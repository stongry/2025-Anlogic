`timescale 1ns / 1ps
//--------------------------------------------------------------------------
// Simple streaming image binarizer.
// Receives 24-bit RGB pixel stream, derives an approximate luminance value
// and emits a binarized pixel (all channels 0x00 or 0xFF). Designed to sit
// between the SDRAM reader and UDP packetizer so that an entire frame is
// converted before transmission.
//--------------------------------------------------------------------------
module image_binarizer #(
    parameter integer FRAME_WIDTH   = 640,
    parameter integer FRAME_HEIGHT  = 480,
    parameter [7:0]   THRESHOLD     = 8'd128
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pixel_valid,
    input  wire [23:0] pixel_data,
    output reg         binary_valid,
    output reg  [23:0] binary_data,
    output reg         frame_start,
    output reg         frame_done
);

    localparam integer FRAME_PIXEL_COUNT = FRAME_WIDTH * FRAME_HEIGHT;

    // ----------------------------------------------------------------------
    // cLog2 helper to size the pixel counter.
    // ----------------------------------------------------------------------
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for(i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer COUNTER_WIDTH = clog2(FRAME_PIXEL_COUNT);

    reg [COUNTER_WIDTH-1:0] pixel_count;

    wire [7:0] pixel_r = pixel_data[23:16];
    wire [7:0] pixel_g = pixel_data[15:8];
    wire [7:0] pixel_b = pixel_data[7:0];

    // Weighted-average approximation without an explicit divider.
    wire [9:0]  rgb_sum   = {2'd0, pixel_r} + {2'd0, pixel_g} + {2'd0, pixel_b};
    wire [17:0] gray_mult = rgb_sum * 8'd85;          // ≈ sum / 3
    wire [7:0]  gray_lvl  = gray_mult[15:8];
    wire        binary_bit = (gray_lvl >= THRESHOLD);
    wire [7:0]  binary_value = binary_bit ? 8'hFF : 8'h00;
    wire [23:0] binary_word  = {binary_value, binary_value, binary_value};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            binary_valid <= 1'b0;
            binary_data  <= 24'd0;
        end else begin
            binary_valid <= pixel_valid;
            if(pixel_valid)
                binary_data <= binary_word;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pixel_count <= {COUNTER_WIDTH{1'b0}};
            frame_start <= 1'b0;
            frame_done  <= 1'b0;
        end else begin
            frame_start <= 1'b0;
            frame_done  <= 1'b0;
            if(pixel_valid) begin
                if(pixel_count == {COUNTER_WIDTH{1'b0}}) begin
                    frame_start <= 1'b1;
                end

                if(pixel_count == FRAME_PIXEL_COUNT - 1) begin
                    pixel_count <= {COUNTER_WIDTH{1'b0}};
                    frame_done  <= 1'b1;
                end else begin
                    pixel_count <= pixel_count + 1'b1;
                end
            end
        end
    end

endmodule
