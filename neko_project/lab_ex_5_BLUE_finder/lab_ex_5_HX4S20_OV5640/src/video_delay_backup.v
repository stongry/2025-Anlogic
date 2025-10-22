// ============================================================================
// Blue Pixel Detection And Highlight Module
// Detects pixels with a dominant blue component and outputs a solid blue pixel
// on HDMI while keeping the original video timing pipeline.
// ============================================================================

module video_delay
#(
    parameter DATA_WIDTH = 24,   // RGB888 by default
    parameter H_SIZE     = 1024  // Kept for compatibility with existing instantiations
)
(
    input                       video_clk,          // Pixel clock
    input                       rst,                // Active-high reset
    output                      read_en,            // Read enable for upstream buffer
    input  [DATA_WIDTH - 1:0]   read_data,          // Incoming RGB data (R[23:16], G[15:8], B[7:0])
    input                       hs,                 // Horizontal sync
    input                       vs,                 // Vertical sync
    input                       de,                 // Data enable
    input                       key_weak_inc,       // Key 1: increase selected threshold
    input                       key_weak_dec,       // Key 2: decrease selected threshold
    input                       switch_threshold_select, // 0: adjust blue level, 1: adjust non-blue limit
    input                       switch_step_size,   // 0: large step, 1: small step

    output                      hs_r,               // Delayed horizontal sync
    output                      vs_r,               // Delayed vertical sync
    output                      de_r,               // Delayed data enable
    output [DATA_WIDTH - 1:0]   vout_data           // Output pixel stream
);

// --------------------------------------------------------------------------
// Configuration
// --------------------------------------------------------------------------
localparam [DATA_WIDTH-1:0] BLUE_PIXEL               = {8'h00, 8'h00, 8'hFF};
localparam [7:0]            BLUE_LEVEL_DEFAULT       = 8'd120;
localparam [7:0]            DOMINANCE_MARGIN_DEFAULT = 8'd40;

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
        dominance_margin    <= DOMINANCE_MARGIN_DEFAULT;
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
wire [7:0] r_in = read_data[23:16];
wire [7:0] g_in = read_data[15:8];
wire [7:0] b_in = read_data[7:0];

// Extend to 9 bits for margin comparisons
wire [8:0] b_ext        = {1'b0, b_in};
wire [8:0] r_margin     = {1'b0, r_in} + {1'b0, dominance_margin};
wire [8:0] g_margin     = {1'b0, g_in} + {1'b0, dominance_margin};

wire blue_is_high       = (b_in >= blue_level_threshold);
wire blue_dominant_over_r = (b_ext >= r_margin);
wire blue_dominant_over_g = (b_ext >= g_margin);
wire blue_pixel_detect  = blue_is_high && blue_dominant_over_r && blue_dominant_over_g;

// --------------------------------------------------------------------------
// Delay pipelines for sync/Data Enable/blue detection flags
// --------------------------------------------------------------------------
reg [20:0] hs_d;
reg [20:0] vs_d;
reg [20:0] de_d;
reg [20:0] blue_d;
reg [DATA_WIDTH-1:0] data_pipe [0:20];
integer idx;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        hs_d   <= 21'd0;
        vs_d   <= 21'd0;
        de_d   <= 21'd0;
        blue_d <= 21'd0;
        for (idx = 0; idx <= 20; idx = idx + 1) begin
            data_pipe[idx] <= {DATA_WIDTH{1'b0}};
        end
    end else begin
        hs_d   <= {hs_d[19:0], hs};
        vs_d   <= {vs_d[19:0], vs};
        de_d   <= {de_d[19:0], de};
        blue_d <= {blue_d[19:0], (de ? blue_pixel_detect : 1'b0)};
        data_pipe[0] <= read_data;
        for (idx = 1; idx <= 20; idx = idx + 1) begin
            data_pipe[idx] <= data_pipe[idx-1];
        end
    end
end

// --------------------------------------------------------------------------
// Output pixel generation
// --------------------------------------------------------------------------
reg [DATA_WIDTH - 1:0] vout_data_r;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        vout_data_r <= {DATA_WIDTH{1'b0}};
    end else if (de_d[19]) begin
        vout_data_r <= blue_d[19] ? BLUE_PIXEL : data_pipe[20];
    end else begin
        vout_data_r <= {DATA_WIDTH{1'b0}};
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

