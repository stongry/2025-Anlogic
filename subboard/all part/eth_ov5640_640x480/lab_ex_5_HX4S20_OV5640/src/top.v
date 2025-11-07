//`define UDP_LOOP_BACK
`define DEBUG_UDP
`define UDP_DEBUG_TX_MODE  // 开启UDP调试发送模式
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

	// //摄像头接口                       
    // input                 cam_pclk     ,  //cmos 数据像素时钟
    // input                 cam_vsync    ,  //cmos 场同步信号
    // input                 cam_href     ,  //cmos 行同步信号
    // input   [7:0]         cam_data     ,  //cmos 数据
    // output                cam_rst_n    ,  //cmos 复位信号，低电平有效
    // output                cam_pwdn     ,  //电源休眠模式选择 0：正常模式 1：电源休眠模式
    // output                cam_scl      ,  //cmos SCCB_SCL线
    // inout                 cam_sda      ,  //cmos SCCB_SDA线
    
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
    output  [3:0]         led_data
);

parameter MEM_DATA_BITS         = 32  ;            //external memory user interface data width
parameter ADDR_BITS             = 21  ;            //external memory user interface address width
parameter BUSRT_BITS            = 10  ;            //external memory user interface burst width
 										   
							   

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
wire[23:0]                      vout_data;
wire[3:0]                       state_code;
wire[6:0]                       seg_data_0;


wire									  write_clk;
wire									  read_clk;

wire                            video_read_req;
wire                            video_read_req_ack;
wire                            video_read_en;
wire[31:0]                      video_read_data;
wire                            udp_write_en;
wire[31:0]                      udp_write_data;


wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS - 1 : 0]Sdr_rd_dout;

wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS - 1 : 0]App_wr_din;
wire [3:0] App_wr_dm;

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
    .clk2_out                   (colorbar_clk),
    .reset						(1'b0)
    );
//generate video pixel clock	
video_pll video_pll_m0(
	.refclk                     (clk),
	.clk0_out                   (video_clk),
    .clk1_out					(hdmi_5x_clk),

    .reset						(1'b0)
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
		.HDMI_CLK_P(HDMI_CLK_P ),
		.HDMI_D2_P (HDMI_D2_P  ),
		.HDMI_D1_P (HDMI_D1_P  ),
		.HDMI_D0_P (HDMI_D0_P  )	
		
	);

//color bar generator test
// outports wire
// wire [7:0]  	rgb_r;
// wire [7:0]  	rgb_g;
// wire [7:0]  	rgb_b;
// wire [15:0] 	rgb565_data;
// wire        	color_bar_data_valid;
// wire [31:0]     color_bar_data;
// wire        	color_bar_write_req;
// wire       	color_bar_write_req_ack;

// assign color_bar_data = {rgb_r,rgb_g,rgb_b,8'b0};

// color_bar u_color_bar(
// 	.clk         	( colorbar_clk  ),
// 	.rst         	( ~rst_n        ),
//     .write_req      (color_bar_write_req),

// 	.hs          	(            ),
// 	.vs          	(            ),
// 	.de          	(            ),
// 	.rgb_r       	( rgb_r        ),
// 	.rgb_g       	( rgb_g        ),
// 	.rgb_b       	( rgb_b        ),
// 	.rgb565_data 	(              ),

//     .write_req_ack ( color_bar_write_req_ack      ),
// 	.data_valid  	( color_bar_data_valid   )
// );

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
	.read_addr_1                (24'd0              ),
	.read_addr_2                (24'd0              ),
	.read_addr_3                (24'd0              ),
	.read_addr_index            (2'd0               ), //use only read_addr_0
	.read_len                   (24'd307200         ), //frame size//24'd786432
	.read_en                    (video_read_en            ),
	.read_data                  (video_read_data          ),
    
    .App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
    .App_wr_din					(App_wr_din),
    .App_wr_dm					(App_wr_dm),
    
    .write_clk                  (udp_clk        ),
	.write_req                  (udp_write_req        ),
	.write_req_ack              (udp_write_req_ack    ),
	.write_finish               (                 ),
	.write_addr_0               (24'd0            ),
	.write_addr_1               (24'd0            ),
	.write_addr_2               (24'd0            ),
	.write_addr_3               (24'd0            ),
	.write_addr_index           (2'd0             ), //use only write_addr_0
	.write_len                  (24'd307200       ), //frame size
	.write_en                   (udp_data_valid ),
	.write_data                 ({rgb_data,8'b0}       )
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

wire            udp_write_req;
wire            udp_write_req_ack;
wire            udp_data_valid;
wire[23:0]      rgb_data;

// 调试数据多路复用器的信号
wire [7:0]      debug_tx_data;
wire            debug_tx_data_valid;
wire [15:0]     debug_tx_data_length;

// 实例化调试数据多路复用器（监控真实的RGB和SDRAM信号）
debug_data_mux debug_data_mux_u0(
    .clk                    (udp_clk),
    .rst_n                  (rst_n),

    // RGB数据信号
    .rgb_data_valid         (udp_data_valid),
    .rgb_data               (rgb_data),
    .rgb_write_req          (udp_write_req),
    .rgb_write_req_ack      (udp_write_req_ack),

    // SDRAM信号
    .sdram_wr_en            (App_wr_en),
    .sdram_wr_addr          (App_wr_addr),
    .sdram_wr_data          (App_wr_din),
    .sdram_rd_en            (Sdr_rd_en),
    .sdram_rd_addr          (App_rd_addr),
    .sdram_rd_data          (Sdr_rd_dout),

    // UDP调试输出
    .debug_tx_data          (debug_tx_data),
    .debug_tx_data_valid    (debug_tx_data_valid),
    .debug_tx_data_length   (debug_tx_data_length)
);

// 测试生成器（已注释，用于验证UDP通信）
// debug_data_gen debug_data_gen_u0(
//     .clk                    (udp_clk),
//     .rst_n                  (rst_n),
//     .debug_tx_data          (debug_tx_data),
//     .debug_tx_data_valid    (debug_tx_data_valid),
//     .debug_tx_data_length   (debug_tx_data_length)
// );

UDP_TOP UDP_TOP_u0 (
    .key1                   (key1),
    .key2                   (key2),
    .clk_50                 (clk),
    .udp_write_req          (udp_write_req),

    .phy1_rgmii_rx_clk      (phy1_rgmii_rx_clk),
    .phy1_rgmii_rx_ctl      (phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data     (phy1_rgmii_rx_data),

    .phy1_rgmii_tx_clk      (phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl      (phy1_rgmii_tx_ctl),
    .phy1_rgmii_tx_data     (phy1_rgmii_tx_data),

    .led_data               (led_data),
    .dled                   (dled),

    .udp_data_valid         (udp_data_valid),
    .rgb888_data            (rgb_data), //24位
    .udp_write_req_ack      (udp_write_req_ack),

    // 调试数据输入接口
    `ifdef UDP_DEBUG_TX_MODE
    .sdram_debug_tx_data        (debug_tx_data),
    .sdram_debug_tx_data_valid  (debug_tx_data_valid),
    .sdram_debug_tx_data_length (debug_tx_data_length),
    `endif

`ifdef DEBUG_UDP
    .debug_out              (debug_out),
`endif
	.udp_clk                (udp_clk)
);

endmodule 