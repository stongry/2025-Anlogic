`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Modified for continuous camera data transmission with batch sending
// Solves the 2200 pixel limitation by implementing circular batch transmission
//////////////////////////////////////////////////////////////////////////////////

`define DEBUG
`include "../include/global_def.v"

module app_wrrd
	(
		input   clk,
        input   rst_n,
		input   sd_clk,
		input			Sdr_init_done,
		input			Sdr_init_ref_vld,
		input   		full_flag_net,
		input                sdr_data_valid,
		input     [23:0]     sdr_data,
		input 				 Sdr_busy,
        output						App_wr_en,
        output  [`ADDR_WIDTH-1:0]	App_wr_addr,
		output	[`DM_WIDTH-1:0]		App_wr_dm,
		output	[`DATA_WIDTH-1:0]	App_wr_din,

		output						App_rd_en,
		output	reg [`ADDR_WIDTH-1:0]	App_rd_addr,
		input						Sdr_rd_en,
		input	[`DATA_WIDTH-1:0]	Sdr_rd_dout,
        output  full_flag,
		output reg            wr_done,
		input  [11:0 ] udp_wrusedw
	);

// Write side - unchanged from original
reg [18:0]w_addr_cnt;
wire wr_done_debug;
assign wr_done_debug = wr_done;
assign App_wr_dm = 4'b0;

reg [8:0] wr_fifo_cnt;
wire  [9:0] rdusedw;
wire  [23:0] sdr_rd_data;
reg wr_fifo_rd_en;
wire empty_flag;

fifo_sdr_data_2 u_wr_fifo_sdr_data(
   .rst			   			(~rst_n		),
   .clkw		   			(sd_clk		),
   .clkr		   			(clk		),
   .we			   			(sdr_data_valid),
   .di			   			(sdr_data),
   .re			   			(wr_fifo_rd_en),
   .dout		    	        (App_wr_din),
   .valid		     	        (),
   .full_flag	    	        (full_flag),
   .empty_flag	    	        (empty_flag),
   .afull		    	        (afull),
   .aempty		    	        (aempty),
   .wrusedw	  	    	    (wrusedw),
   .rdusedw 	    	        (rdusedw)
);

assign App_wr_en = wr_fifo_rd_en;
reg wr_fifo_rd_en_reg;

reg [1:0] brust_rd_cnt;
reg empty_flag_reg;

always @(posedge clk) begin
    empty_flag_reg <= empty_flag;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        wr_fifo_rd_en <= 1'b0;
    else if(!Sdr_busy & Sdr_init_ref_vld == 1'b0 & w_addr_cnt <= 19'd307199 & (rdusedw > 4))
        wr_fifo_rd_en <= 1'b1;
    else if(!Sdr_busy & Sdr_init_ref_vld == 1'b0 & w_addr_cnt == 19'd307196 & (rdusedw == 4))
        wr_fifo_rd_en <= 1'b1;
    else if(brust_rd_cnt == 3)
        wr_fifo_rd_en <= 1'b0;
    else
        wr_fifo_rd_en <= wr_fifo_rd_en;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        brust_rd_cnt <= 2'b0;
    else if(wr_fifo_rd_en & (brust_rd_cnt < 3))
        brust_rd_cnt <= brust_rd_cnt + 1;
    else if(wr_fifo_rd_en & (brust_rd_cnt == 3))
        brust_rd_cnt <= 2'b0;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        wr_fifo_rd_en_reg <= 1'b0;
    else
        wr_fifo_rd_en_reg <= wr_fifo_rd_en;
end

// Write address counter
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b0;
    end
    else if(App_wr_en & w_addr_cnt < 19'd307199)
        w_addr_cnt <= w_addr_cnt + 1'b1;
    else if(App_wr_en & w_addr_cnt == 19'd307199) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b1;
    end
    else begin
        w_addr_cnt <= w_addr_cnt;
        wr_done <= wr_done;
    end
end

reg [15:0]sdr_rd_delay;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sdr_rd_delay <= 16'b0;
    end
    else if(wr_done & sdr_rd_delay < 16'd1000)
        sdr_rd_delay <= sdr_rd_delay + 1'b1;
    else
        sdr_rd_delay <= sdr_rd_delay;
end

assign App_wr_addr = w_addr_cnt;

// ============ MODIFIED READ SIDE - Circular Batch Transmission ============

// Batch transmission parameters
localparam BATCH_SIZE = 19'd1500;      // Send 1500 pixels per batch
localparam FRAME_SIZE = 19'd307200;    // Total frame size
localparam FIFO_LOW_THRESH = 12'd200;  // Start new batch when FIFO < 200

reg [18:0] r_addr_cnt;        // Current read address in SDRAM
reg [18:0] batch_cnt;         // Pixels sent in current batch
reg [2:0] batch_state;        // Batch transmission state machine
reg app_rd_en_reg;
reg rd_done;
reg [1:0] burst_sdr_rd_cnt;
reg [18:0] total_sent_cnt;    // Total pixels sent in current frame

// Batch state machine
localparam IDLE = 3'd0;
localparam WAIT_FIFO = 3'd1;
localparam SEND_BATCH = 3'd2;
localparam BATCH_DONE = 3'd3;
localparam FRAME_DONE = 3'd4;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        batch_state <= IDLE;
        r_addr_cnt <= 19'b0;
        batch_cnt <= 19'b0;
        total_sent_cnt <= 19'b0;
        app_rd_en_reg <= 1'b0;
        rd_done <= 1'b0;
    end
    else begin
        case(batch_state)
            IDLE: begin
                // Wait for SDRAM write to complete
                if(sdr_rd_delay == 16'd1000 && !rd_done) begin
                    batch_state <= WAIT_FIFO;
                    r_addr_cnt <= 19'b0;
                    batch_cnt <= 19'b0;
                    total_sent_cnt <= 19'b0;
                end
            end

            WAIT_FIFO: begin
                // Wait for UDP FIFO to have space
                if(udp_wrusedw < FIFO_LOW_THRESH && !Sdr_busy && Sdr_init_ref_vld == 1'b0) begin
                    batch_state <= SEND_BATCH;
                    batch_cnt <= 19'b0;
                end
            end

            SEND_BATCH: begin
                // Send a batch of pixels
                if(!Sdr_busy && Sdr_init_ref_vld == 1'b0 && burst_sdr_rd_cnt == 2'b0) begin
                    if(batch_cnt < BATCH_SIZE && total_sent_cnt < FRAME_SIZE) begin
                        app_rd_en_reg <= 1'b1;
                        r_addr_cnt <= r_addr_cnt + 1'b1;
                        batch_cnt <= batch_cnt + 1'b1;
                        total_sent_cnt <= total_sent_cnt + 1'b1;
                    end
                    else begin
                        app_rd_en_reg <= 1'b0;
                        batch_state <= BATCH_DONE;
                    end
                end
                // Handle burst read
                else if(!Sdr_busy && Sdr_init_ref_vld == 1'b0 && burst_sdr_rd_cnt > 0 && burst_sdr_rd_cnt < 3) begin
                    app_rd_en_reg <= 1'b1;
                    r_addr_cnt <= r_addr_cnt + 1'b1;
                    batch_cnt <= batch_cnt + 1'b1;
                    total_sent_cnt <= total_sent_cnt + 1'b1;
                end
                else if(burst_sdr_rd_cnt == 3) begin
                    app_rd_en_reg <= 1'b0;
                end
            end

            BATCH_DONE: begin
                // Check if frame is complete
                if(total_sent_cnt >= FRAME_SIZE - 1) begin
                    batch_state <= FRAME_DONE;
                    rd_done <= 1'b1;
                end
                else begin
                    // Wait before starting next batch
                    batch_state <= WAIT_FIFO;
                end
            end

            FRAME_DONE: begin
                // Frame complete, start over for continuous transmission
                rd_done <= 1'b0;
                batch_state <= IDLE;
                r_addr_cnt <= 19'b0;
                total_sent_cnt <= 19'b0;
            end
        endcase
    end
end

// Burst counter for SDRAM reads
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        burst_sdr_rd_cnt <= 2'b0;
    else if(app_rd_en_reg & (burst_sdr_rd_cnt < 3))
        burst_sdr_rd_cnt <= burst_sdr_rd_cnt + 1;
    else if(app_rd_en_reg & (burst_sdr_rd_cnt == 3))
        burst_sdr_rd_cnt <= 2'b0;
end

assign App_rd_en = app_rd_en_reg;

// Read address output
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        App_rd_addr <= 19'b0;
    end
    else if(App_rd_en) begin
        if(App_rd_addr < 19'd307199)
            App_rd_addr <= App_rd_addr + 1'b1;
        else
            App_rd_addr <= 19'b0;  // Wrap around for circular buffer
    end
    else begin
        App_rd_addr <= App_rd_addr;
    end
end

// Debug counters
reg [18:0] sdr_rd_cnt;
reg sdr_rd_done;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sdr_rd_cnt <= 19'b0;
        sdr_rd_done <= 1'b0;
    end
    else if(Sdr_rd_en & !sdr_rd_done) begin
        sdr_rd_cnt <= sdr_rd_cnt + 1'b1;
    end
    else if(sdr_rd_cnt == 19'd307199) begin
        sdr_rd_done <= 1'b1;
    end
    else begin
        sdr_rd_cnt <= sdr_rd_cnt;
        sdr_rd_done <= sdr_rd_done;
    end
end

endmodule