`timescale 1ns / 1ps
//********************************************************************** 
// -------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>Copyright Notice<<<<<<<<<<<<<<<<<<<<<<<<<<<< 
// ------------------------------------------------------------------- 
//             /\ --------------- 
//            /  \ ------------- 
//           / /\ \ -----------
//          / /  \ \ ---------
//         / /    \ \ ------- 
//        / /      \ \ ----- `
//       / /_ _ _   \ \ --- 
//      /_ _ _ _ _\  \_\ -
//*********************************************************************** 
// Author: suluyang 
// Email:luyang.su@anlogic.com 
// Date:2020/11/17 
// Description: 
// 2022/03/10:  修改时钟结构
//              简化约束
//              添加 soft fifo 
//              添加 debug 功能
// 2023/02/16 :add dynamic_local_ip_address port
// 
// web：www.anlogic.com 
//------------------------------------------------------------------- 
//*********************************************************************/
`define UDP_LOOP_BACK
//  `define DEBUG_UDP
module UDP_Example_Top (
    input         clk_50,
    input         sys_rst_n,
    
    input         sd_reset_rd,
    input         sd_miso,
    output        sd_clk,
    output        sd_cs,
    output        sd_mosi,
    
    input         sw4,
    
    input         cam_pclk,
    input         cam_vsync,
    input         cam_href,
    input  [7:0]  cam_data,
    output        cam_rst_n,
    output        cam_pwdn,
    output        cam_scl,
    inout         cam_sda,
    
    input         phy1_rgmii_rx_clk,
    input         phy1_rgmii_rx_ctl,
    input  [3:0]  phy1_rgmii_rx_data,
    
    output wire         phy1_rgmii_tx_clk,
    output wire         phy1_rgmii_tx_ctl,
    output wire [3:0]   phy1_rgmii_tx_data,
    
    output      [2:0]   led,
    
    input               uart_rx,
    output              uart_tx,
    
    output			vga_out_hs,
    output			vga_out_vs,
//    output			vga_out_de,
    output	[11:0]	vga_data,
    //hdmi接口                         
	//HDMI
	output			HDMI_CLK_P,
	output			HDMI_D2_P,
	output			HDMI_D1_P,
	output			HDMI_D0_P
);

parameter DEVICE             = "EG4"; // "PH1","EG4"
parameter LOCAL_UDP_PORT_NUM = 16'h0001;
parameter LOCAL_IP_ADDRESS   = 32'hc0a8f001;
parameter LOCAL_MAC_ADDRESS  = 48'h0123456789ab;
parameter DST_UDP_PORT_NUM   = 16'h0002;
parameter DST_IP_ADDRESS     = 32'hc0a8f002;
/*------------------------------*/
/*------------------------------*/
wire         key1 = sys_rst_n;
wire         app_rx_data_valid;//synthesis keep 
wire [7:0]   app_rx_data;//synthesis keep       
wire [15:0]  app_rx_data_length;//synthesis keep
wire [15:0]  app_rx_port_num;

wire         udp_tx_ready;//synthesis keep
wire         app_tx_ack;//synthesis keep
wire         app_tx_data_request;//synthesis keep
wire         app_tx_data_valid;//synthesis keep 
wire [7:0]   app_tx_data;//synthesis keep       
wire  [15:0] udp_data_length;

wire  [7:0]  tpg_data           ;
wire         tpg_data_valid     ;
wire  [15:0] tpg_data_udp_length;

//temac signals
wire        tx_stop;
wire [7:0]  tx_ifg_val;
wire        pause_req;
wire [15:0] pause_val;
wire [47:0] pause_source_addr;
wire [47:0] unicast_address;
wire [19:0] mac_cfg_vector;  

wire        temac_tx_ready;//synthesis keep
wire        temac_tx_valid;//synthesis keep
wire [7:0]  temac_tx_data;//synthesis keep 
wire        temac_tx_sof;
wire        temac_tx_eof;

wire        temac_rx_ready;
wire        temac_rx_valid;//synthesis keep
wire [7:0]  temac_rx_data;//synthesis keep 
wire        temac_rx_sof;
wire        temac_rx_eof;

wire        rx_correct_frame;
wire        rx_error_frame;
wire [1:0]  TRI_speed;

assign TRI_speed = 2'b10;//千兆 2'b10 百兆 2'b01 十兆 2'b00

wire        rx_clk_int; 
wire        rx_clk_en_int;
wire        tx_clk_int; 
wire        tx_clk_en_int;

wire        temac_clk;//synthesis keep
wire        udp_clk;  //synthesis keep
wire        temac_clk90;//synthesis keep
wire        clk_125_out;
wire        clk_12_5_out;
wire        clk_1_25_out;
wire        phy1_rgmii_rx_clk_0;
wire        phy1_rgmii_rx_clk_90;
wire        rx_valid;//synthesis keep   
wire [7:0]  rx_data;//synthesis keep    
wire [7:0]  tx_data; //synthesis keep   
wire        tx_valid; //synthesis keep  
wire        tx_rdy;         
wire        tx_collision;   
wire        tx_retransmit;

wire        reset,reset_reg;
wire        clk_50_out;
reg [7:0]   phy_reset_cnt='d0;
reg [7:0]   soft_reset_cnt=8'hff;
reg sys_rst_n_1,sys_rst_n_2;
wire  key2;
assign key2 =sys_rst_n_2;
wire locked;
wire clk_50m ,clk_50m_180deg /* synthesis syn_keep=1 */;
assign  reset = ~key1 || reset_reg || (soft_reset_cnt != 'd0);

wire abcdsfg ;//synthesis keep = 1
assign abcdsfg = 1;
wire clk_sample;//synthesis keep = 1

wire cmd_sd_read_enable;
wire cmd_display_use_sd;

cmd_ctrl #(
    .CLK_FRE   (50),
    .BAUD_RATE (115200)
) u_cmd_ctrl (
    .clk                (clk_50),
    .rst_n              (sys_rst_n),
    .uart_rx            (uart_rx),
    .uart_tx            (uart_tx),
    .default_sd_enable  (1'b1),
    .default_display_sel(sw4),
    .sd_read_enable     (cmd_sd_read_enable),
    .display_use_sd     (cmd_display_use_sd)
);

pll_50 u_pll_50(
.refclk (clk_50)   ,
.reset  (!sys_rst_n_2)   ,
.extlock(locked)  ,
.clk0_out  (clk_50m),
.clk1_out  (clk_50m_180deg),
.clk2_out  (clk_sample)
);

clk_gen_rst_gen#(
.DEVICE         (DEVICE     )
)u_clk_gen(
.reset                (~key1                ),//~key1 
.clk_in         (clk_50     ),
.rst_out        (reset_reg  ),
.clk_125_out0   (temac_clk  ),
.clk_125_out1   (clk_125_out),
.clk_125_out2   (temac_clk90),
.clk_12_5_out   (clk_12_5_out),
.clk_1_25_out   (clk_1_25_out),
.clk_25_out     (clk_50_out ) //25mhz
);

//rx_pll u_rx_pll(
//.refclk        (phy1_rgmii_rx_clk),
//.reset       (1'b0),
//.clk0_out    (phy1_rgmii_rx_clk_0),
//.clk1_out    (phy1_rgmii_rx_clk_90)
//);

udp_clk_gen#(
.DEVICE               (DEVICE                   )
)           
u5_temac_clk_gen(           
.reset                (~key1               ),//~key1 
.tri_speed            (TRI_speed                ),
.clk_125_in           (clk_125_out              ),//125M  
.clk_12_5_in          (clk_12_5_out             ),//12.5M 
.clk_1_25_in          (clk_1_25_out             ),//1.25M 
.udp_clk_out          (udp_clk                  )
);

//generate video pixel clock	
video_pll video_pll_m0(
	.refclk                     (clk_50),
	.clk0_out                   (video_clk),
    .clk1_out					(hdmi_5x_clk),
    .reset						(1'b0)
	);

//wire video_clk = clk_50_out;
//wire hdmi_5x_clk = clk_125_out;

always @(posedge clk_50 or negedge sys_rst_n)           
begin                                        
if(!sys_rst_n)  begin
sys_rst_n_1 <= 1'b0;
sys_rst_n_2 <= 1'b0;
end                             

else begin
sys_rst_n_1 <= sys_rst_n;
sys_rst_n_2 <= sys_rst_n_1;
end                                                                 
end                                          
wire rst_n/* synthesis syn_keep=1 */;
assign  rst_n = sys_rst_n_2 ;    

wire        sdr_wr_en;//synthesis keep 
wire [23:0] sdr_wr_data;//synthesis keep 
wire        full_flag_sdr;
wire        full_flag;
wire Sdr_init_done/* synthesis syn_keep=1 */;

wire        sd_rd_start_en;
wire [31:0] sd_rd_sec_addr;
wire        sd_rd_busy;
wire        sd_rd_val_en;
wire [15:0] sd_rd_val_data;
wire        sd_init_done/* synthesis syn_keep=1 */;
wire        sd_path_wr_en;
wire [23:0] sd_path_wr_data;
wire        sd_reset_rd_flag;
wire        sd_card_clk;

sd_ctrl_top u_sd_ctrl_top(
    .clk_ref                (clk_50m),
    .clk_ref_180deg         (clk_50m_180deg),
    .rst_n                  (rst_n),
    .sd_miso                (sd_miso),
    .sd_clk                 (sd_card_clk),
    .sd_cs                  (sd_cs),
    .sd_mosi                (sd_mosi),
    .rd_start_en            (sd_rd_start_en),
    .rd_sec_addr            (sd_rd_sec_addr),
    .rd_busy                (sd_rd_busy),
    .rd_val_en              (sd_rd_val_en),
    .rd_val_data            (sd_rd_val_data),
    .sd_init_done           (sd_init_done)
    );

assign sd_clk = sd_card_clk;

reg sd_reset_rd_d0, sd_reset_rd_d1;
always @(posedge clk_50 or negedge rst_n)
begin
    if(!rst_n) begin
        sd_reset_rd_d0 <= 1'b0;
        sd_reset_rd_d1 <= 1'b0;
    end else begin
        sd_reset_rd_d0 <= sd_reset_rd;
        sd_reset_rd_d1 <= sd_reset_rd_d0;
    end
end

wire use_sd_data;
reg use_sd_rst_d0, use_sd_rst_d1;
always @(posedge clk_50 or negedge rst_n)
begin
    if(!rst_n) begin
        use_sd_rst_d0 <= 1'b0;
        use_sd_rst_d1 <= 1'b0;
    end else begin
        use_sd_rst_d0 <= use_sd_data;
        use_sd_rst_d1 <= use_sd_rst_d0;
    end
end
assign sd_reset_rd_flag = (use_sd_rst_d1 && {sd_reset_rd_d0,sd_reset_rd_d1} == 2'b10) ? 1'b0 : use_sd_rst_d1;

sd_read_photo u_sd_read_photo(
    .clk                   (clk_50m),
    .rst_n                 (rst_n & Sdr_init_done & sd_init_done & sd_reset_rd_flag),
    .ddr_max_addr          (24'd307200),
    .sd_sec_num            (16'd1801),
    .rd_busy               (sd_rd_busy),
    .sd_rd_val_en          (sd_rd_val_en),
    .sd_rd_val_data        (sd_rd_val_data),
    .rd_start_en           (sd_rd_start_en),
    .rd_sec_addr           (sd_rd_sec_addr),
    .sdr_wr_en             (sd_path_wr_en),
    .sdr_wr_data           (sd_path_wr_data),
    .full_flag_sdr         (full_flag_sdr)
    );

// 分辨率设置：640×480，保持与19fps工程一致的行/帧节奏
localparam [12:0] H_CMOS_DISP    = 13'd640;  // 有效列数
localparam [12:0] V_CMOS_DISP    = 13'd480;  // 有效行数
localparam [12:0] TOTAL_H_PIXEL  = H_CMOS_DISP + 13'd1216; // =1856，总像素（含消隐）
// 帧率调节：56 MHz / (1856 × TOTAL_V_PIXEL)，当前选择约22 fps
localparam [12:0] TOTAL_V_PIXEL  = V_CMOS_DISP + 13'd891;

localparam integer UDP_PKT_WORDS = 480;             // 480 × 3 = 1440-byte UDP payload
localparam integer UDP_PKT_BYTES = UDP_PKT_WORDS * 3; // 1440字节

wire        cmos_frame_vsync;
wire        cmos_frame_href;
wire        cmos_frame_valid;
wire [15:0] cmos_frame_data;
wire        cam_write_req;
wire        cam_write_req_ack;
wire        cam_write_en;
wire [31:0] cam_write_data;

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

wire        cam_wr_en_raw  = cam_write_en & Sdr_init_done;
wire [23:0] cam_wr_data_raw = cam_write_data[31:8];
wire wr_data_clk;

sdram_write_static_sel #(
.DATA_WIDTH(24),
.DEVICE    (DEVICE)
) u_sdram_write_sel (
.rst_n      (rst_n),
.clk_cfg    (clk_50m),
.clk_a      (cam_pclk),
.clk_b      (clk_50m),
.sel_raw    (1'b0),
.en_a_raw   (cam_wr_en_raw),
.data_a_raw (cam_wr_data_raw),
.en_b_raw   (sd_path_wr_en),
.data_b_raw (sd_path_wr_data),
.clk_out    (wr_data_clk),
.en_out     (sdr_wr_en),
.data_out   (sdr_wr_data),
.sel_sync   (use_sd_data)
);

wire Sdr_rd_en            ;//synthesis keep
wire [31:0] Sdr_rd_dout   ;//synthesis keep
wire sdr_clk;
wire  [11:0] udp_wrusedw;//synthesis keep

sdram_top t3_sdram (
.SYS_CLK                            (clk_50m                   ),
.sd_clk                             (wr_data_clk               ),
.sdr_data_valid                     (sdr_wr_en                 ),
.sdr_data                           (sdr_wr_data               ),
.rst_n                              (rst_n                     ),
.sdr_clk                            (sdr_clk),
.Sdr_rd_en                          (Sdr_rd_en                 ),  
.Sdr_rd_dout                        (Sdr_rd_dout               ) , 
.Sdr_init_done                      (Sdr_init_done             ) ,
.full_flag                            (full_flag),
.full_flag_sdr  (full_flag_sdr),
.udp_wrusedw  (udp_wrusedw)
);

always @(posedge clk_50_out or negedge key1)
begin
if(~key1)
phy_reset_cnt<='d0;
else if(phy_reset_cnt < 255)
phy_reset_cnt<= phy_reset_cnt+1;
else
phy_reset_cnt<=phy_reset_cnt;
end

assign  reset = ~key1 || reset_reg || (soft_reset_cnt != 'd0);
assign  phy_reset = phy_reset_cnt[7];

always @(posedge udp_clk or negedge key1)
begin
if(~key1)
soft_reset_cnt<=8'hff;
else if(soft_reset_cnt > 0)
soft_reset_cnt<= soft_reset_cnt-1;
else
soft_reset_cnt<=soft_reset_cnt;
end

//============================================================
// 参数设置逻辑
//============================================================
//需设置的客户端接口（初始默认值）
assign  tx_stop    = 1'b0;
assign  tx_ifg_val = 8'h00;
assign  pause_req  = 1'b0;
assign  pause_val  = 16'h0;
assign  pause_source_addr = 48'h5af1f2f3f4f5;
// assign  unicast_address   = 48'hab8967452301;
assign  unicast_address   = {   LOCAL_MAC_ADDRESS[7:0],
LOCAL_MAC_ADDRESS[15:8],
LOCAL_MAC_ADDRESS[23:16],
LOCAL_MAC_ADDRESS[31:24],
LOCAL_MAC_ADDRESS[39:32],
LOCAL_MAC_ADDRESS[47:40]
};

assign  mac_cfg_vector    = {1'b0,2'b00,TRI_speed,8'b00000010,7'b0000010}; //地址过滤模式、流控设置、速度设置、接收器设置、发送器设置
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b10,8'b00000010,7'b0000010}; //地址过滤模式、流控设置、速度设置、接收器设置、发送器设置
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b01,8'b00000010,7'b0000010}; //地址过滤模式、流控设置、速度设置、接收器设置、发送器设置
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b00,8'b00000010,7'b0000010}; //地址过滤模式、流控设置、速度设置、接收器设置、发送器设置

//-----------------------------------------------------
//test dynamic_local_ip_address
//-----------------------------------------------------

//参数定义
reg [32:0] cnt0;
wire      end_cnt0;
wire      add_cnt0;
reg [7:0] cnt1;
wire      end_cnt1;
wire      add_cnt1;

wire rst_n ;
//计数器2
always @(posedge udp_clk or negedge sys_rst_n_2)begin
if(!sys_rst_n_2)begin
cnt0 <= 0;
end
else if(add_cnt0)begin
if(end_cnt0)
cnt0 <= 0;
else
cnt0 <= cnt0 + 1;
end
end

assign add_cnt0 = 1;
assign end_cnt0 = add_cnt0 && 0;

always @(posedge udp_clk or negedge sys_rst_n_2)begin 
if(!sys_rst_n_2)begin
cnt1 <= 0;
end
else if(add_cnt1)begin
if(end_cnt1)
cnt1 <= 0;
else
cnt1 <= cnt1 + 1;
end
end

assign add_cnt1 = end_cnt0;
assign end_cnt1 = add_cnt1 && cnt1== 15;  

reg [31:0]  input_local_ip_address;
reg         input_local_ip_address_valid;

always@(posedge udp_clk or posedge reset)
begin
if(reset) 
begin
input_local_ip_address      <= LOCAL_IP_ADDRESS;
input_local_ip_address_valid<= 1'b0;
end
else if(end_cnt0 == 1'b1)
begin
input_local_ip_address      <= {LOCAL_IP_ADDRESS[31:8],cnt1};
input_local_ip_address_valid<= 1'b1;
end
else
begin
input_local_ip_address      <= input_local_ip_address;
input_local_ip_address_valid<= 1'b1;
end
end

assign led[0] = Sdr_init_done;      // SDRAM 是否初始化完成
assign led[1] = cam_write_en;       // 摄像头写 SDRAM 的握手
assign led[2] = Sdr_rd_en_aligned;  // 读侧是否有数据

reg [15:0] input_local_udp_port_num;
reg        input_local_udp_port_num_valid;

always@(posedge udp_clk or posedge reset)
begin
if(reset) 
begin
input_local_udp_port_num      <= LOCAL_UDP_PORT_NUM;
input_local_udp_port_num_valid<= 1'b0;
end
else
begin
input_local_udp_port_num      <= input_local_ip_address[3:0] + 3;
input_local_udp_port_num_valid<= 1'b1;
end
end

//-----------------------------------------------------

//app
//app u_app (
//    .sys_clk                    (clk_50                ),
//    .udp_rx_clk                 (udp_clk                ),
//    .udp_tx_clk                 (udp_clk                ),
//    .reset                      (key2                  ), 
//    .app_rx_data_valid          (app_rx_data_valid      ), 
//    .app_rx_data                (app_rx_data            ), 
//    .app_rx_data_length         (app_rx_data_length     ), 
//    .app_rx_port_num            (app_rx_port_num        ),
//    .VGA_HSYNC                    (VGA_HSYNC              ),
//    .VGA_VSYNC                     (VGA_VSYNC              ),
//    .VGA_D                      (VGA_D                  ),
//    .rd_en                      (rd_en                  )
//);

/*vga_bmp u_vga_bmp
(   .VGA_HSYNC                    (VGA_HSYNC              ),
.VGA_VSYNC                     (VGA_VSYNC              ),
.VGA_D                      (VGA_D                  ),
.sys_clk                    (clk_50                ),
.reset                      (key2                  )
);*/

udp_data_tpg u1_udp_data_tpg(
.clk                (udp_clk            ),
.reset              (~key2              ),

.tpg_data           (tpg_data           ),//数据输出
.tpg_data_valid     (tpg_data_valid     ),//数据有效信号
.tpg_data_udp_length(tpg_data_udp_length),//数据长度（包含帧头）
.tpg_data_done      (tpg_data_done      ),

.tpg_data_enable    (phy_reset          ),
.tpg_data_header0   (16'haabb           ),//帧头0
.tpg_data_header1   (16'hccdd           ),//帧头1
.tpg_data_type      (16'ha8b8           ),//数据帧类型
.tpg_data_length    (16'h00ff           ),//数据长度500
.tpg_data_num       (16'h000a           ),//产生的帧个数10
.tpg_data_ifg       (8'd130             )
);

sdram_read_align u_sdram_read_align (
        .clk               (sdr_clk),
        .rst_n             (rst_n),
        .sdr_rd_en         (Sdr_rd_en),
        .sdr_rd_dout       (Sdr_rd_dout[31:8]),  // SDRAM 输出 32bit，去掉最低 8bit
        .sdr_rd_en_aligned (Sdr_rd_en_aligned),
        .image_r           (image_r),
        .image_g           (image_g),
        .image_b           (image_b)
    );

wire [23:0] image_data;

wire        video_read_en;

wire [23:0] sdr_image_data;

wire        video_fifo_re;

wire [23:0] video_fifo_dout;

wire        video_fifo_valid;

reg  [23:0] video_pixel_data;
wire        video_read_req;
wire        video_read_req_ack;
wire [23:0] vout_data;

assign video_read_req_ack = video_read_req;

assign vga_out_hs = hs;
assign vga_out_vs = vs;
assign vga_out_de = de;
assign vga_data = {vout_data[23:20],vout_data[15:12],vout_data[7:4]};
assign sdr_image_data = {image_r, image_g, image_b};

assign image_data     = sdr_image_data;

fifo_sdr_data_2 #(

    .DATA_WIDTH_W(24),
    .DATA_WIDTH_R(24),
    .ADDR_WIDTH_W(12),
    .ADDR_WIDTH_R(12)

) u_video_frame_fifo (

    .rst        (~rst_n),
    .clkw       (sdr_clk),
    .clkr       (video_clk),
    .we         (Sdr_rd_en),
    .di         (Sdr_rd_dout[31:8]),
    .re         (video_fifo_re),
    .dout       (video_fifo_dout),
    .valid      (video_fifo_valid),
    .full_flag  (),
    .empty_flag (),
    .afull      (),
    .aempty     (),
    .wrusedw    (),
    .rdusedw    ()

);

assign video_fifo_re = video_read_en & video_fifo_valid;

always @(posedge video_clk or negedge rst_n) begin

    if (!rst_n) begin

        video_pixel_data <= 24'd0;

    end else if (video_fifo_re) begin

        video_pixel_data <= video_fifo_dout;

    end else if (video_read_en && !video_fifo_valid) begin

        video_pixel_data <= 24'd0;

    end

end

wire hs_0;

wire vs_0;
wire de_0;

// wire color_bar_hs;
// wire color_bar_vs;
// wire color_bar_de;
// wire [7:0] color_bar_r;
// wire [7:0] color_bar_g;
// wire [7:0] color_bar_b;

// color_bar u_color_bar (
//     .clk   (video_clk),
//     .rst   (~rst_n),
//     .hs    (color_bar_hs),
//     .vs    (color_bar_vs),
//     .de    (color_bar_de),
//     .rgb_r (color_bar_r),
//     .rgb_g (color_bar_g),
//     .rgb_b (color_bar_b)
// );

video_timing_data video_timing_data_m0
(
	.video_clk                  (video_clk                ),
	.rst                        (~rst_n    ),
	.read_req                   (video_read_req           ),
	.read_req_ack               (video_read_req_ack       ),
	//.read_en                    (video_read_en            ),
	//.read_data                  (video_read_data          ),
	.hs                         (hs_0                       ),
	.vs                         (vs_0                       ),
	.de                         (de_0                         )
    

	//.vout_data                  (vout_data                )
);

video_delay video_delay_m0
(
    .video_clk                  (video_clk                ),
	.rst                        (~rst_n    ),
    .read_en					(video_read_en),
    .read_data					(video_pixel_data),
    .hs                         (hs_0),
	.vs                         (vs_0),
	.de                         (de_0),
	.hs_r                       (hs                       ),
	.vs_r                       (vs                       ),
	.de_r                       (de                       ),
	.vout_data					(vout_data)
);
hdmi_tx #(.FAMILY("EG4"))	//EF2、EF3、EG4、AL3、PH1

 u3_hdmi_tx
	(
		.PXLCLK_I(video_clk),
		.PXLCLK_5X_I(hdmi_5x_clk),

		.RST_N (rst_n),
		
		//VGA
		.VGA_HS (hs ),
		.VGA_VS (vs ),
		.VGA_DE (de ),
		.VGA_RGB(vout_data),

		//HDMI
		.HDMI_CLK_P             (HDMI_CLK_P),
	.HDMI_D2_P          (HDMI_D2_P),
	.HDMI_D1_P          (HDMI_D1_P),
	.HDMI_D0_P          (HDMI_D0_P)
		
	);

//------------------------------------------------------------
//udp_loopback
//------------------------------------------------------------
udp_loopback#(
.DEVICE(DEVICE),
.WORDS_PER_PKT(UDP_PKT_WORDS)
)
u2_udp_loopback
(
.app_rx_clk                 (sdr_clk                ),
.app_tx_clk                 (udp_clk                ),
.reset                      (reset                ),//reset
.udp_wrusedw                   (udp_wrusedw),
`ifdef UDP_LOOP_BACK    
.app_rx_data                (image_data      ),
.app_rx_data_valid          (Sdr_rd_en_aligned ),  // 使用对齐后的读使能
.app_rx_data_length         (UDP_PKT_BYTES[15:0]    ),
`else   
.app_rx_data                (tpg_data               ),
.app_rx_data_valid          (tpg_data_valid         ),
.app_rx_data_length         (tpg_data_udp_length    ),
`endif              
.full_flag                  (full_flag),
.udp_tx_ready               (udp_tx_ready           ),
.app_tx_ack                 (app_tx_ack             ),
.app_tx_data                (app_tx_data            ),
.app_tx_data_request        (app_tx_data_request    ),
.app_tx_data_valid          (app_tx_data_valid      ),
.udp_data_length            (udp_data_length        )   
);

// udp_loopback#(
//    .DEVICE(DEVICE)
// )
// u2_udp_loopback
// (
//    .app_rx_clk                 (udp_clk                ),
//    .app_tx_clk                 (udp_clk                ),
//    .reset                      (reset                 ),//reset

//    `ifdef UDP_LOOP_BACK    
//    .app_rx_data                (app_rx_data            ),
//    .app_rx_data_valid          (app_rx_data_valid      ),
//    .app_rx_data_length         (app_rx_data_length     ),
//    `else   
//    .app_rx_data                (tpg_data               ),
//    .app_rx_data_valid          (tpg_data_valid         ),
//    .app_rx_data_length         (tpg_data_udp_length    ),
//    `endif              

//    .udp_tx_ready               (udp_tx_ready           ),
//    .app_tx_ack                 (app_tx_ack             ),
//    .app_tx_data                (app_tx_data            ),
//    .app_tx_data_request        (app_tx_data_request    ),
//    .app_tx_data_valid          (app_tx_data_valid      ),
//    .udp_data_length            (udp_data_length        )   
// );
//------------------------------------------------------------  
//UDP
//------------------------------------------------------------       
udp_ip_protocol_stack #
(
.DEVICE                     (DEVICE                 ),
.LOCAL_UDP_PORT_NUM         (LOCAL_UDP_PORT_NUM     ),
.LOCAL_IP_ADDRESS           (LOCAL_IP_ADDRESS       ),
.LOCAL_MAC_ADDRESS          (LOCAL_MAC_ADDRESS      )
)   
u3_udp_ip_protocol_stack    
(   
.udp_rx_clk                 (udp_clk                ),
.udp_tx_clk                 (udp_clk                ),
.reset                      (reset                 ), 
.udp2app_tx_ready           (udp_tx_ready           ), 
.udp2app_tx_ack             (app_tx_ack             ), 
.app_tx_request             (app_tx_data_request    ), 
.app_tx_data_valid          (app_tx_data_valid      ), 
.app_tx_data                (app_tx_data            ), 
.app_tx_data_length         (udp_data_length        ), 
.app_tx_dst_port            (DST_UDP_PORT_NUM       ), 
.ip_tx_dst_address          (DST_IP_ADDRESS         ), 

.input_local_udp_port_num      (input_local_udp_port_num      ),
.input_local_udp_port_num_valid(input_local_udp_port_num_valid),

.input_local_ip_address     (input_local_ip_address     ),
.input_local_ip_address_valid(input_local_ip_address_valid),

.app_rx_data_valid          (app_rx_data_valid      ), 
.app_rx_data                (app_rx_data            ), 
.app_rx_data_length         (app_rx_data_length     ), 
.app_rx_port_num            (app_rx_port_num        ), 
.temac_rx_ready             (temac_rx_ready         ),//output
.temac_rx_valid             (!temac_rx_valid        ),//input
.temac_rx_data              (temac_rx_data          ),//input
.temac_rx_sof               (temac_rx_sof           ),//input
.temac_rx_eof               (temac_rx_eof           ),//input
.temac_tx_ready             (temac_tx_ready         ),//input
.temac_tx_valid             (temac_tx_valid         ),//output
.temac_tx_data              (temac_tx_data          ),//output
.temac_tx_sof               (temac_tx_sof           ),//output
.temac_tx_eof               (temac_tx_eof           ),//output
`ifdef DEBUG_UDP
.udp_debug_out              (udp_debug_out          ),
`endif
.ip_rx_error                (                       ), 
.arp_request_no_reply_error (                       )
);
//------------------------------------------------------------  
//TEMAC
//------------------------------------------------------------  
temac_block#(
.DEVICE               (DEVICE                   )
)  
u4_trimac_block
(
.reset                (reset                   ),
.gtx_clk              (clk_125_out                ),//input   125M
.gtx_clk_90           (temac_clk90                ),//input   125M
.rx_clk               (rx_clk_int               ),//output  125M 25M    2.5M
.rx_clk_en            (rx_clk_en_int            ),//output  1    12.5M  1.25M
.rx_data              (rx_data                  ),
.rx_data_valid        (rx_valid                 ),
.rx_correct_frame     (rx_correct_frame         ),
.rx_error_frame       (rx_error_frame           ),
.rx_status_vector     (                         ),
.rx_status_vld        (                         ),
//  .tri_speed            (tri_speed                ),//output
.tx_clk               (tx_clk_int               ),//output  125M
.tx_clk_en            (tx_clk_en_int            ),//output  1    12.5M  1.25M 占空比不对
.tx_data              (tx_data                  ),
.tx_data_en           (tx_valid                 ),
.tx_rdy               (tx_rdy                   ),//temac_tx_ready
.tx_stop              (tx_stop                  ),//input
.tx_collision         (tx_collision             ),
.tx_retransmit        (tx_retransmit            ),
.tx_ifg_val           (tx_ifg_val               ),//input
.tx_status_vector     (                         ),
.tx_status_vld        (                         ),
.pause_req            (pause_req                ),//input
.pause_val            (pause_val                ),//input
.pause_source_addr    (pause_source_addr        ),//input
.unicast_address      (unicast_address          ),//input
.mac_cfg_vector       (mac_cfg_vector           ),//input
.rgmii_txd            (phy1_rgmii_tx_data       ),
.rgmii_tx_ctl         (phy1_rgmii_tx_ctl        ),
.rgmii_txc            (phy1_rgmii_tx_clk        ),
.rgmii_rxd            (phy1_rgmii_rx_data       ),
.rgmii_rx_ctl         (phy1_rgmii_rx_ctl        ),
.rgmii_rxc            (phy1_rgmii_rx_clk_90        ),
.inband_link_status   (                         ),
.inband_clock_speed   (                         ),
.inband_duplex_status (                         )
);

tx_client_fifo #
(
.DEVICE               (DEVICE                   )
)
u6_tx_fifo
(
.rd_clk               (tx_clk_int               ),
.rd_sreset            (reset                   ),
.rd_enable            (tx_clk_en_int            ),
.tx_data              (tx_data                  ),
.tx_data_valid        (tx_valid                 ),
.tx_ack               (tx_rdy                   ),
.tx_collision         (tx_collision             ),
.tx_retransmit        (tx_retransmit            ),
.overflow             (                         ),

.wr_clk               (udp_clk                  ),
.wr_sreset            (reset                   ),
.wr_data              (temac_tx_data            ),
.wr_sof_n             (temac_tx_sof             ),
.wr_eof_n             (temac_tx_eof             ),
.wr_src_rdy_n         (temac_tx_valid           ),
.wr_dst_rdy_n         (temac_tx_ready           ),//temac_tx_ready
.wr_fifo_status       (                         )
);

rx_client_fifo# 
(
.DEVICE               (DEVICE                   )
)                           
u7_rx_fifo                  
(                           
.wr_clk               (rx_clk_int               ),
.wr_enable            (rx_clk_en_int            ),
.wr_sreset            (reset                    ),
.rx_data              (rx_data                  ),
.rx_data_valid        (rx_valid                 ),
.rx_good_frame        (rx_correct_frame         ),
.rx_bad_frame         (rx_error_frame           ),
.overflow             (                         ),
.rd_clk               (udp_clk                  ),
.rd_sreset            (reset                   ),
.rd_data_out          (temac_rx_data            ),//output reg [7:0] rd_data_out,
.rd_sof_n             (temac_rx_sof             ),//output reg       rd_sof_n,
.rd_eof_n             (temac_rx_eof             ),//output           rd_eof_n,
.rd_src_rdy_n         (temac_rx_valid           ),//output reg       rd_src_rdy_n,
.rd_dst_rdy_n         (temac_rx_ready           ),//input            rd_dst_rdy_n,
.rx_fifo_status       (                         )
);

endmodule
