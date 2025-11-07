`include "video_define.v"

module color_bar (
    input        clk,
    input        rst,
    output       hs,
    output       vs,
    output       de,
    output [7:0] rgb_r,
    output [7:0] rgb_g,
    output [7:0] rgb_b
);
//----------------------------------------------------------------------------
// Video timing configuration
//----------------------------------------------------------------------------
`ifdef  VIDEO_1280_720
localparam H_ACTIVE = 16'd1280;
localparam H_FP     = 16'd110;
localparam H_SYNC   = 16'd40;
localparam H_BP     = 16'd220;
localparam V_ACTIVE = 16'd720;
localparam V_FP     = 16'd5;
localparam V_SYNC   = 16'd5;
localparam V_BP     = 16'd20;
localparam HS_POL   = 1'b1;
localparam VS_POL   = 1'b1;
`elsif  VIDEO_480_272
localparam H_ACTIVE = 16'd480;
localparam H_FP     = 16'd2;
localparam H_SYNC   = 16'd41;
localparam H_BP     = 16'd2;
localparam V_ACTIVE = 16'd272;
localparam V_FP     = 16'd2;
localparam V_SYNC   = 16'd10;
localparam V_BP     = 16'd2;
localparam HS_POL   = 1'b0;
localparam VS_POL   = 1'b0;
`elsif  VIDEO_640_480
localparam H_ACTIVE = 16'd640;
localparam H_FP     = 16'd16;
localparam H_SYNC   = 16'd96;
localparam H_BP     = 16'd48;
localparam V_ACTIVE = 16'd480;
localparam V_FP     = 16'd10;
localparam V_SYNC   = 16'd2;
localparam V_BP     = 16'd33;
localparam HS_POL   = 1'b0;
localparam VS_POL   = 1'b0;
`elsif  VIDEO_800_480
localparam H_ACTIVE = 16'd800;
localparam H_FP     = 16'd40;
localparam H_SYNC   = 16'd128;
localparam H_BP     = 16'd88;
localparam V_ACTIVE = 16'd480;
localparam V_FP     = 16'd1;
localparam V_SYNC   = 16'd3;
localparam V_BP     = 16'd21;
localparam HS_POL   = 1'b0;
localparam VS_POL   = 1'b0;
`elsif  VIDEO_800_600
localparam H_ACTIVE = 16'd800;
localparam H_FP     = 16'd40;
localparam H_SYNC   = 16'd128;
localparam H_BP     = 16'd88;
localparam V_ACTIVE = 16'd600;
localparam V_FP     = 16'd1;
localparam V_SYNC   = 16'd4;
localparam V_BP     = 16'd23;
localparam HS_POL   = 1'b1;
localparam VS_POL   = 1'b1;
`elsif  VIDEO_1024_768
localparam H_ACTIVE = 16'd1024;
localparam H_FP     = 16'd24;
localparam H_SYNC   = 16'd136;
localparam H_BP     = 16'd160;
localparam V_ACTIVE = 16'd768;
localparam V_FP     = 16'd3;
localparam V_SYNC   = 16'd6;
localparam V_BP     = 16'd29;
localparam HS_POL   = 1'b0;
localparam VS_POL   = 1'b0;
`elsif  VIDEO_1920_1080
localparam H_ACTIVE = 16'd1920;
localparam H_FP     = 16'd88;
localparam H_SYNC   = 16'd44;
localparam H_BP     = 16'd148;
localparam V_ACTIVE = 16'd1080;
localparam V_FP     = 16'd4;
localparam V_SYNC   = 16'd5;
localparam V_BP     = 16'd36;
localparam HS_POL   = 1'b1;
localparam VS_POL   = 1'b1;
`else
`error "video_define.v must select a valid resolution macro."
`endif

localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

localparam WHITE_R   = 8'hff;
localparam WHITE_G   = 8'hff;
localparam WHITE_B   = 8'hff;
localparam YELLOW_R  = 8'hff;
localparam YELLOW_G  = 8'hff;
localparam YELLOW_B  = 8'h00;
localparam CYAN_R    = 8'h00;
localparam CYAN_G    = 8'hff;
localparam CYAN_B    = 8'hff;
localparam GREEN_R   = 8'h00;
localparam GREEN_G   = 8'hff;
localparam GREEN_B   = 8'h00;
localparam MAGENTA_R = 8'hff;
localparam MAGENTA_G = 8'h00;
localparam MAGENTA_B = 8'hff;
localparam RED_R     = 8'hff;
localparam RED_G     = 8'h00;
localparam RED_B     = 8'h00;
localparam BLUE_R    = 8'h00;
localparam BLUE_G    = 8'h00;
localparam BLUE_B    = 8'hff;
localparam BLACK_R   = 8'h00;
localparam BLACK_G   = 8'h00;
localparam BLACK_B   = 8'h00;

reg [11:0] h_cnt;
reg [11:0] v_cnt;
reg        hs_reg;
reg        vs_reg;
reg        h_active;
reg        v_active;
reg [7:0]  rgb_r_reg;
reg [7:0]  rgb_g_reg;
reg [7:0]  rgb_b_reg;

wire [11:0] active_x = h_cnt - (H_FP + H_SYNC + H_BP);
wire        video_active = h_active && v_active;

assign hs    = hs_reg;
assign vs    = vs_reg;
assign de    = video_active;
assign rgb_r = rgb_r_reg;
assign rgb_g = rgb_g_reg;
assign rgb_b = rgb_b_reg;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        h_cnt <= 12'd0;
        v_cnt <= 12'd0;
    end else begin
        if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 12'd0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 12'd0;
            else
                v_cnt <= v_cnt + 12'd1;
        end else begin
            h_cnt <= h_cnt + 12'd1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        hs_reg <= 1'b0;
    else if (h_cnt == H_FP - 1)
        hs_reg <= HS_POL;
    else if (h_cnt == H_FP + H_SYNC - 1)
        hs_reg <= ~hs_reg;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        h_active <= 1'b0;
    else if (h_cnt == H_FP + H_SYNC + H_BP - 1)
        h_active <= 1'b1;
    else if (h_cnt == H_TOTAL - 1)
        h_active <= 1'b0;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        vs_reg <= 1'b0;
    else if ((v_cnt == V_FP - 1) && (h_cnt == H_FP - 1))
        vs_reg <= HS_POL;
    else if ((v_cnt == V_FP + V_SYNC - 1) && (h_cnt == H_FP - 1))
        vs_reg <= ~vs_reg;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        v_active <= 1'b0;
    else if ((v_cnt == V_FP + V_SYNC + V_BP - 1) && (h_cnt == H_FP - 1))
        v_active <= 1'b1;
    else if ((v_cnt == V_TOTAL - 1) && (h_cnt == H_FP - 1))
        v_active <= 1'b0;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rgb_r_reg <= 8'd0;
        rgb_g_reg <= 8'd0;
        rgb_b_reg <= 8'd0;
    end else if (video_active) begin
        case (active_x / (H_ACTIVE / 8))
            0: begin rgb_r_reg <= WHITE_R;   rgb_g_reg <= WHITE_G;   rgb_b_reg <= WHITE_B;   end
            1: begin rgb_r_reg <= YELLOW_R;  rgb_g_reg <= YELLOW_G;  rgb_b_reg <= YELLOW_B;  end
            2: begin rgb_r_reg <= CYAN_R;    rgb_g_reg <= CYAN_G;    rgb_b_reg <= CYAN_B;    end
            3: begin rgb_r_reg <= GREEN_R;   rgb_g_reg <= GREEN_G;   rgb_b_reg <= GREEN_B;   end
            4: begin rgb_r_reg <= MAGENTA_R; rgb_g_reg <= MAGENTA_G; rgb_b_reg <= MAGENTA_B; end
            5: begin rgb_r_reg <= RED_R;     rgb_g_reg <= RED_G;     rgb_b_reg <= RED_B;     end
            6: begin rgb_r_reg <= BLUE_R;    rgb_g_reg <= BLUE_G;    rgb_b_reg <= BLUE_B;    end
            default: begin rgb_r_reg <= BLACK_R;  rgb_g_reg <= BLACK_G;  rgb_b_reg <= BLACK_B; end
        endcase
    end else begin
        rgb_r_reg <= 8'd0;
        rgb_g_reg <= 8'd0;
        rgb_b_reg <= 8'd0;
    end
end

endmodule
