`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Sobel edge filter for streaming RGB data
// - Converts incoming RGB pixels to grayscale
// - Applies 3x3 Sobel operator
// - Replicates gradient magnitude to RGB channels
// - Edges (first/last two rows/columns) output zero due to incomplete kernel
// -----------------------------------------------------------------------------
module sobel_filter #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [23:0] in_pixel,
    output reg         out_valid,
    output reg  [23:0] out_pixel
);

    localparam integer X_CNT_WIDTH = 12;
    localparam integer Y_CNT_WIDTH = 12;

    // grayscale conversion helpers
    wire [7:0] pixel_r = in_pixel[23:16];
    wire [7:0] pixel_g = in_pixel[15:8];
    wire [7:0] pixel_b = in_pixel[7:0];

    wire [15:0] gray_calc = pixel_r * 8'd76 + pixel_g * 8'd150 + pixel_b * 8'd29;
    wire [7:0]  gray_curr = gray_calc[15:8];

    // line buffers hold two previous rows of grayscale data
    reg [7:0] linebuf0 [0:IMG_WIDTH-1];
    reg [7:0] linebuf1 [0:IMG_WIDTH-1];

    reg [7:0] row0_shift0;
    reg [7:0] row0_shift1;
    reg [7:0] row1_shift0;
    reg [7:0] row1_shift1;
    reg [7:0] row2_shift0;
    reg [7:0] row2_shift1;

    reg [X_CNT_WIDTH-1:0] x_cnt;
    reg [Y_CNT_WIDTH-1:0] y_cnt;
    reg                    frame_new;

    // stage registers capturing 3x3 window
    reg [7:0] win00, win01, win02;
    reg [7:0] win10, win11, win12;
    reg [7:0] win20, win21, win22;
    reg       win_valid;
    reg [X_CNT_WIDTH-1:0] x_cnt_d;
    reg [Y_CNT_WIDTH-1:0] y_cnt_d;

    wire [7:0] prev_row_curr   = (y_cnt == 0) ? 8'd0 : linebuf0[x_cnt];
    wire [7:0] prev2_row_curr  = (y_cnt <= 1) ? 8'd0 : linebuf1[x_cnt];

    wire last_pixel = (x_cnt == IMG_WIDTH-1) && (y_cnt == IMG_HEIGHT-1);
    wire frame_start = frame_new && in_valid;

    // pixel counters (wrap at frame end)
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x_cnt         <= {X_CNT_WIDTH{1'b0}};
            y_cnt         <= {Y_CNT_WIDTH{1'b0}};
            frame_new     <= 1'b1;
        end else begin
            if(in_valid) begin
                if(x_cnt == IMG_WIDTH-1) begin
                    x_cnt <= {X_CNT_WIDTH{1'b0}};
                    if(y_cnt == IMG_HEIGHT-1)
                        y_cnt <= {Y_CNT_WIDTH{1'b0}};
                    else
                        y_cnt <= y_cnt + 1'b1;
                end else begin
                    x_cnt <= x_cnt + 1'b1;
                end

                if(last_pixel)
                    frame_new <= 1'b1;
                else
                    frame_new <= 1'b0;
            end
        end
    end

    // build 3x3 window and update line buffers
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            row0_shift0 <= 8'd0;
            row0_shift1 <= 8'd0;
            row1_shift0 <= 8'd0;
            row1_shift1 <= 8'd0;
            row2_shift0 <= 8'd0;
            row2_shift1 <= 8'd0;
            win00       <= 8'd0;
            win01       <= 8'd0;
            win02       <= 8'd0;
            win10       <= 8'd0;
            win11       <= 8'd0;
            win12       <= 8'd0;
            win20       <= 8'd0;
            win21       <= 8'd0;
            win22       <= 8'd0;
            win_valid   <= 1'b0;
            x_cnt_d     <= {X_CNT_WIDTH{1'b0}};
            y_cnt_d     <= {Y_CNT_WIDTH{1'b0}};
        end else begin
            if(in_valid) begin
                if(frame_start) begin
                    win00 <= 8'd0;
                    win01 <= 8'd0;
                    win02 <= 8'd0;
                    win10 <= 8'd0;
                    win11 <= 8'd0;
                    win12 <= 8'd0;
                    win20 <= 8'd0;
                    win21 <= 8'd0;
                    win22 <= gray_curr;

                    row0_shift0 <= 8'd0;
                    row0_shift1 <= 8'd0;
                    row1_shift0 <= 8'd0;
                    row1_shift1 <= 8'd0;
                    row2_shift0 <= 8'd0;
                    row2_shift1 <= 8'd0;
                end else begin
                    // capture current 3x3 window before updating buffers
                    win00 <= row2_shift1;
                    win01 <= row2_shift0;
                    win02 <= prev2_row_curr;
                    win10 <= row1_shift1;
                    win11 <= row1_shift0;
                    win12 <= prev_row_curr;
                    win20 <= row0_shift1;
                    win21 <= row0_shift0;
                    win22 <= gray_curr;

                    // shift current line pixels
                    row0_shift1 <= row0_shift0;
                    row0_shift0 <= gray_curr;

                    // previous line
                    row1_shift1 <= row1_shift0;
                    row1_shift0 <= prev_row_curr;

                    // line -2
                    row2_shift1 <= row2_shift0;
                    row2_shift0 <= prev2_row_curr;
                end

                win_valid <= 1'b1;
                x_cnt_d   <= x_cnt;
                y_cnt_d   <= y_cnt;

                // update line buffers (write current grayscale)
                if(y_cnt == {Y_CNT_WIDTH{1'b0}})
                    linebuf1[x_cnt] <= 8'd0;
                else
                    linebuf1[x_cnt] <= linebuf0[x_cnt];
                linebuf0[x_cnt] <= gray_curr;
            end else begin
                win_valid <= 1'b0;
            end
        end
    end

    // Sobel gradient calculation
    wire signed [10:0] s00 = {3'b0, win00};
    wire signed [10:0] s01 = {3'b0, win01};
    wire signed [10:0] s02 = {3'b0, win02};
    wire signed [10:0] s10 = {3'b0, win10};
    wire signed [10:0] s11 = {3'b0, win11};
    wire signed [10:0] s12 = {3'b0, win12};
    wire signed [10:0] s20 = {3'b0, win20};
    wire signed [10:0] s21 = {3'b0, win21};
    wire signed [10:0] s22 = {3'b0, win22};

    wire signed [11:0] gx = -s00 - (s10 <<< 1) - s20
                            + s02 + (s12 <<< 1) + s22;
    wire signed [11:0] gy =  s00 + (s01 <<< 1) + s02
                            - s20 - (s21 <<< 1) - s22;

    wire [11:0] abs_gx = gx[11] ? (~gx + 12'd1) : gx;
    wire [11:0] abs_gy = gy[11] ? (~gy + 12'd1) : gy;
    wire [12:0] mag_sum = abs_gx + abs_gy;
    wire [7:0]  mag_sat = (mag_sum > 13'd255) ? 8'hff : mag_sum[7:0];

    wire window_ready = (x_cnt_d >= 2) && (y_cnt_d >= 2);
    wire border_pixel = (x_cnt_d <= 2) || (x_cnt_d >= IMG_WIDTH) ||
                        (y_cnt_d <= 2) || (y_cnt_d >= IMG_HEIGHT);

    // output pipeline
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            out_valid <= 1'b0;
            out_pixel <= 24'd0;
        end else begin
            out_valid <= win_valid;
            if(win_valid) begin
                if(window_ready && !border_pixel)
                    out_pixel <= {mag_sat, mag_sat, mag_sat};
                else
                    out_pixel <= 24'd0;
            end else begin
                out_pixel <= 24'd0;
            end
        end
    end

endmodule
