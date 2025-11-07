`define UDP_LOOP_BACK
`define DEBUG_UDP
module top(
	input                       clk,
	input                       rst_n,
    input                       key1,
    input                       key2,
 
    output			vga_out_hs,
    output			vga_out_vs,
//    output			vga_out_de,
    output	[11:0]	vga_data,
    //hdmi接口                         
	//HDMI
	output			HDMI_CLK_P,
	output			HDMI_D2_P,
	output			HDMI_D1_P,
	output			HDMI_D0_P,
	//摄像头接口                       
    input                 cam_pclk     ,  //cmos 数据像素时钟
    input                 cam_vsync    ,  //cmos 场同步信号
    input                 cam_href     ,  //cmos 行同步信号
    input   [7:0]         cam_data     ,  //cmos 数据
    output                cam_rst_n    ,  //cmos 复位信号，低电平有效
    output                cam_pwdn     ,  //电源休眠模式选择 0：正常模式 1：电源休眠模式
    output                cam_scl      ,  //cmos SCCB_SCL线
    inout                 cam_sda      ,  //cmos SCCB_SDA线
    
    //网口
    input                       phy1_rgmii_rx_clk,
    input                       phy1_rgmii_rx_ctl,
    input [3:0]                 phy1_rgmii_rx_data,
    output                      phy1_rgmii_tx_clk,
    output                      phy1_rgmii_tx_ctl,
    output [3:0]                phy1_rgmii_tx_data,
    
    `ifdef DEBUG_UDP
    output wire           debug_out,
    `endif
    
    //LED部分
    output  [15:0]        dled         ,
    output  [3:0]         led_data     ,

    //SD卡接口
    input                 sd_miso      ,  //SD卡数据输入
    output                sd_clk       ,  //SD卡时钟
    output                sd_cs        ,  //SD卡片选
    output                sd_mosi      ,  //SD卡数据输出

    //UART接口（用于命令控制）
    input                 uart_rx      ,
    output                uart_tx      ,

    //开关（用于选择视频源）
    input                 sw4             //开关4：选择摄像头或SD卡作为视频源
);

parameter MEM_DATA_BITS         = 32  ;            //external memory user interface data width
parameter ADDR_BITS             = 21  ;            //external memory user interface address width
parameter BUSRT_BITS            = 10  ;            //external memory user interface burst width

                                
parameter  V_CMOS_DISP = 11'd768;                  //CMOS分辨率--行
parameter  H_CMOS_DISP = 11'd1024;                 //CMOS分辨率--列	
parameter  TOTAL_H_PIXEL = H_CMOS_DISP + 12'd1216; //CMOS分辨率--行
parameter  TOTAL_V_PIXEL = V_CMOS_DISP + 12'd504;    										   
							   

wire                            Sdr_init_done;
wire                            Sdr_init_ref_vld;
wire                            Sdr_busy;

wire                            vga_out_de;
wire                            read_req;
wire                            read_req_ack;
wire                            read_en;
wire                            write_en;
wire                            write_req;
wire                            write_req_ack;
wire                            sd_card_clk;       //SD card controller clock
wire                            ext_mem_clk;       //external memory clock
wire                            ext_mem_clk_sft;

wire                            video_clk;         //video pixel clock
wire							hdmi_5x_clk;
wire                            hs;
wire                            vs;
wire 							de;
wire[23:0]                      vout_data;
wire[3:0]                       state_code;
wire[6:0]                       seg_data_0;


wire									  write_clk;
wire									  read_clk;

wire                            video_read_req;
wire                            video_read_req_ack;
wire                            video_read_en;
wire[31:0]                      video_read_data;
wire                            cam_write_en;
wire[31:0]                      cam_write_data;
wire                            cam_write_req;
wire                            cam_write_req_ack;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS - 1 : 0]Sdr_rd_dout;

wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS - 1 : 0]App_wr_din;
wire [3:0] App_wr_dm;

wire cmos_frame_vsync;
wire cmos_frame_href;
wire cmos_frame_valid;
wire [15:0] cmos_wr_data;

//SD卡相关信号
wire        sd_rd_start_en;
wire [31:0] sd_rd_sec_addr;
wire        sd_rd_busy;
wire        sd_rd_val_en;
wire [15:0] sd_rd_val_data;
wire        sd_init_done;
wire        sd_path_wr_en;
wire [23:0] sd_path_wr_data;
wire        sd_reset_rd_flag;
wire        clk_50m;         //50MHz时钟，用于SD卡控制器
wire        clk_50m_180deg;  //50MHz 180度相位时钟
wire        cmd_sd_read_enable;
wire        cmd_display_use_sd;

assign vga_out_hs = hs;
assign vga_out_vs = vs;
assign vga_out_de = de;
assign vga_data = {vout_data[23:20],vout_data[15:12],vout_data[7:4]};
//assign vga_out_r  = vout_data[15:11];
//assign vga_out_g  = vout_data[10:5];
//assign vga_out_b  = vout_data[4:0];
assign sdram_clk = ext_mem_clk;
//generate SD card controller clock and  SDRAM controller clock
sys_pll sys_pll_m0(
	.refclk                     (clk),
	.clk0_out                   (ext_mem_clk),
	.clk1_out                   (ext_mem_clk_sft),
    .reset						(1'b0)
    );
    
//generate video pixel clock	
video_pll video_pll_m0(
	.refclk                     (clk),
	.clk0_out                   (video_clk),
    .clk1_out					(hdmi_5x_clk),
    .reset						(1'b0)
	);
//ov5640 驱动
ov5640_dri u_ov5640_dri(
    .clk               (clk),
    .rst_n             (rst_n),

    .cam_pclk          (cam_pclk ),
    .cam_vsync         (cam_vsync),
    .cam_href          (cam_href ),
    .cam_data          (cam_data ),
    .cam_rst_n         (cam_rst_n),
    .cam_pwdn          (cam_pwdn ),
    .cam_scl           (cam_scl  ),
    .cam_sda           (cam_sda  ),
    
    .capture_start     (Sdr_init_done),
    .cmos_h_pixel      (H_CMOS_DISP),
    .cmos_v_pixel      (V_CMOS_DISP),
    .total_h_pixel     (TOTAL_H_PIXEL),
    .total_v_pixel     (TOTAL_V_PIXEL),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_frame_data   (cmos_wr_data)
    );   

ov5640_delay u_ov5640_delay(
    .clk               (cam_pclk),
    .rst_n             (rst_n),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_wr_data   (cmos_wr_data),
    
    .cam_write_req(cam_write_req),
    .cam_write_req_ack(cam_write_req_ack),
    .cam_write_en(cam_write_en),
    .cam_write_data(cam_write_data)
);
//
wire hs_0;
wire vs_0;
wire de_0;
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
    .read_data					(video_read_data[31:8]),
    .hs                         (hs_0                       ),
	.vs                         (vs_0                       ),
	.de                         (de_0                         ),
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
//video frame data read-write control
frame_read_write frame_read_write_m0(
    .mem_clk					(ext_mem_clk),
    .rst						(~rst_n),
    .Sdr_init_done				(Sdr_init_done),
    .Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
    
    .App_rd_en					(App_rd_en),
    .App_rd_addr				(App_rd_addr),
    .Sdr_rd_en					(Sdr_rd_en),
    .Sdr_rd_dout				(Sdr_rd_dout),
    
    .read_clk                   (video_clk           ),
	.read_req                   (video_read_req           ),
	.read_req_ack               (video_read_req_ack       ),
	.read_finish                (                   ),
	.read_addr_0                (24'd0              ), //first frame base address is 0
	.read_addr_1                (24'd0         ),
	.read_addr_2                (24'd0              ),
	.read_addr_3                (24'd0              ),
	.read_addr_index            (2'd0               ), //use only read_addr_0
	.read_len                   (24'd786432         ), //frame size//24'd786432
	.read_en                    (video_read_en            ),
	.read_data                  (video_read_data          ),
    
    .App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
    .App_wr_din					(App_wr_din),
    .App_wr_dm					(App_wr_dm),
    
    .write_clk                  (cam_pclk        ),
	.write_req                  (cam_write_req        ),
	.write_req_ack              (cam_write_req_ack    ),
	.write_finish               (                 ),
	.write_addr_0               (24'd0            ),
	.write_addr_1               (24'd0       ),
	.write_addr_2               (24'd0            ),
	.write_addr_3               (24'd0            ),
	.write_addr_index           (2'd0             ), //use only write_addr_0
	.write_len                  (24'd786432       ), //frame size
	.write_en                   (cam_write_en         ),
	.write_data                 (cam_write_data       )
);

//生成50MHz时钟用于SD卡控制器
//注意：这里需要根据实际的PLL IP核进行调整
//假设已有clk_50m和clk_50m_180deg从某个PLL输出
assign clk_50m = clk;  //暂时使用输入时钟，实际应该从PLL生成
assign clk_50m_180deg = clk;  //暂时使用输入时钟，实际应该从PLL生成

//UART命令控制模块
cmd_ctrl #(
    .CLK_FRE   (50),
    .BAUD_RATE (115200)
) u_cmd_ctrl (
    .clk                (clk),
    .rst_n              (rst_n),
    .uart_rx            (uart_rx),
    .uart_tx            (uart_tx),
    .default_sd_enable  (1'b1),
    .default_display_sel(sw4),
    .sd_read_enable     (cmd_sd_read_enable),
    .display_use_sd     (cmd_display_use_sd)
);

//SD卡控制器顶层模块
sd_ctrl_top u_sd_ctrl_top(
    .clk_ref                (clk_50m),
    .clk_ref_180deg         (clk_50m_180deg),
    .rst_n                  (rst_n),
    .sd_miso                (sd_miso),
    .sd_clk                 (sd_clk),
    .sd_cs                  (sd_cs),
    .sd_mosi                (sd_mosi),
    .rd_start_en            (sd_rd_start_en),
    .rd_sec_addr            (sd_rd_sec_addr),
    .rd_busy                (sd_rd_busy),
    .rd_val_en              (sd_rd_val_en),
    .rd_val_data            (sd_rd_val_data),
    .sd_init_done           (sd_init_done)
);

//SD卡读取照片模块
sd_read_photo u_sd_read_photo(
    .clk                   (clk_50m),
    .rst_n                 (rst_n & Sdr_init_done & sd_init_done),
    .ddr_max_addr          (24'd307200),  //根据实际图片大小调整
    .sd_sec_num            (16'd1801),    //根据实际扇区数调整
    .rd_busy               (sd_rd_busy),
    .sd_rd_val_en          (sd_rd_val_en),
    .sd_rd_val_data        (sd_rd_val_data),
    .rd_start_en           (sd_rd_start_en),
    .rd_sec_addr           (sd_rd_sec_addr),
    .sdr_wr_en             (sd_path_wr_en),
    .sdr_wr_data           (sd_path_wr_data),
    .full_flag_sdr         (1'b0)  //需要连接到实际的FIFO满标志
);

sdram U3
(
.Clk				(ext_mem_clk),
.Clk_sft			(ext_mem_clk_sft),
.Rst				(~rst_n),
    
.Sdr_init_done		(Sdr_init_done),
.Sdr_init_ref_vld	(Sdr_init_ref_vld),
.Sdr_busy			(Sdr_busy),
    
.App_wr_en			(App_wr_en),
.App_wr_addr		(App_wr_addr),  	
.App_wr_dm			(App_wr_dm),
.App_wr_din			(App_wr_din),
    
.App_rd_en			(App_rd_en),//data_req
.App_rd_addr		(App_rd_addr),
.Sdr_rd_en			(Sdr_rd_en),//data_valid
.Sdr_rd_dout		(Sdr_rd_dout)
);

UDP_TOP UDP_TOP_u0 (
    .key1                   (key1),
    .key2                   (key2),
    .clk_50                 (clk),

    .phy1_rgmii_rx_clk      (phy1_rgmii_rx_clk),
    .phy1_rgmii_rx_ctl      (phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data     (phy1_rgmii_rx_data),

    .phy1_rgmii_tx_clk      (phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl      (phy1_rgmii_tx_ctl),
    .phy1_rgmii_tx_data     (phy1_rgmii_tx_data),
    .led_data               (led_data),
    .dled                   (dled),
    .Sdr_rd_en              (Sdr_rd_en),
    .Sdr_init_done          (Sdr_init_done),
    
    .cam_data               (vout_data),

    .udp_clk                (udp_clk),
`ifdef DEBUG_UDP
    .debug_out              (),
`endif
	.HDMI_CLK_P             (),
	.HDMI_APP_D2_P          (),
	.HDMI_APP_D1_P          (),
	.HDMI_APP_D0_P          ()


);

endmodule 