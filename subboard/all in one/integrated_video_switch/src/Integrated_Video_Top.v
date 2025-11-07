`timescale 1ns / 1ps
//***********************************************************************
// Integrated Video Processing System with Mode Switching
// Description: 整合多种视频处理算法，通过3个开关(sw1,sw2,sw3)切换
//
// Mode Selection (SW3 SW2 SW1):
//   000 - 原始视频输出（无处理）
//   001 - UDP接收模式（预留）
//   010 - 蓝色检测与边界框叠加 (Klein Blue Detection)
//   011 - 图像饱和度分析 (Saturation Analyzer)
//   100 - Otsu二值化+腐蚀 (Otsu Binarization + Erosion)
//   101 - Sobel边缘检测 (Sobel Edge Detection)
//   110 - 待定模式1 (Reserved)
//   111 - 待定模式2 (Reserved)
//***********************************************************************

`define UDP_LOOP_BACK

module Integrated_Video_Top(
    // System inputs
    input  clk_50,
    input  sys_rst_n,

    // Mode selection switches
    input  sw1,           // LSB
    input  sw2,
    input  sw3,           // MSB

    // SD Card interface
    input  sd_reset_rd,
    input  sd_miso ,
    output sd_clk  ,
    output sd_cs   ,
    output sd_mosi ,

    // OV5640 Camera interface
    input               cam_pclk,
    input               cam_vsync,
    input               cam_href,
    input       [7:0]   cam_data,
    output              cam_rst_n,
    output              cam_pwdn,
    output              cam_scl,
    inout               cam_sda,

    // Ethernet PHY interface (RGMII)
    input               phy1_rgmii_rx_clk,
    input               phy1_rgmii_rx_ctl,
    input [3:0]         phy1_rgmii_rx_data,
    output wire         phy1_rgmii_tx_clk,
    output wire         phy1_rgmii_tx_ctl,
    output wire [3:0]   phy1_rgmii_tx_data,

    // LED outputs
    output [2:0]        led
);

// =========================================
// Parameters
// =========================================
parameter  DEVICE             = "EG4";
parameter  LOCAL_UDP_PORT_NUM = 16'h0001;
parameter  LOCAL_IP_ADDRESS   = 32'hc0a8f001;
parameter  LOCAL_MAC_ADDRESS  = 48'h0123456789ab;
parameter  DST_UDP_PORT_NUM   = 16'h0002;
parameter  DST_IP_ADDRESS     = 32'hc0a8f002;

// Video resolution parameters
localparam [12:0] H_CMOS_DISP    = 13'd640;
localparam [12:0] V_CMOS_DISP    = 13'd480;
localparam [12:0] TOTAL_H_PIXEL  = H_CMOS_DISP + 13'd1216; // 640+1216=1856
localparam [12:0] TOTAL_V_PIXEL  = V_CMOS_DISP + 13'd891;  // 19fps配置

localparam integer UDP_PKT_WORDS = 480;
localparam integer UDP_PKT_BYTES = UDP_PKT_WORDS * 3;

// =========================================
// Mode Selection Logic
// =========================================
wire [2:0] mode_select = {sw3, sw2, sw1};

// Mode definitions
localparam MODE_RAW        = 3'b000;  // 原始视频
localparam MODE_UDP_RX     = 3'b001;  // UDP接收（预留）
localparam MODE_BLUE_BBOX  = 3'b010;  // 蓝色检测
localparam MODE_SATURATION = 3'b011;  // 饱和度分析
localparam MODE_OTSU       = 3'b100;  // Otsu二值化+腐蚀
localparam MODE_SOBEL      = 3'b101;  // Sobel边缘检测
localparam MODE_RESERVED1  = 3'b110;  // 预留1
localparam MODE_RESERVED2  = 3'b111;  // 预留2

// LED显示当前模式（二进制编码）
assign led = mode_select;

// =========================================
// Reset and Clock Management
// =========================================
wire key1 = sys_rst_n;
reg sys_rst_n_1, sys_rst_n_2;
wire rst_n;
wire locked;
wire clk_50m, clk_50m_180deg, clk_sample;

// Synchronize reset
always @(posedge clk_50 or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        sys_rst_n_1 <= 1'b0;
        sys_rst_n_2 <= 1'b0;
    end else begin
        sys_rst_n_1 <= sys_rst_n;
        sys_rst_n_2 <= sys_rst_n_1;
    end
end

assign rst_n = sys_rst_n_2;

// 50MHz PLL
pll_50 u_pll_50(
    .refclk     (clk_50),
    .reset      (!sys_rst_n_2),
    .extlock    (locked),
    .clk0_out   (clk_50m),
    .clk1_out   (clk_50m_180deg),
    .clk2_out   (clk_sample)
);

// SD card pins (unused)
assign sd_clk  = 1'b0;
assign sd_cs   = 1'b1;
assign sd_mosi = 1'b0;

// =========================================
// OV5640 Camera Interface
// =========================================
wire        cmos_frame_vsync;
wire        cmos_frame_href;
wire        cmos_frame_valid;
wire [15:0] cmos_frame_data;
wire        cam_write_req;
wire        cam_write_req_ack;
wire        cam_write_en;
wire [31:0] cam_write_data;
wire        Sdr_init_done;

ov5640_dri u_ov5640_dri(
    .clk               (clk_50m),
    .rst_n             (rst_n),
    .cam_pclk          (cam_pclk),
    .cam_vsync         (cam_vsync),
    .cam_href          (cam_href),
    .cam_data          (cam_data),
    .cam_rst_n         (cam_rst_n),
    .cam_pwdn          (cam_pwdn),
    .cam_scl           (cam_scl),
    .cam_sda           (cam_sda),
    .capture_start     (Sdr_init_done),
    .cmos_h_pixel      (H_CMOS_DISP),
    .cmos_v_pixel      (V_CMOS_DISP),
    .total_h_pixel     (TOTAL_H_PIXEL),
    .total_v_pixel     (TOTAL_V_PIXEL),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_frame_data   (cmos_frame_data)
);

ov5640_delay u_ov5640_delay(
    .clk               (cam_pclk),
    .rst_n             (rst_n),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_wr_data      (cmos_frame_data),
    .cam_write_en      (cam_write_en),
    .cam_write_data    (cam_write_data),
    .cam_write_req     (cam_write_req),
    .cam_write_req_ack (cam_write_req_ack)
);

assign cam_write_req_ack = cam_write_req;

// =========================================
// SDRAM Frame Buffer
// =========================================
wire sdr_wr_en   = cam_write_en & Sdr_init_done;
wire [23:0] sdr_wr_data = cam_write_data[31:8]; // {R,G,B}
wire Sdr_rd_en;
wire [23:0] Sdr_rd_dout;
wire sdr_clk;
wire full_flag_sdr;
wire full_flag;
wire [11:0] udp_wrusedw;

sdram_top u_sdram (
    .SYS_CLK                (clk_50m),
    .sd_clk                 (cam_pclk),
    .sdr_data_valid         (sdr_wr_en),
    .sdr_data               (sdr_wr_data),
    .rst_n                  (rst_n),
    .sdr_clk                (sdr_clk),
    .Sdr_rd_en              (Sdr_rd_en),
    .Sdr_rd_dout            (Sdr_rd_dout),
    .Sdr_init_done          (Sdr_init_done),
    .full_flag              (full_flag),
    .full_flag_sdr          (full_flag_sdr),
    .udp_wrusedw            (udp_wrusedw)
);

// =========================================
// Signal Alignment for Processing Modules
// =========================================
reg Sdr_rd_en_aligned;
reg [23:0] Sdr_rd_dout_aligned;

always @(posedge sdr_clk or negedge rst_n) begin
    if (!rst_n) begin
        Sdr_rd_en_aligned   <= 1'b0;
        Sdr_rd_dout_aligned <= 24'd0;
    end else begin
        Sdr_rd_en_aligned   <= Sdr_rd_en;
        Sdr_rd_dout_aligned <= Sdr_rd_dout;
    end
end

wire [7:0] image_r = Sdr_rd_dout_aligned[23:16];
wire [7:0] image_g = Sdr_rd_dout_aligned[15:8];
wire [7:0] image_b = Sdr_rd_dout_aligned[7:0];
wire [23:0] image_data = {image_b, image_r, image_g};

// =========================================
// Video Processing Modules (All Instantiated)
// =========================================

// Mode 0: RAW - 原始视频（直通）
wire raw_valid = Sdr_rd_en_aligned;
wire [23:0] raw_data = Sdr_rd_dout_aligned;

// Mode 2: Blue Detection with Bounding Box
// Note: blue_bbox_overlay uses separate R,G,B inputs/outputs
wire blue_is_blue = ((image_b > 8'd96) &&
                      (image_b > image_r + 8'd40) &&
                      (image_b > image_g + 8'd40) &&
                      (image_r < 8'd120) &&
                      (image_g < 8'd140));
wire [7:0] blue_out_r, blue_out_g, blue_out_b;
wire blue_frame_start, blue_frame_end, blue_has_bbox;
wire [9:0] blue_bbox_min_x, blue_bbox_max_x;
wire [8:0] blue_bbox_min_y, blue_bbox_max_y;

blue_bbox_overlay #(
    .H_ACTIVE   (H_CMOS_DISP),
    .V_ACTIVE   (V_CMOS_DISP)
) u_blue_bbox (
    .clk            (sdr_clk),
    .rst            (!rst_n),
    .pixel_valid    (Sdr_rd_en_aligned),
    .in_r           (image_r),
    .in_g           (image_g),
    .in_b           (image_b),
    .is_blue        (blue_is_blue),
    .out_r          (blue_out_r),
    .out_g          (blue_out_g),
    .out_b          (blue_out_b),
    .frame_start_o  (blue_frame_start),
    .frame_end_o    (blue_frame_end),
    .has_bbox       (blue_has_bbox),
    .bbox_min_x     (blue_bbox_min_x),
    .bbox_max_x     (blue_bbox_max_x),
    .bbox_min_y     (blue_bbox_min_y),
    .bbox_max_y     (blue_bbox_max_y)
);

wire blue_valid = Sdr_rd_en_aligned; // Use input valid signal
wire [23:0] blue_data = {blue_out_r, blue_out_g, blue_out_b};

// Mode 3: Saturation Analysis
// Note: This module only outputs analysis result, not processed video
// So we pass through the original video while displaying analysis results
wire [3:0] sat_result_digit;

image_saturation_analyzer #(
    .FRAME_WIDTH    (H_CMOS_DISP),
    .FRAME_HEIGHT   (V_CMOS_DISP)
) u_saturation (
    .clk            (sdr_clk),
    .rst_n          (rst_n),
    .pixel_valid    (Sdr_rd_en_aligned),
    .pixel_data     (Sdr_rd_dout_aligned),
    .result_digit   (sat_result_digit)
);

// For saturation mode, we pass through original video
// (The result_digit can be displayed on 7-segment display or sent via UDP metadata)
wire sat_valid = Sdr_rd_en_aligned;
wire [23:0] sat_data = Sdr_rd_dout_aligned;

// Mode 4: Otsu Binarization + Erosion
wire binarizer_valid;
wire [23:0] binarizer_data;
wire binarizer_frame_start;
wire binarizer_frame_done;

image_binarizer #(
    .FRAME_WIDTH    (H_CMOS_DISP),
    .FRAME_HEIGHT   (V_CMOS_DISP)
) u_binarizer (
    .clk            (sdr_clk),
    .rst_n          (rst_n),
    .pixel_valid    (Sdr_rd_en_aligned),
    .pixel_data     (Sdr_rd_dout_aligned),
    .binary_valid   (binarizer_valid),
    .binary_data    (binarizer_data),
    .frame_start    (binarizer_frame_start),
    .frame_done     (binarizer_frame_done)
);

wire erosion_valid;
wire [23:0] erosion_data;

image_erosion_5x5 #(
    .FRAME_WIDTH    (H_CMOS_DISP),
    .FRAME_HEIGHT   (V_CMOS_DISP)
) u_erosion (
    .clk            (sdr_clk),
    .rst_n          (rst_n),
    .frame_start    (binarizer_frame_start),
    .pixel_valid    (binarizer_valid),
    .pixel_data     (binarizer_data),
    .erosion_valid  (erosion_valid),
    .erosion_rgb    (erosion_data)
);

// Mode 5: Sobel Edge Detection
wire sobel_valid;
wire [23:0] sobel_data;

sobel_filter #(
    .IMG_WIDTH  (H_CMOS_DISP),
    .IMG_HEIGHT (V_CMOS_DISP)
) u_sobel (
    .clk        (sdr_clk),
    .rst_n      (rst_n),
    .in_valid   (Sdr_rd_en_aligned),
    .in_pixel   (image_data),
    .out_valid  (sobel_valid),
    .out_pixel  (sobel_data)
);

// =========================================
// Output Multiplexer
// =========================================
reg        final_valid;
reg [23:0] final_data;

always @(*) begin
    case (mode_select)
        MODE_RAW: begin
            final_valid = raw_valid;
            final_data  = raw_data;
        end
        MODE_UDP_RX: begin
            // UDP接收模式：直通原始数据（预留）
            final_valid = raw_valid;
            final_data  = raw_data;
        end
        MODE_BLUE_BBOX: begin
            final_valid = blue_valid;
            final_data  = blue_data;
        end
        MODE_SATURATION: begin
            final_valid = sat_valid;
            final_data  = sat_data;
        end
        MODE_OTSU: begin
            final_valid = erosion_valid;
            final_data  = erosion_data;
        end
        MODE_SOBEL: begin
            final_valid = sobel_valid;
            final_data  = sobel_data;
        end
        MODE_RESERVED1: begin
            // 预留模式1：直通
            final_valid = raw_valid;
            final_data  = raw_data;
        end
        MODE_RESERVED2: begin
            // 预留模式2：直通
            final_valid = raw_valid;
            final_data  = raw_data;
        end
        default: begin
            final_valid = raw_valid;
            final_data  = raw_data;
        end
    endcase
end

// =========================================
// UDP/Ethernet Stack
// =========================================
wire         app_rx_data_valid;
wire [7:0]   app_rx_data;
wire [15:0]  app_rx_data_length;
wire [15:0]  app_rx_port_num;
wire         udp_tx_ready;
wire         app_tx_ack;
wire         app_tx_data_request;
wire         app_tx_data_valid;
wire [7:0]   app_tx_data;
wire [15:0]  udp_data_length;

// Ethernet clocks
wire temac_clk;
wire udp_clk;
wire temac_clk90;
wire clk_125_out;
wire clk_12_5_out;
wire clk_1_25_out;

// TEMAC signals
wire        temac_tx_ready;
wire        temac_tx_valid;
wire [7:0]  temac_tx_data;
wire        temac_tx_sof;
wire        temac_tx_eof;
wire        temac_rx_ready;
wire        temac_rx_valid;
wire [7:0]  temac_rx_data;
wire        temac_rx_sof;
wire        temac_rx_eof;
wire        rx_correct_frame;
wire        rx_error_frame;
wire [1:0]  TRI_speed = 2'b10; // 千兆以太网

// Clock generation for Ethernet
pll_gen pll_gen_inst(
    .refclk      (clk_50m),
    .reset       (!rst_n),
    .clk0_out    (temac_clk),
    .clk1_out    (udp_clk),
    .clk2_out    (temac_clk90),
    .clk3_out    (clk_125_out),
    .clk4_out    (clk_12_5_out),
    .clk5_out    (clk_1_25_out)
);

// TEMAC block
wire reset = !rst_n;
wire reset_reg;
wire [7:0] phy_reset_cnt;
wire phy_reset;
wire tx_stop;
wire [7:0] tx_ifg_val;
wire pause_req;
wire [15:0] pause_val;
wire [47:0] pause_source_addr;
wire [47:0] unicast_address;
wire [19:0] mac_cfg_vector;

temac_block u_temac(
    .glbl_rstn          (!reset),
    .reset_error        (reset_reg),
    .rx_clk             (temac_clk),
    .tx_clk             (temac_clk),
    .rx_enable          (1'b1),
    .tx_enable          (1'b1),
    .rx_data            (temac_rx_data),
    .rx_data_valid      (temac_rx_valid),
    .rx_good_frame      (rx_correct_frame),
    .rx_bad_frame       (rx_error_frame),
    .tx_data            (temac_tx_data),
    .tx_data_valid      (temac_tx_valid),
    .tx_ack             (temac_tx_ready),
    .tx_underrun        (1'b0),
    .tx_collision       (),
    .tx_retransmit      (),
    .pause_req          (pause_req),
    .pause_val          (pause_val),
    .gtx_clk            (temac_clk),
    .rgmii_tx_clk       (phy1_rgmii_tx_clk),
    .rgmii_tx_ctl       (phy1_rgmii_tx_ctl),
    .rgmii_txd          (phy1_rgmii_tx_data),
    .rgmii_rx_clk       (phy1_rgmii_rx_clk),
    .rgmii_rx_ctl       (phy1_rgmii_rx_ctl),
    .rgmii_rxd          (phy1_rgmii_rx_data),
    .speed_is_10_100    (TRI_speed[0])
);

// UDP/IP Protocol Stack
wire rx_clk_int;
wire rx_clk_en_int;
wire tx_clk_int;
wire tx_clk_en_int;

temac_clk_gen u_clk_gen(
    .clk         (temac_clk),
    .clk90       (temac_clk90),
    .rst         (reset),
    .TRI_speed   (TRI_speed),
    .rx_clk_int  (rx_clk_int),
    .rx_clk_en   (rx_clk_en_int),
    .tx_clk_int  (tx_clk_int),
    .tx_clk_en   (tx_clk_en_int)
);

// UDP loopback module - sends processed video data
udp_loopback #(
    .UDP_PKT_WORDS (UDP_PKT_WORDS),
    .UDP_PKT_BYTES (UDP_PKT_BYTES)
) u_udp_loopback(
    .clk                    (udp_clk),
    .rst                    (reset),
    .app_rx_data_valid      (app_rx_data_valid),
    .app_rx_data            (app_rx_data),
    .app_rx_data_length     (app_rx_data_length),
    .udp_tx_ready           (udp_tx_ready),
    .app_tx_ack             (app_tx_ack),
    .app_tx_data_request    (app_tx_data_request),
    .app_tx_data_valid      (app_tx_data_valid),
    .app_tx_data            (app_tx_data),
    .udp_data_length        (udp_data_length),
    .Sdr_rd_en              (Sdr_rd_en),
    .Sdr_rd_dout            (final_data),        // 使用切换后的视频数据
    .Sdr_init_done          (Sdr_init_done),
    .sdr_clk                (sdr_clk),
    .full_flag              (full_flag),
    .full_flag_sdr          (full_flag_sdr),
    .udp_wrusedw            (udp_wrusedw)
);

// UDP/IP stack (encrypted)
udp_ip_protocol_stack u_udp_stack(
    .clk                    (udp_clk),
    .rst                    (reset),
    .LOCAL_MAC_ADDRESS      (LOCAL_MAC_ADDRESS),
    .LOCAL_IP_ADDRESS       (LOCAL_IP_ADDRESS),
    .LOCAL_UDP_PORT_NUM     (LOCAL_UDP_PORT_NUM),
    .DST_IP_ADDRESS         (DST_IP_ADDRESS),
    .DST_UDP_PORT_NUM       (DST_UDP_PORT_NUM),
    .app_rx_data_valid      (app_rx_data_valid),
    .app_rx_data            (app_rx_data),
    .app_rx_data_length     (app_rx_data_length),
    .app_rx_port_num        (app_rx_port_num),
    .app_tx_data_valid      (app_tx_data_valid),
    .app_tx_data            (app_tx_data),
    .app_tx_ack             (app_tx_ack),
    .app_tx_data_request    (app_tx_data_request),
    .udp_data_length        (udp_data_length),
    .udp_tx_ready           (udp_tx_ready),
    .temac_tx_ready         (temac_tx_ready),
    .temac_tx_valid         (temac_tx_valid),
    .temac_tx_data          (temac_tx_data),
    .temac_tx_sof           (temac_tx_sof),
    .temac_tx_eof           (temac_tx_eof),
    .temac_rx_ready         (temac_rx_ready),
    .temac_rx_valid         (temac_rx_valid),
    .temac_rx_data          (temac_rx_data),
    .temac_rx_sof           (temac_rx_sof),
    .temac_rx_eof           (temac_rx_eof)
);

endmodule
