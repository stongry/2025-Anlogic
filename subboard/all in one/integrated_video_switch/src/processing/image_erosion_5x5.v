`timescale 1ns / 1ps
//--------------------------------------------------------------------------
// Streaming 5x5 binary erosion (top/left padded).
// Uses four line buffers to hold the previous rows and builds a 5x5 window
// on-the-fly. The output valid follows the input valid so that upstream
// packet sizes remain unchanged; border pixels are forced to zero.
//--------------------------------------------------------------------------
module image_erosion_5x5 #(
    parameter integer FRAME_WIDTH  = 640,
    parameter integer FRAME_HEIGHT = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire        pixel_valid,
    input  wire [23:0] pixel_data,
    output reg         erosion_valid,
    output reg  [23:0] erosion_rgb
);

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for(i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer COL_W = clog2(FRAME_WIDTH);
    localparam integer ROW_W = clog2(FRAME_HEIGHT);

    wire pixel_bit = pixel_data[23];

    reg [FRAME_WIDTH-1:0] linebuf1;
    reg [FRAME_WIDTH-1:0] linebuf2;
    reg [FRAME_WIDTH-1:0] linebuf3;
    reg [FRAME_WIDTH-1:0] linebuf4;

    reg [4:0] window0;
    reg [4:0] window1;
    reg [4:0] window2;
    reg [4:0] window3;
    reg [4:0] window4;

    reg [COL_W-1:0] col_cnt;
    reg [ROW_W-1:0] row_cnt;

    wire [COL_W-1:0] col_idx = frame_start ? {COL_W{1'b0}} : col_cnt;
    wire [ROW_W-1:0] row_idx = frame_start ? {ROW_W{1'b0}} : row_cnt;
    wire start_of_row = frame_start || (col_idx == {COL_W{1'b0}});

    wire prev1 = linebuf1[col_idx];
    wire prev2 = linebuf2[col_idx];
    wire prev3 = linebuf3[col_idx];
    wire prev4 = linebuf4[col_idx];

    wire [4:0] window0_next = start_of_row ? {4'd0, pixel_bit} : {window0[3:0], pixel_bit};
    wire [4:0] window1_next = start_of_row ? {4'd0, prev1     } : {window1[3:0], prev1     };
    wire [4:0] window2_next = start_of_row ? {4'd0, prev2     } : {window2[3:0], prev2     };
    wire [4:0] window3_next = start_of_row ? {4'd0, prev3     } : {window3[3:0], prev3     };
    wire [4:0] window4_next = start_of_row ? {4'd0, prev4     } : {window4[3:0], prev4     };

    wire window_ready = (row_idx >= 4) && (col_idx >= 4);
    wire erosion_bit  = (&window0_next) & (&window1_next) & (&window2_next)
                      & (&window3_next) & (&window4_next);
    wire [7:0] erosion_byte = window_ready ? {8{erosion_bit}} : 8'd0;

    // ------------------------------------------------------------------
    // State updates
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            linebuf1 <= {FRAME_WIDTH{1'b0}};
            linebuf2 <= {FRAME_WIDTH{1'b0}};
            linebuf3 <= {FRAME_WIDTH{1'b0}};
            linebuf4 <= {FRAME_WIDTH{1'b0}};
        end else if(pixel_valid) begin
            linebuf4[col_idx] <= linebuf3[col_idx];
            linebuf3[col_idx] <= linebuf2[col_idx];
            linebuf2[col_idx] <= linebuf1[col_idx];
            linebuf1[col_idx] <= pixel_bit;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            window0 <= 5'd0;
            window1 <= 5'd0;
            window2 <= 5'd0;
            window3 <= 5'd0;
            window4 <= 5'd0;
        end else if(pixel_valid) begin
            window0 <= window0_next;
            window1 <= window1_next;
            window2 <= window2_next;
            window3 <= window3_next;
            window4 <= window4_next;
        end else if(frame_start) begin
            window0 <= 5'd0;
            window1 <= 5'd0;
            window2 <= 5'd0;
            window3 <= 5'd0;
            window4 <= 5'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            col_cnt <= {COL_W{1'b0}};
            row_cnt <= {ROW_W{1'b0}};
        end else if(pixel_valid) begin
            if(frame_start) begin
                col_cnt <= (FRAME_WIDTH > 1) ? {{(COL_W-1){1'b0}}, 1'b1} : {COL_W{1'b0}};
                row_cnt <= {ROW_W{1'b0}};
            end else if(col_cnt == FRAME_WIDTH-1) begin
                col_cnt <= {COL_W{1'b0}};
                if(row_cnt == FRAME_HEIGHT-1)
                    row_cnt <= {ROW_W{1'b0}};
                else
                    row_cnt <= row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end else if(frame_start) begin
            col_cnt <= {COL_W{1'b0}};
            row_cnt <= {ROW_W{1'b0}};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            erosion_valid <= 1'b0;
            erosion_rgb   <= 24'd0;
        end else begin
            erosion_valid <= pixel_valid;
            if(pixel_valid)
                erosion_rgb <= {erosion_byte, erosion_byte, erosion_byte};
        end
    end

endmodule
