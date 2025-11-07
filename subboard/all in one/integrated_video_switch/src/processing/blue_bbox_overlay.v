`timescale 1ns / 1ps

module blue_bbox_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        pixel_valid,
    input  wire [7:0]  in_r,
    input  wire [7:0]  in_g,
    input  wire [7:0]  in_b,
    input  wire        is_blue,
    output wire [7:0]  out_r,
    output wire [7:0]  out_g,
    output wire [7:0]  out_b,
    output wire        frame_start_o,
    output wire        frame_end_o,
    output wire        has_bbox,
    output wire [9:0]  bbox_min_x,
    output wire [9:0]  bbox_max_x,
    output wire [8:0]  bbox_min_y,
    output wire [8:0]  bbox_max_y,
    output wire [9:0]  divider_x0_o,
    output wire [9:0]  divider_x1_o,
    output wire [9:0]  divider_x2_o,
    output wire [9:0]  divider_x3_o,
    output wire [9:0]  divider_x4_o,
    output wire [9:0]  divider_x5_o
);
    localparam [9:0] H_MAX_VAL = H_ACTIVE > 0 ? H_ACTIVE - 1 : 0;
    localparam [8:0] V_MAX_VAL = V_ACTIVE > 0 ? V_ACTIVE - 1 : 0;

    reg [9:0] x_cnt;
    reg [8:0] y_cnt;
    reg        pixel_valid_d;
    wire       frame_start;
    wire       frame_end;

    reg        blue_found_cur;
    reg [9:0]  bbox_min_x_cur;
    reg [9:0]  bbox_max_x_cur;
    reg [8:0]  bbox_min_y_cur;
    reg [8:0]  bbox_max_y_cur;

    reg        has_bbox_prev;
    reg [9:0]  bbox_min_x_prev;
    reg [9:0]  bbox_max_x_prev;
    reg [8:0]  bbox_min_y_prev;
    reg [8:0]  bbox_max_y_prev;

    localparam [7:0] YELLOW_R = 8'hFF;
    localparam [7:0] YELLOW_G = 8'hFF;
    localparam [7:0] YELLOW_B = 8'h00;

    localparam integer RATIO_DENOM      = 1000000;
    localparam integer RATIO_HALF_DENOM = RATIO_DENOM / 2;
    localparam integer RATIO_0_NUM      = 330103;
    localparam integer RATIO_1_NUM      = 456693;
    localparam integer RATIO_2_NUM      = 589945;
    localparam integer RATIO_3_NUM      = 721381;
    localparam integer RATIO_4_NUM      = 847365;
    localparam integer RATIO_5_NUM      = 981829;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_valid_d <= 1'b0;
        end else begin
            pixel_valid_d <= pixel_valid;
        end
    end

    assign frame_start =  pixel_valid && !pixel_valid_d;
    assign frame_end   = !pixel_valid &&  pixel_valid_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_cnt <= 10'd0;
            y_cnt <= 9'd0;
        end else if (pixel_valid) begin
            if (frame_start) begin
                x_cnt <= 10'd0;
                y_cnt <= 9'd0;
            end else if (x_cnt == H_MAX_VAL) begin
                x_cnt <= 10'd0;
                if (y_cnt == V_MAX_VAL) begin
                    y_cnt <= 9'd0;
                end else begin
                    y_cnt <= y_cnt + 9'd1;
                end
            end else begin
                x_cnt <= x_cnt + 10'd1;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            blue_found_cur <= 1'b0;
            bbox_min_x_cur <= H_MAX_VAL;
            bbox_max_x_cur <= 10'd0;
            bbox_min_y_cur <= V_MAX_VAL;
            bbox_max_y_cur <= 9'd0;
        end else begin
            if (frame_start) begin
                blue_found_cur <= 1'b0;
                bbox_min_x_cur <= H_MAX_VAL;
                bbox_max_x_cur <= 10'd0;
                bbox_min_y_cur <= V_MAX_VAL;
                bbox_max_y_cur <= 9'd0;
            end
            if (pixel_valid && is_blue) begin
                if (!blue_found_cur || frame_start) begin
                    bbox_min_x_cur <= x_cnt;
                    bbox_max_x_cur <= x_cnt;
                    bbox_min_y_cur <= y_cnt;
                    bbox_max_y_cur <= y_cnt;
                end else begin
                    if (x_cnt < bbox_min_x_cur)
                        bbox_min_x_cur <= x_cnt;
                    if (x_cnt > bbox_max_x_cur)
                        bbox_max_x_cur <= x_cnt;
                    if (y_cnt < bbox_min_y_cur)
                        bbox_min_y_cur <= y_cnt;
                    if (y_cnt > bbox_max_y_cur)
                        bbox_max_y_cur <= y_cnt;
                end
                blue_found_cur <= 1'b1;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            has_bbox_prev  <= 1'b0;
            bbox_min_x_prev <= 10'd0;
            bbox_max_x_prev <= 10'd0;
            bbox_min_y_prev <= 9'd0;
            bbox_max_y_prev <= 9'd0;
        end else if (frame_end) begin
            has_bbox_prev  <= blue_found_cur;
            bbox_min_x_prev <= bbox_min_x_cur;
            bbox_max_x_prev <= bbox_max_x_cur;
            bbox_min_y_prev <= bbox_min_y_cur;
            bbox_max_y_prev <= bbox_max_y_cur;
        end
    end

    wire within_bbox;
    wire on_bbox_edge;
    wire [9:0] divider_x0;
    wire [9:0] divider_x1;
    wire [9:0] divider_x2;
    wire [9:0] divider_x3;
    wire [9:0] divider_x4;
    wire [9:0] divider_x5;
    wire       on_divider;

    function automatic [9:0] calc_line_pos;
        input [9:0] min_x;
        input [9:0] max_x;
        input integer ratio_num;
        reg [9:0] width;
        reg [31:0] scaled;
        reg [31:0] offset;
        reg [9:0] pos;
        begin
            if (max_x > min_x)
                width = max_x - min_x;
            else
                width = 10'd0;
            scaled = (width * ratio_num) + RATIO_HALF_DENOM;
            offset = scaled / RATIO_DENOM;
            pos = min_x + offset[9:0];
            if (pos > max_x)
                pos = max_x;
            if (pos < min_x)
                pos = min_x;
            calc_line_pos = pos;
        end
    endfunction

    assign within_bbox = has_bbox_prev &&
                         (x_cnt >= bbox_min_x_prev) && (x_cnt <= bbox_max_x_prev) &&
                         (y_cnt >= bbox_min_y_prev) && (y_cnt <= bbox_max_y_prev);

    assign on_bbox_edge = within_bbox &&
                          ((x_cnt == bbox_min_x_prev) || (x_cnt == bbox_max_x_prev) ||
                           (y_cnt == bbox_min_y_prev) || (y_cnt == bbox_max_y_prev));

    assign divider_x0 = calc_line_pos(bbox_min_x_prev, bbox_max_x_prev, RATIO_0_NUM);
    assign divider_x1 = calc_line_pos(bbox_min_x_prev, bbox_max_x_prev, RATIO_1_NUM);
    assign divider_x2 = calc_line_pos(bbox_min_x_prev, bbox_max_x_prev, RATIO_2_NUM);
    assign divider_x3 = calc_line_pos(bbox_min_x_prev, bbox_max_x_prev, RATIO_3_NUM);
    assign divider_x4 = calc_line_pos(bbox_min_x_prev, bbox_max_x_prev, RATIO_4_NUM);
    assign divider_x5 = calc_line_pos(bbox_min_x_prev, bbox_max_x_prev, RATIO_5_NUM);

    assign on_divider = has_bbox_prev &&
                        (y_cnt >= bbox_min_y_prev) && (y_cnt <= bbox_max_y_prev) &&
                        ((x_cnt == divider_x0) || (x_cnt == divider_x1) ||
                         (x_cnt == divider_x2) || (x_cnt == divider_x3) ||
                         (x_cnt == divider_x4) || (x_cnt == divider_x5));

    assign out_r = (on_bbox_edge || on_divider) ? YELLOW_R : in_r;
    assign out_g = (on_bbox_edge || on_divider) ? YELLOW_G : in_g;
    assign out_b = (on_bbox_edge || on_divider) ? YELLOW_B : in_b;

    assign frame_start_o  = frame_start;
    assign frame_end_o    = frame_end;
    assign has_bbox       = has_bbox_prev;
    assign bbox_min_x     = bbox_min_x_prev;
    assign bbox_max_x     = bbox_max_x_prev;
    assign bbox_min_y     = bbox_min_y_prev;
    assign bbox_max_y     = bbox_max_y_prev;
    assign divider_x0_o   = divider_x0;
    assign divider_x1_o   = divider_x1;
    assign divider_x2_o   = divider_x2;
    assign divider_x3_o   = divider_x3;
    assign divider_x4_o   = divider_x4;
    assign divider_x5_o   = divider_x5;

endmodule
