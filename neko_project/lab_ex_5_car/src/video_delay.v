module video_delay
#(
    parameter DATA_WIDTH = 24,
    parameter integer FRAME_WIDTH = 1024,
    parameter [7:0] SAT_THRESHOLD = 8'd40,
    parameter [23:0] HIGHLIGHT_COLOR = 24'hFF3030,
    parameter integer COUNTER_WIDTH = 20,
    parameter integer MARGIN_SHIFT  = 3,
    parameter integer MIN_MARGIN    = 4000
)
(
    input                       video_clk,
    input                       rst,
    output                      read_en,
    input  [DATA_WIDTH - 1:0]   read_data,
    input                       key_inc,
    input                       key_dec,
    input                       switch_param,
    input                       switch_step,
    input                       hs,
    input                       vs,
    input                       de,
    output                      hs_r,
    output                      vs_r,
    output                      de_r,
    output [DATA_WIDTH - 1:0]   vout_data,
    output [3:0]                highlight_digit
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1) begin
                clog2 = clog2 + 1;
            end
        end
    endfunction

    localparam integer X_ADDR_WIDTH = (FRAME_WIDTH <= 1) ? 1 : clog2(FRAME_WIDTH);
    localparam integer HALF_WIDTH   = FRAME_WIDTH >> 1;

    function [3:0] balance_digit;
        input [COUNTER_WIDTH-1:0] left;
        input [COUNTER_WIDTH-1:0] right;
        input [COUNTER_WIDTH-1:0] min_margin_dyn;
        reg [COUNTER_WIDTH:0] left_ext;
        reg [COUNTER_WIDTH:0] right_ext;
        reg [COUNTER_WIDTH:0] total_ext;
        reg [COUNTER_WIDTH:0] margin_ext;
        begin
            left_ext  = {1'b0, left};
            right_ext = {1'b0, right};
            total_ext = left_ext + right_ext;
            margin_ext = total_ext >> MARGIN_SHIFT;
            if (margin_ext < {1'b0, min_margin_dyn})
                margin_ext = {1'b0, min_margin_dyn};
            if (left_ext > right_ext + margin_ext)
                balance_digit = 4'd1;
            else if (right_ext > left_ext + margin_ext)
                balance_digit = 4'd3;
            else
                balance_digit = 4'd2;
        end
    endfunction

    reg [7:0]                  sat_threshold_reg;
    reg [COUNTER_WIDTH-1:0]    min_margin_reg;

    reg                        key_inc_sync0;
    reg                        key_inc_sync1;
    reg                        key_dec_sync0;
    reg                        key_dec_sync1;
    reg                        switch_param_sync;
    reg                        switch_step_sync;

    wire                       inc_pulse;
    wire                       dec_pulse;

    wire [7:0]                 sat_step;
    wire [COUNTER_WIDTH-1:0]   margin_step_small;
    wire [COUNTER_WIDTH-1:0]   margin_step_large;
    wire [COUNTER_WIDTH-1:0]   margin_step;

    wire [7:0] red_in   = read_data[23:16];
    wire [7:0] green_in = read_data[15:8];
    wire [7:0] blue_in  = read_data[7:0];

    wire [7:0] max_rg   = (red_in   > green_in) ? red_in   : green_in;
    wire [7:0] max_rgb  = (max_rg   > blue_in)  ? max_rg   : blue_in;
    wire [7:0] min_rg   = (red_in   < green_in) ? red_in   : green_in;
    wire [7:0] min_rgb  = (min_rg   < blue_in)  ? min_rg   : blue_in;
    wire [8:0] sat_diff = {1'b0, max_rgb} - {1'b0, min_rgb};
    wire [7:0] saturation = sat_diff[7:0];

    wire highlight = de && (saturation >= sat_threshold_reg);
    wire [23:0] highlight_rgb = highlight ? HIGHLIGHT_COLOR : 24'd0;

    assign read_en = de;

    reg [X_ADDR_WIDTH-1:0] x_pos;
    reg                    de_prev;
    reg                    vs_prev;
    reg [COUNTER_WIDTH-1:0] left_count;
    reg [COUNTER_WIDTH-1:0] right_count;
    reg [3:0]               highlight_digit_r;

    reg [23:0] color_stage0;
    reg [23:0] color_stage1;
    reg [23:0] color_stage2;
    reg [1:0] hs_pipe;
    reg [1:0] vs_pipe;
    reg [1:0] de_pipe;

    wire frame_start = (~vs_prev) && vs;

    assign inc_pulse = key_inc_sync1 && ~key_inc_sync0;
    assign dec_pulse = key_dec_sync1 && ~key_dec_sync0;

    assign sat_step          = switch_step_sync ? 8'd8  : 8'd1;
    assign margin_step_small = {{(COUNTER_WIDTH-5){1'b0}}, 5'd16};
    assign margin_step_large = {{(COUNTER_WIDTH-7){1'b0}}, 7'd64};
    assign margin_step       = switch_step_sync ? margin_step_large : margin_step_small;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            key_inc_sync0     <= 1'b1;
            key_inc_sync1     <= 1'b1;
            key_dec_sync0     <= 1'b1;
            key_dec_sync1     <= 1'b1;
            switch_param_sync <= 1'b0;
            switch_step_sync  <= 1'b0;
        end else begin
            key_inc_sync0     <= key_inc;
            key_inc_sync1     <= key_inc_sync0;
            key_dec_sync0     <= key_dec;
            key_dec_sync1     <= key_dec_sync0;
            switch_param_sync <= switch_param;
            switch_step_sync  <= switch_step;
        end
    end

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            sat_threshold_reg <= SAT_THRESHOLD;
            min_margin_reg    <= MIN_MARGIN[COUNTER_WIDTH-1:0];
        end else begin
            if (inc_pulse) begin
                if (!switch_param_sync) begin
                    if (sat_threshold_reg >= 8'd255 - sat_step)
                        sat_threshold_reg <= 8'd255;
                    else
                        sat_threshold_reg <= sat_threshold_reg + sat_step;
                end else begin
                    if (min_margin_reg >= {COUNTER_WIDTH{1'b1}} - margin_step)
                        min_margin_reg <= {COUNTER_WIDTH{1'b1}};
                    else
                        min_margin_reg <= min_margin_reg + margin_step;
                end
            end
            if (dec_pulse) begin
                if (!switch_param_sync) begin
                    if (sat_threshold_reg <= sat_step)
                        sat_threshold_reg <= 8'd0;
                    else
                        sat_threshold_reg <= sat_threshold_reg - sat_step;
                end else begin
                    if (min_margin_reg <= margin_step)
                        min_margin_reg <= {COUNTER_WIDTH{1'b0}};
                    else
                        min_margin_reg <= min_margin_reg - margin_step;
                end
            end
        end
    end

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            x_pos             <= {X_ADDR_WIDTH{1'b0}};
            de_prev           <= 1'b0;
            vs_prev           <= 1'b0;
            left_count        <= {COUNTER_WIDTH{1'b0}};
            right_count       <= {COUNTER_WIDTH{1'b0}};
            highlight_digit_r <= 4'd2;
        end else begin
            de_prev <= de;
            vs_prev <= vs;

            if (frame_start) begin
                highlight_digit_r <= balance_digit(left_count, right_count, min_margin_reg);
                left_count        <= {COUNTER_WIDTH{1'b0}};
                right_count       <= {COUNTER_WIDTH{1'b0}};
                x_pos             <= {X_ADDR_WIDTH{1'b0}};
            end else begin
                if (de) begin
                    if (highlight) begin
                        if (x_pos < HALF_WIDTH) begin
                            if (left_count != {COUNTER_WIDTH{1'b1}})
                                left_count <= left_count + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                        end else begin
                            if (right_count != {COUNTER_WIDTH{1'b1}})
                                right_count <= right_count + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end

                    if (x_pos == FRAME_WIDTH - 1)
                        x_pos <= {X_ADDR_WIDTH{1'b0}};
                    else
                        x_pos <= x_pos + {{(X_ADDR_WIDTH-1){1'b0}}, 1'b1};
                end else if (de_prev && ~de) begin
                    x_pos <= {X_ADDR_WIDTH{1'b0}};
                end
            end
        end
    end

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            color_stage0 <= 24'd0;
            color_stage1 <= 24'd0;
            color_stage2 <= 24'd0;
            hs_pipe      <= 2'b0;
            vs_pipe      <= 2'b0;
            de_pipe      <= 2'b0;
        end else begin
            color_stage0 <= highlight_rgb;
            color_stage1 <= color_stage0;
            color_stage2 <= color_stage1;

            hs_pipe <= {hs_pipe[0], hs};
            vs_pipe <= {vs_pipe[0], vs};
            de_pipe <= {de_pipe[0], de};
        end
    end

    assign hs_r      = hs_pipe[1];
    assign vs_r      = vs_pipe[1];
    assign de_r      = de_pipe[1];
    assign vout_data = color_stage2;
    assign highlight_digit = highlight_digit_r;

endmodule

