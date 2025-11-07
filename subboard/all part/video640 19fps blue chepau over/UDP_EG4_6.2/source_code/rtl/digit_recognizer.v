`timescale 1ns / 1ps

module digit_recognizer #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
)( 
    input  wire        clk,
    input  wire        rst,
    input  wire        pixel_valid,
    input  wire        frame_start,
    input  wire        frame_end,
    input  wire        has_bbox,
    input  wire [9:0]  bbox_min_x,
    input  wire [9:0]  bbox_max_x,
    input  wire [8:0]  bbox_min_y,
    input  wire [8:0]  bbox_max_y,
    input  wire [9:0]  divider_x0,
    input  wire [9:0]  divider_x1,
    input  wire [9:0]  divider_x2,
    input  wire [9:0]  divider_x3,
    input  wire [9:0]  divider_x4,
    input  wire [9:0]  divider_x5,
    input  wire        is_blue,
    output reg  [3:0]  digit0,
    output reg  [3:0]  digit1,
    output reg  [3:0]  digit2,
    output reg  [3:0]  digit3,
    output reg  [3:0]  digit4,
    output reg         digits_valid
);
    localparam integer H_MAX_VAL = H_ACTIVE > 0 ? H_ACTIVE - 1 : 0;
    localparam integer V_MAX_VAL = V_ACTIVE > 0 ? V_ACTIVE - 1 : 0;

    localparam [2:0] ST_CLEAR    = 3'd0;
    localparam [2:0] ST_WAIT     = 3'd1;
    localparam [2:0] ST_CAPTURE  = 3'd2;
    localparam [2:0] ST_RECOG    = 3'd3;

    localparam [1:0] SUB_IDLE    = 2'd0;
    localparam [1:0] SUB_REQ     = 2'd1;
    localparam [1:0] SUB_PROC    = 2'd2;

    localparam [3:0] DIGIT_BLANK = 4'hF;

    reg [2:0] state;
    reg [1:0] recog_substate;

    reg [5:0] clear_row;

    reg        has_bbox_frame;
    reg [9:0]  bbox_min_x_frame;
    reg [9:0]  bbox_max_x_frame;
    reg [8:0]  bbox_min_y_frame;
    reg [8:0]  bbox_max_y_frame;
    reg [9:0]  divider_frame0;
    reg [9:0]  divider_frame1;
    reg [9:0]  divider_frame2;
    reg [9:0]  divider_frame3;
    reg [9:0]  divider_frame4;
    reg [9:0]  divider_frame5;

    wire [9:0] seg_left0  = (divider_frame0 < divider_frame1) ? (divider_frame0 + 10'd1) : divider_frame0;
    wire [9:0] seg_right0 = divider_frame1;
    wire [9:0] seg_left1  = (divider_frame1 < divider_frame2) ? (divider_frame1 + 10'd1) : divider_frame1;
    wire [9:0] seg_right1 = divider_frame2;
    wire [9:0] seg_left2  = (divider_frame2 < divider_frame3) ? (divider_frame2 + 10'd1) : divider_frame2;
    wire [9:0] seg_right2 = divider_frame3;
    wire [9:0] seg_left3  = (divider_frame3 < divider_frame4) ? (divider_frame3 + 10'd1) : divider_frame3;
    wire [9:0] seg_right3 = divider_frame4;
    wire [9:0] seg_left4  = (divider_frame4 < divider_frame5) ? (divider_frame4 + 10'd1) : divider_frame4;
    wire [9:0] seg_right4 = divider_frame5;

    wire [9:0] seg_width0 = (seg_right0 > seg_left0) ? (seg_right0 - seg_left0) : 10'd1;
    wire [9:0] seg_width1 = (seg_right1 > seg_left1) ? (seg_right1 - seg_left1) : 10'd1;
    wire [9:0] seg_width2 = (seg_right2 > seg_left2) ? (seg_right2 - seg_left2) : 10'd1;
    wire [9:0] seg_width3 = (seg_right3 > seg_left3) ? (seg_right3 - seg_left3) : 10'd1;
    wire [9:0] seg_width4 = (seg_right4 > seg_left4) ? (seg_right4 - seg_left4) : 10'd1;

    reg [9:0] bbox_height_frame;

    reg [9:0] x_cnt;
    reg [8:0] y_cnt;

    reg [4:0] segment_active;

    reg [27:0] digit_bitmap0 [0:27];
    reg [27:0] digit_bitmap1 [0:27];
    reg [27:0] digit_bitmap2 [0:27];
    reg [27:0] digit_bitmap3 [0:27];
    reg [27:0] digit_bitmap4 [0:27];

    reg [3:0] digit_res0;
    reg [3:0] digit_res1;
    reg [3:0] digit_res2;
    reg [3:0] digit_res3;
    reg [3:0] digit_res4;

    reg [2:0] current_digit;
    reg [3:0] template_idx;
    reg [4:0] row_idx;
    reg [9:0] current_distance;
    reg [9:0] best_distance;
    reg [3:0] best_template;

    reg [2:0] proc_digit;
    reg [3:0] proc_template;
    reg [4:0] proc_row;

    reg [27:0] rom_data_q;
    reg        proc_valid;

    wire [27:0] rom_data;
    reg  [8:0]  rom_addr;

    wire pixel_foreground = pixel_valid && !is_blue;
    wire within_bbox_y = (y_cnt >= bbox_min_y_frame) && (y_cnt <= bbox_max_y_frame);

    ROM_0 u_digit_rom (
        .doa   (rom_data),
        .addra (rom_addr),
        .clka  (clk)
    );

    function automatic [5:0] scale_to_28;
        input [9:0] value;
        input [9:0] range;
        reg [19:0] scaled;
        begin
            if (range <= 1) begin
                scale_to_28 = 6'd0;
            end else begin
                scaled = (value * 10'd28) + (range >> 1);
                scale_to_28 = scaled / range;
                if (scale_to_28 > 6'd27)
                    scale_to_28 = 6'd27;
            end
        end
    endfunction

    function automatic [27:0] get_digit_row;
        input [2:0] idx;
        input [4:0] row;
        begin
            case (idx)
                3'd0: get_digit_row = digit_bitmap0[row];
                3'd1: get_digit_row = digit_bitmap1[row];
                3'd2: get_digit_row = digit_bitmap2[row];
                3'd3: get_digit_row = digit_bitmap3[row];
                3'd4: get_digit_row = digit_bitmap4[row];
                default: get_digit_row = 28'd0;
            endcase
        end
    endfunction

    function automatic [3:0] read_digit_res;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: read_digit_res = digit_res0;
                3'd1: read_digit_res = digit_res1;
                3'd2: read_digit_res = digit_res2;
                3'd3: read_digit_res = digit_res3;
                3'd4: read_digit_res = digit_res4;
                default: read_digit_res = DIGIT_BLANK;
            endcase
        end
    endfunction

    task automatic write_digit_res;
        input [2:0] idx;
        input [3:0] value;
        begin
            case (idx)
                3'd0: digit_res0 <= value;
                3'd1: digit_res1 <= value;
                3'd2: digit_res2 <= value;
                3'd3: digit_res3 <= value;
                3'd4: digit_res4 <= value;
                default: ;
            endcase
        end
    endtask

    function automatic [9:0] popcount28;
        input [27:0] value;
        integer i;
        begin
            popcount28 = 10'd0;
            for (i = 0; i < 28; i = i + 1) begin
                popcount28 = popcount28 + value[i];
            end
        end
    endfunction

    task automatic handle_digit_pixel;
        input [2:0] digit_idx;
        input [9:0] seg_left;
        input [9:0] seg_width;
        reg [9:0] x_rel;
        reg [9:0] y_rel;
        reg [5:0] x_scaled;
        reg [5:0] y_scaled;
        begin
            if (pixel_foreground) begin
                x_rel    = x_cnt - seg_left;
                y_rel    = y_cnt - bbox_min_y_frame;
                x_scaled = scale_to_28(x_rel, seg_width);
                y_scaled = scale_to_28(y_rel, bbox_height_frame);
                if (x_scaled < 6'd28 && y_scaled < 6'd28) begin
                    segment_active[digit_idx] <= 1'b1;
                    case (digit_idx)
                        3'd0: digit_bitmap0[y_scaled][x_scaled] <= 1'b1;
                        3'd1: digit_bitmap1[y_scaled][x_scaled] <= 1'b1;
                        3'd2: digit_bitmap2[y_scaled][x_scaled] <= 1'b1;
                        3'd3: digit_bitmap3[y_scaled][x_scaled] <= 1'b1;
                        3'd4: digit_bitmap4[y_scaled][x_scaled] <= 1'b1;
                        default: ;
                    endcase
                end
            end
        end
    endtask

    task automatic process_template_row;
        reg [27:0] digit_row;
        reg [27:0] diff_bits;
        reg [9:0]  diff_count;
        reg [9:0]  total_distance;
        begin
            digit_row   = get_digit_row(proc_digit, proc_row);
            diff_bits   = digit_row ^ rom_data_q;
            diff_count  = popcount28(diff_bits);
            total_distance = current_distance + diff_count;

            if (proc_row == 5'd27) begin
                if (total_distance < best_distance) begin
                    best_distance <= total_distance;
                    best_template <= proc_template;
                end
                current_distance <= 10'd0;
                row_idx          <= 5'd0;
                if (proc_template == 4'd9) begin
                    if (segment_active[proc_digit])
                        write_digit_res(proc_digit, best_template);
                    else
                        write_digit_res(proc_digit, DIGIT_BLANK);

                    best_distance <= 10'h3FF;
                    best_template <= 4'd0;
                    template_idx  <= 4'd0;
                    if (proc_digit == 3'd4) begin
                        current_digit <= 3'd5;
                    end else begin
                        current_digit <= proc_digit + 3'd1;
                    end
                end else begin
                    template_idx    <= proc_template + 4'd1;
                end
            end else begin
                current_distance <= total_distance;
                row_idx          <= proc_row + 5'd1;
            end
            recog_substate <= SUB_REQ;
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= ST_CLEAR;
            recog_substate  <= SUB_IDLE;
            clear_row       <= 6'd0;
            has_bbox_frame  <= 1'b0;
            bbox_min_x_frame<= 10'd0;
            bbox_max_x_frame<= 10'd0;
            bbox_min_y_frame<= 9'd0;
            bbox_max_y_frame<= 9'd0;
            divider_frame0  <= 10'd0;
            divider_frame1  <= 10'd0;
            divider_frame2  <= 10'd0;
            divider_frame3  <= 10'd0;
            divider_frame4  <= 10'd0;
            divider_frame5  <= 10'd0;
            bbox_height_frame <= 10'd1;
            x_cnt           <= 10'd0;
            y_cnt           <= 9'd0;
            segment_active  <= 5'd0;
            digit_res0      <= DIGIT_BLANK;
            digit_res1      <= DIGIT_BLANK;
            digit_res2      <= DIGIT_BLANK;
            digit_res3      <= DIGIT_BLANK;
            digit_res4      <= DIGIT_BLANK;
            digit0          <= DIGIT_BLANK;
            digit1          <= DIGIT_BLANK;
            digit2          <= DIGIT_BLANK;
            digit3          <= DIGIT_BLANK;
            digit4          <= DIGIT_BLANK;
            digits_valid    <= 1'b0;
            current_digit   <= 3'd0;
            template_idx    <= 4'd0;
            row_idx         <= 5'd0;
            current_distance<= 10'd0;
            best_distance   <= 10'h3FF;
            best_template   <= 4'd0;
            proc_digit      <= 3'd0;
            proc_template   <= 4'd0;
            proc_row        <= 5'd0;
            rom_addr        <= 9'd0;
            proc_valid      <= 1'b0;
        end else begin
            digits_valid <= 1'b0;
            rom_data_q   <= rom_data;
            case (state)
                ST_CLEAR: begin
                    digit_bitmap0[clear_row] <= 28'd0;
                    digit_bitmap1[clear_row] <= 28'd0;
                    digit_bitmap2[clear_row] <= 28'd0;
                    digit_bitmap3[clear_row] <= 28'd0;
                    digit_bitmap4[clear_row] <= 28'd0;
                    if (clear_row == 6'd27) begin
                        clear_row <= 6'd0;
                        state     <= ST_WAIT;
                    end else begin
                        clear_row <= clear_row + 6'd1;
                    end
                end
                ST_WAIT: begin
                    if (frame_start) begin
                        has_bbox_frame   <= has_bbox;
                        bbox_min_x_frame <= bbox_min_x;
                        bbox_max_x_frame <= bbox_max_x;
                        bbox_min_y_frame <= bbox_min_y;
                        bbox_max_y_frame <= bbox_max_y;
                        divider_frame0   <= divider_x0;
                        divider_frame1   <= divider_x1;
                        divider_frame2   <= divider_x2;
                        divider_frame3   <= divider_x3;
                        divider_frame4   <= divider_x4;
                        divider_frame5   <= divider_x5;
                        bbox_height_frame<= (bbox_max_y >= bbox_min_y) ? ({1'b0,bbox_max_y} - {1'b0,bbox_min_y} + 10'd1) : 10'd1;
                        segment_active   <= 5'd0;
                        x_cnt            <= 10'd0;
                        y_cnt            <= 9'd0;
                        state            <= ST_CAPTURE;
                    end
                end
                ST_CAPTURE: begin
                    if (frame_end) begin
                        state           <= ST_RECOG;
                        recog_substate  <= SUB_REQ;
                        current_digit   <= 3'd0;
                        template_idx    <= 4'd0;
                        row_idx         <= 5'd0;
                        current_distance<= 10'd0;
                        best_distance   <= 10'h3FF;
                        best_template   <= 4'd0;
                    end else if (pixel_valid) begin
                        if (has_bbox_frame && within_bbox_y) begin
                            if ((x_cnt >= seg_left0) && (x_cnt < seg_right0)) begin
                                handle_digit_pixel(3'd0, seg_left0, seg_width0);
                            end else if ((x_cnt >= seg_left1) && (x_cnt < seg_right1)) begin
                                handle_digit_pixel(3'd1, seg_left1, seg_width1);
                            end else if ((x_cnt >= seg_left2) && (x_cnt < seg_right2)) begin
                                handle_digit_pixel(3'd2, seg_left2, seg_width2);
                            end else if ((x_cnt >= seg_left3) && (x_cnt < seg_right3)) begin
                                handle_digit_pixel(3'd3, seg_left3, seg_width3);
                            end else if ((x_cnt >= seg_left4) && (x_cnt < seg_right4)) begin
                                handle_digit_pixel(3'd4, seg_left4, seg_width4);
                            end
                        end

                        if (x_cnt == H_MAX_VAL) begin
                            x_cnt <= 10'd0;
                            if (y_cnt == V_MAX_VAL)
                                y_cnt <= 9'd0;
                            else
                                y_cnt <= y_cnt + 9'd1;
                        end else begin
                            x_cnt <= x_cnt + 10'd1;
                        end
                    end
                end
                ST_RECOG: begin
                    case (recog_substate)
                        SUB_REQ: begin
                            if (current_digit > 3'd4) begin
                                digit0       <= digit_res0;
                                digit1       <= digit_res1;
                                digit2       <= digit_res2;
                                digit3       <= digit_res3;
                                digit4       <= digit_res4;
                                digits_valid <= 1'b1;
                                state        <= ST_CLEAR;
                                clear_row    <= 6'd0;
                                recog_substate <= SUB_IDLE;
                            end else if (!segment_active[current_digit]) begin
                                write_digit_res(current_digit, DIGIT_BLANK);
                                current_digit   <= current_digit + 3'd1;
                                template_idx    <= 4'd0;
                                row_idx         <= 5'd0;
                                current_distance<= 10'd0;
                                best_distance   <= 10'h3FF;
                                best_template   <= 4'd0;
                            end else begin
                                rom_addr      <= template_idx * 9'd28 + row_idx;
                                proc_digit    <= current_digit;
                                proc_template <= template_idx;
                                proc_row      <= row_idx;
                                proc_valid    <= 1'b1;
                                recog_substate<= SUB_PROC;
                            end
                        end
                        SUB_PROC: begin
                            if (proc_valid) begin
                                proc_valid <= 1'b0;
                                process_template_row();
                            end else begin
                                recog_substate <= SUB_REQ;
                            end
                        end
                        default: begin
                            recog_substate <= SUB_REQ;
                        end
                    endcase
                end
                default: state <= ST_CLEAR;
            endcase
        end
    end
endmodule
