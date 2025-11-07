`timescale 1ns / 1ps

module klein_blue_replace #(
    parameter [7:0] TARGET_R          = 8'h00,
    parameter [7:0] TARGET_G          = 8'h2F,
    parameter [7:0] TARGET_B          = 8'hA7,
    parameter [7:0] BLUE_MIN          = 8'd96,
    parameter [7:0] RED_MAX           = 8'd120,
    parameter [7:0] GREEN_MAX         = 8'd140,
    parameter [7:0] DOMINANCE_MARGIN  = 8'd40
)(
    input  wire [7:0] in_r,
    input  wire [7:0] in_g,
    input  wire [7:0] in_b,
    output wire [7:0] out_r,
    output wire [7:0] out_g,
    output wire [7:0] out_b,
    output wire       is_target_blue
);
    wire [7:0] max_rg;
    wire [8:0] margin_ext;
    wire [8:0] max_rg_ext;
    wire [8:0] in_b_ext;
    wire [8:0] dominant_threshold;
    wire        replace_blue;

    assign max_rg            = (in_r > in_g) ? in_r : in_g;
    assign margin_ext        = {1'b0, DOMINANCE_MARGIN};
    assign max_rg_ext        = {1'b0, max_rg};
    assign in_b_ext          = {1'b0, in_b};
    assign dominant_threshold = max_rg_ext + margin_ext;

    assign replace_blue = (in_b_ext >= dominant_threshold) &&
                          (in_b >= BLUE_MIN) &&
                          (in_r <= RED_MAX) &&
                          (in_g <= GREEN_MAX);

    assign out_r = replace_blue ? TARGET_R : in_r;
    assign out_g = replace_blue ? TARGET_G : in_g;
    assign out_b = replace_blue ? TARGET_B : in_b;
    assign is_target_blue = replace_blue;

endmodule
