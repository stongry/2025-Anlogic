// ============================================================================
// Blue Pixel Highlight With Bounding Box
// - Detects blue-dominant pixels
// - Highlights them in pure blue
// - Tracks the bounding box encompassing blue pixels in the previous frame
//   and overlays a rectangular frame on the next frame output
// ============================================================================

module video_delay
#(
    parameter INPUT_WIDTH  = 32,          // Incoming pixel width (RGB888 + padding)
    parameter OUTPUT_WIDTH = 24,          // Outgoing pixel width (RGB888)
    parameter H_SIZE       = 1024,        // Active horizontal resolution
    parameter V_SIZE       = 768          // Active vertical resolution
)
(
    input                       video_clk,
    input                       rst,
    output                      read_en,
    input  [INPUT_WIDTH-1:0]    read_data,
    input                       hs,
    input                       vs,
    input                       de,
    input                       key_weak_inc,
    input                       key_weak_dec,
    input                       switch_threshold_select,
    input                       switch_step_size,

    output                      hs_r,
    output                      vs_r,
    output                      de_r,
    output [OUTPUT_WIDTH-1:0]   vout_data
);

// --------------------------------------------------------------------------
// Utility function: clog2
// --------------------------------------------------------------------------
function integer clog2;
    input integer value;
    integer i;
    begin
        clog2 = 0;
        for (i = value - 1; i > 0; i = i >> 1)
            clog2 = clog2 + 1;
    end
endfunction

localparam integer X_WIDTH = (H_SIZE > 1) ? clog2(H_SIZE) : 1;
localparam integer Y_WIDTH = (V_SIZE > 1) ? clog2(V_SIZE) : 1;

// --------------------------------------------------------------------------
// Configuration
// --------------------------------------------------------------------------
localparam [OUTPUT_WIDTH-1:0] BLUE_PIXEL             = {8'h00, 8'h00, 8'hFF};
localparam [OUTPUT_WIDTH-1:0] BOX_COLOR              = {8'hFF, 8'hFF, 8'h00};
localparam [7:0]              BLUE_LEVEL_DEFAULT     = 8'd85;
localparam [7:0]              DOMINANCE_MARGIN_DEFAULT = 8'd44;
localparam [X_WIDTH-1:0]      X_MAX_VALUE            = (H_SIZE > 0) ? (H_SIZE - 1) : 0;
localparam [Y_WIDTH-1:0]      Y_MAX_VALUE            = (V_SIZE > 0) ? (V_SIZE - 1) : 0;

// --------------------------------------------------------------------------
// Key handling (rising-edge detect)
// --------------------------------------------------------------------------
reg [1:0] key_sync;
reg [1:0] key_sync_d;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        key_sync   <= 2'b0;
        key_sync_d <= 2'b0;
    end else begin
        key_sync   <= {key_weak_inc, key_weak_dec};
        key_sync_d <= key_sync;
    end
end

wire [1:0] key_press = key_sync & ~key_sync_d;
wire [7:0] requested_step = switch_step_size ? 8'd10 : 8'd25;

// --------------------------------------------------------------------------
// Threshold registers (adjustable through the existing key/switch inputs)
// --------------------------------------------------------------------------
reg [7:0] blue_level_threshold;
reg [7:0] dominance_margin;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        blue_level_threshold <= BLUE_LEVEL_DEFAULT;
        dominance_margin     <= DOMINANCE_MARGIN_DEFAULT;
    end else begin
        if (switch_threshold_select == 1'b0) begin
            // Adjust blue detection lower bound
            if (key_press[1]) begin
                if (blue_level_threshold >= 8'd255 - requested_step)
                    blue_level_threshold <= 8'd255;
                else
                    blue_level_threshold <= blue_level_threshold + requested_step;
            end else if (key_press[0]) begin
                if (blue_level_threshold <= requested_step)
                    blue_level_threshold <= 8'd0;
                else
                    blue_level_threshold <= blue_level_threshold - requested_step;
            end
        end else begin
            // Adjust dominance margin required over R/G channels
            if (key_press[1]) begin
                if (dominance_margin >= 8'd255 - requested_step)
                    dominance_margin <= 8'd255;
                else
                    dominance_margin <= dominance_margin + requested_step;
            end else if (key_press[0]) begin
                if (dominance_margin <= requested_step)
                    dominance_margin <= 8'd0;
                else
                    dominance_margin <= dominance_margin - requested_step;
            end
        end
    end
end

// --------------------------------------------------------------------------
// Current pixel components
// --------------------------------------------------------------------------
wire [7:0] r_in = read_data[31:24];
wire [7:0] g_in = read_data[23:16];
wire [7:0] b_in = read_data[15:8];
wire [OUTPUT_WIDTH-1:0] rgb_in = read_data[31:8]; // RGB888 portion

// Extend to 9 bits for margin comparisons
wire [8:0] r_margin = {1'b0, r_in} + {1'b0, dominance_margin};
wire [8:0] g_margin = {1'b0, g_in} + {1'b0, dominance_margin};

wire blue_is_high         = (b_in >= blue_level_threshold);
wire blue_dominant_over_r = ({1'b0, b_in} >= r_margin);
wire blue_dominant_over_g = ({1'b0, b_in} >= g_margin);
wire blue_pixel_detect    = blue_is_high && blue_dominant_over_r && blue_dominant_over_g;

// --------------------------------------------------------------------------
// Coordinate counters
// --------------------------------------------------------------------------
reg [X_WIDTH-1:0] x_cnt;
reg [Y_WIDTH-1:0] y_cnt;
reg de_prev;
reg vs_prev;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        x_cnt   <= {X_WIDTH{1'b0}};
        y_cnt   <= {Y_WIDTH{1'b0}};
        de_prev <= 1'b0;
        vs_prev <= 1'b0;
    end else begin
        de_prev <= de;
        vs_prev <= vs;

        if (vs_prev && !vs) begin
            // Start of a new frame
            x_cnt <= {X_WIDTH{1'b0}};
            y_cnt <= {Y_WIDTH{1'b0}};
        end else if (de_prev && !de) begin
            // End of active line
            x_cnt <= {X_WIDTH{1'b0}};
            if (y_cnt != Y_MAX_VALUE)
                y_cnt <= y_cnt + 1'b1;
        end else if (de) begin
            if (!de_prev)
                x_cnt <= {X_WIDTH{1'b0}};
            else if (x_cnt != X_MAX_VALUE)
                x_cnt <= x_cnt + 1'b1;
        end
    end
end

// --------------------------------------------------------------------------
// Frame bounding box accumulation
// --------------------------------------------------------------------------
reg [X_WIDTH-1:0] frame_min_x;
reg [X_WIDTH-1:0] frame_max_x;
reg [Y_WIDTH-1:0] frame_min_y;
reg [Y_WIDTH-1:0] frame_max_y;
reg frame_has_blue;

reg [X_WIDTH-1:0] bbox_min_x;
reg [X_WIDTH-1:0] bbox_max_x;
reg [Y_WIDTH-1:0] bbox_min_y;
reg [Y_WIDTH-1:0] bbox_max_y;
reg bbox_valid;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        frame_min_x   <= {X_WIDTH{1'b1}};
        frame_max_x   <= {X_WIDTH{1'b0}};
        frame_min_y   <= {Y_WIDTH{1'b1}};
        frame_max_y   <= {Y_WIDTH{1'b0}};
        frame_has_blue<= 1'b0;
        bbox_min_x    <= {X_WIDTH{1'b0}};
        bbox_max_x    <= {X_WIDTH{1'b0}};
        bbox_min_y    <= {Y_WIDTH{1'b0}};
        bbox_max_y    <= {Y_WIDTH{1'b0}};
        bbox_valid    <= 1'b0;
    end else begin
        if (de && blue_pixel_detect) begin
            if (!frame_has_blue) begin
                frame_min_x    <= x_cnt;
                frame_max_x    <= x_cnt;
                frame_min_y    <= y_cnt;
                frame_max_y    <= y_cnt;
                frame_has_blue <= 1'b1;
            end else begin
                if (x_cnt < frame_min_x) frame_min_x <= x_cnt;
                if (x_cnt > frame_max_x) frame_max_x <= x_cnt;
                if (y_cnt < frame_min_y) frame_min_y <= y_cnt;
                if (y_cnt > frame_max_y) frame_max_y <= y_cnt;
            end
        end

        if (vs_prev && !vs) begin
            // Frame boundary reached, latch bounding box for next frame
            if (frame_has_blue) begin
                bbox_min_x <= frame_min_x;
                bbox_max_x <= frame_max_x;
                bbox_min_y <= frame_min_y;
                bbox_max_y <= frame_max_y;
                bbox_valid <= 1'b1;
            end else begin
                bbox_valid <= 1'b0;
            end

            frame_min_x    <= {X_WIDTH{1'b1}};
            frame_max_x    <= {X_WIDTH{1'b0}};
            frame_min_y    <= {Y_WIDTH{1'b1}};
            frame_max_y    <= {Y_WIDTH{1'b0}};
            frame_has_blue <= 1'b0;
        end
    end
end

// --------------------------------------------------------------------------
// Delay pipelines for sync/Data Enable/blue detection flags & RGB data
// --------------------------------------------------------------------------
reg [20:0] hs_d;
reg [20:0] vs_d;
reg [20:0] de_d;
reg [20:0] blue_d;
reg [OUTPUT_WIDTH-1:0] rgb_pipe [0:20];
reg [X_WIDTH-1:0]      x_pipe   [0:20];
reg [Y_WIDTH-1:0]      y_pipe   [0:20];
integer pipe_idx;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        hs_d   <= 21'd0;
        vs_d   <= 21'd0;
        de_d   <= 21'd0;
        blue_d <= 21'd0;
        for (pipe_idx = 0; pipe_idx < 21; pipe_idx = pipe_idx + 1) begin
            rgb_pipe[pipe_idx] <= {OUTPUT_WIDTH{1'b0}};
            x_pipe[pipe_idx]   <= {X_WIDTH{1'b0}};
            y_pipe[pipe_idx]   <= {Y_WIDTH{1'b0}};
        end
    end else begin
        hs_d   <= {hs_d[19:0], hs};
        vs_d   <= {vs_d[19:0], vs};
        de_d   <= {de_d[19:0], de};
        blue_d <= {blue_d[19:0], (de ? blue_pixel_detect : 1'b0)};

        rgb_pipe[0] <= de ? rgb_in : {OUTPUT_WIDTH{1'b0}};
        x_pipe[0]   <= x_cnt;
        y_pipe[0]   <= y_cnt;
        for (pipe_idx = 1; pipe_idx < 21; pipe_idx = pipe_idx + 1) begin
            rgb_pipe[pipe_idx] <= rgb_pipe[pipe_idx - 1];
            x_pipe[pipe_idx]   <= x_pipe[pipe_idx - 1];
            y_pipe[pipe_idx]   <= y_pipe[pipe_idx - 1];
        end
    end
end

// --------------------------------------------------------------------------
// Output pixel generation
// --------------------------------------------------------------------------
reg [OUTPUT_WIDTH - 1:0] vout_data_r;

wire [X_WIDTH-1:0] x_out = x_pipe[20];
wire [Y_WIDTH-1:0] y_out = y_pipe[20];

wire within_bbox =
    bbox_valid &&
    (x_out >= bbox_min_x) && (x_out <= bbox_max_x) &&
    (y_out >= bbox_min_y) && (y_out <= bbox_max_y);

wire on_bbox_edge =
    within_bbox &&
    ( (x_out == bbox_min_x) || (x_out == bbox_max_x) ||
      (y_out == bbox_min_y) || (y_out == bbox_max_y) );

wire [OUTPUT_WIDTH-1:0] highlight_color =
    blue_d[19] ? BLUE_PIXEL : rgb_pipe[20];

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        vout_data_r <= {OUTPUT_WIDTH{1'b0}};
    end else if (de_d[19]) begin
        vout_data_r <= on_bbox_edge ? BOX_COLOR : highlight_color;
    end else begin
        vout_data_r <= {OUTPUT_WIDTH{1'b0}};
    end
end

// --------------------------------------------------------------------------
// Output assignments
// --------------------------------------------------------------------------
assign read_en   = de_d[18];
assign hs_r      = hs_d[20];
assign vs_r      = vs_d[20];
assign de_r      = de_d[20];
assign vout_data = vout_data_r;

endmodule
