`timescale 1ns / 1ps

module image_saturation_analyzer #(
    parameter integer FRAME_WIDTH         = 640,
    parameter integer FRAME_HEIGHT        = 480,
    parameter [7:0]   SAT_DIFF_THRESHOLD  = 8'd40,
    parameter [7:0]   VALUE_THRESHOLD     = 8'd80,
    parameter [31:0] COUNT_TOLERANCE      = 32'd2000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pixel_valid,
    input  wire [23:0] pixel_data,
    output reg  [3:0]  result_digit
);

    localparam integer HALF_WIDTH      = FRAME_WIDTH / 2;
    localparam [31:0]  COUNT_TOL       = COUNT_TOLERANCE;

    reg [11:0]  column_index;
    reg [11:0]  row_index;
    reg [31:0]  left_count;
    reg [31:0]  right_count;

    wire [7:0] pixel_b = pixel_data[23:16];
    wire [7:0] pixel_r = pixel_data[15:8];
    wire [7:0] pixel_g = pixel_data[7:0];

    wire [7:0] max_rg  = (pixel_r > pixel_g) ? pixel_r : pixel_g;
    wire [7:0] min_rg  = (pixel_r < pixel_g) ? pixel_r : pixel_g;
    wire [7:0] max_rgb = (max_rg  > pixel_b) ? max_rg  : pixel_b;
    wire [7:0] min_rgb = (min_rg  < pixel_b) ? min_rg  : pixel_b;

    wire [7:0] saturation_span = max_rgb - min_rgb;

    wire high_saturation_pixel = (max_rgb >= VALUE_THRESHOLD) && (saturation_span >= SAT_DIFF_THRESHOLD);
    wire is_left_half          = (column_index < HALF_WIDTH);

    wire [31:0] left_count_with_pixel  = (pixel_valid && high_saturation_pixel && is_left_half)
                                         ? left_count + 32'd1 : left_count;
    wire [31:0] right_count_with_pixel = (pixel_valid && high_saturation_pixel && !is_left_half)
                                         ? right_count + 32'd1 : right_count;

    wire last_column  = (column_index == FRAME_WIDTH  - 1);
    wire last_row     = (row_index    == FRAME_HEIGHT - 1);
    wire at_frame_end = pixel_valid && last_column && last_row;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column_index <= 12'd0;
            row_index    <= 12'd0;
            left_count   <= 32'd0;
            right_count  <= 32'd0;
            result_digit <= 4'd2;
        end else if (pixel_valid) begin
            if (at_frame_end) begin
                if (left_count_with_pixel > right_count_with_pixel + COUNT_TOL) begin
                    result_digit <= 4'd1;
                end else if (right_count_with_pixel > left_count_with_pixel + COUNT_TOL) begin
                    result_digit <= 4'd3;
                end else begin
                    result_digit <= 4'd2;
                end

                column_index <= 12'd0;
                row_index    <= 12'd0;
                left_count   <= 32'd0;
                right_count  <= 32'd0;
            end else begin
                left_count  <= left_count_with_pixel;
                right_count <= right_count_with_pixel;

                if (last_column) begin
                    column_index <= 12'd0;
                    if (last_row) begin
                        row_index <= 12'd0;
                    end else begin
                        row_index <= row_index + 12'd1;
                    end
                end else begin
                    column_index <= column_index + 12'd1;
                end
            end
        end
    end

endmodule
