`timescale 1ns/ 1ps
// --------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>>> COPYRIGHT NOTICE <<<<<<<<<<<<<<<<<<<<<<<<<
// --------------------------------------------------------------------
// 
// Author: Anlogic
// 
// Description:
//
//		dvp_ov2640,摄像头VGA显示
// 
// Web: www.anlogic.com
// --------------------------------------------------------------------
module test_camera
(
	input 	wire 		clk_24m,	//系统时钟
	input 	wire 		rst_n,		//复位
	//camera	
	input 	wire 		cam_pclk,	//像素时钟
	output 	wire 		cam_xclk,	//系统时钟
	input 	wire 		cam_href,	//行同
	input 	wire 		cam_vsync,	//帧同
	output 	wire 		cam_pwdn,	//模式
	output 	wire 		cam_rst,	//复位
	output 	wire 		cam_soic,	//SCCB
	inout 	wire 		cam_soid,	//SCCB
	input 	wire [7:0]	cam_data,	//
	//vga
	output 	wire [7:0] 	vga_r,
	output 	wire [7:0] 	vga_g,
	output 	wire [7:0] 	vga_b,
	output 	wire 		vga_clk,
	output 	wire 		vga_hsync,
	output 	wire 		vga_vsync
    //output wire [3:0]slect_aw,  //选择一个数码管
    //output wire [7:0]a_data_outw 

 );
	 
wire 		clk_lcd;
wire 		clk_cam;
wire 		clk_sccb;
wire         clk_div;       //自己加的时钟分频
wire   [2:0]SE_RAM;//自己加的ram选择信号
wire   img_ack_ALL; ////控制TOP层的 vga_r、g、b

wire        camera_wrreq;
wire        camera_wclk;
wire [15:0] camera_wrdat;
wire [19:0] camera_addr;

reg 		init_state;
wire 		init_ready;
wire 		sda_oe;
wire 		sda;
wire 		sda_in;
wire 		scl;

 reg [2:0] SE_RAM_fft1;

//lcd display
wire [10:0] hsync_cnt;
wire [10:0] vsync_cnt;
wire 		vga_rden;
wire [15:0]	vga_rddat;	//lcd read
reg [15:0]	vga_data;	//最后的输出数据，根据SE_RAM选择
//wire [15:0]	vga_data;	//最后的数据，根据SE_RAM选择
wire [15:0   ]vga_addr;  //自己加的读vag信号的地址
reg  [15:0]	vga_rdaddr;
//============
 
//=========
assign cam_soid = (sda_oe == 1'b1) ? sda : 1'bz;
assign sda_in 	= cam_soid;
assign cam_soic = scl;
assign cam_pwdn = 1'b0;
assign cam_rst 	= rst_n;


wire vga_den;
wire vga_pwm;	//backlight,set to high
  //===========================
  reg   [15:0]vga_rdaddr_C1; //用case(?)选择vga_rdaddr、vga_rdaddr_C1、~P1、~C2、~P2	
  reg   [15:0]vga_rdaddr_P1; //用case(?)选择vga_rdaddr、vga_rdaddr_C1、~P1、~C2、~P2	
  reg   [15:0]vga_rdaddr_C2; //用case(?)选择vga_rdaddr、vga_rdaddr_C1、~P1、~C2、~P2	
  reg   [15:0]vga_rdaddr_P2; //用case(?)选择vga_rdaddr、vga_rdaddr_C1、~P1、~C2、~P2	
  reg   [15:0]vga_rdaddr_end;
 //=================================下面是自己额外加的，改的时候删了
  wire ready_C1 , start_C1 , ram_wen_C1 ;
  wire [15:0]data_in1_C1,data_out1_C1,  ram_waddr_C1,ram_raddr_C1;     
  wire [15:0]data_out_C1;
  wire  [15:0]addr_CV_C1;     //当clk_div=0时其值为ram_raddr_C1，反之为vga_rdaddr_C1
  //============
    wire ready_P1 , start_P1 , ram_wen_P1  ;
    wire [15:0]data_out1_P1;     
    wire [15:0]data_out_P1;
    wire  [15:0]addr_CV_P1,ram_raddr_P1 ; 
    wire [10:0]ram_waddr_P1;
   assign addr_CV_C1=(   SE_RAM_fft1 ==3'b001 && ram_raddr_P1 == 0  )?vga_rdaddr_C1:ram_raddr_P1;
   //=====================================
    wire ready_C2 , start_C2 , ram_wen_C2  ;
    wire [15:0]data_out1_C2;     
    wire [15:0]data_out_C2;
    wire  [15:0]addr_CV_C2,ram_raddr_C2 ; 
    wire [10:0]ram_waddr_C2;
   assign addr_CV_P1 =(   SE_RAM_fft1 ==3'b010  && ram_raddr_C2 == 0    )?vga_rdaddr_P1:ram_raddr_C2;
   //=========================
    wire ready_P2 , start_P2 , ram_wen_P2  ;
    wire [15:0]data_out1_P2;     
    wire [15:0]data_out_P2;
    wire  [15:0]addr_CV_P2,ram_raddr_P2 ; 
    wire [10:0]ram_waddr_P2;
   assign addr_CV_C2 =(   SE_RAM_fft1 ==3'b011     )?vga_rdaddr_C2:ram_raddr_P2;
  //wire [15:0]vga_rdaddr_C1;
 //cnn_layers=======================================
 wire reset_n_conv1 , reset_n_conv2  , reset_n_full;
wire Y_ren ,ren_Y748,layer_ren, layer_ren_conv2_layer   ;
wire [7:0]pre_dob;
wire [8:0]pre_addrb;
wire [9:0]pre_ram_raddr;
wire [11:0]data_in1_conv2_layer;
wire [10:0]ram_raddr_conv2_layer;
wire Y_ren_conv2_layer;   
wire [11:0] in_full_layer;
wire [3:0]out_full_layer ;
wire [6:0]raddr_full_layer ;
wire Y_ren_full_layer;
//==============endlayer
 wire [7:0] data_out_pre   ;  
 wire [7:0] data_out_end   ;
 //============================
//vga rgb565 mode

assign vga_r [7:0] 	=  img_ack_ALL ? { vga_data[15:11] ,   vga_data[13:11] } : 8'h0;
assign vga_g[7:0] 	=  img_ack_ALL ? { vga_data[10:5]   ,   vga_data[6:5] }  : 8'h0;
assign vga_b[7:0] 	=  img_ack_ALL ? { vga_data[4:0]     ,   vga_data[2:0]}   : 8'h0;

//=================
ip_pll u_pll(       //时钟
	.refclk(clk_24m),		//24M
	.clk0_out(clk_lcd),		//25M,VGA clk
	.clk1_out(clk_cam),		//12m,for cam xclk//14换成6M
	.clk2_out(clk_sccb)		//4m,for sccb init
);

camera_init u_camera_init
(
	.clk(clk_sccb),
	.reset_n(rst_n),
	.ready(init_ready),
	.sda_oe(sda_oe),
	.sda(sda),
	.sda_in(sda_in),
	.scl(scl)
);
	
lcd_sync        //vga输出
#(
	.IMG_W		(80		),
	.IMG_H		(100		),
	.IMG_X		(100		),
	.IMG_Y		(10  	)
)
u_vga_sync
(
	.clk		(clk_lcd	),
	.rest_n		(rst_n		),
	.lcd_clk	(vga_clk	),
	.lcd_pwm	(vga_pwm	),
	.lcd_hsync	(vga_hsync	), 
	.lcd_vsync	(vga_vsync	), 
	.lcd_de		(vga_den	),
	.hsync_cnt	(hsync_cnt	),
	.vsync_cnt	(vsync_cnt	),
	.img_ack	(vga_rden	),
	.addr		(vga_addr	),
    .clk_div  (clk_div ),         //自己加的时钟分频
    .SE_RAM(SE_RAM),    //自己加的ram选择信号
    .img_ack_ALL (img_ack_ALL)////控制TOP层的 vga_r、g、b
);

camera_reader u_camera_reader
(
	.clk		(clk_cam		),
	.reset_n	(rst_n			),
	.csi_xclk	(cam_xclk		),
	.csi_pclk	(cam_pclk		),
	.csi_data	(cam_data		),
	.csi_vsync	(!cam_vsync		),
	.csi_hsync	(cam_href		),
	.data_out	(camera_wrdat	),
	.wrreq		(camera_wrreq	),
	.wrclk		(camera_wclk	),
	.wraddr		(camera_addr	)
);

img_cache u_img       //写入CAMERA数据，读出原始图像
( 
	//write 45000*8
	.dia		(camera_wrdat	), 
	.addra		(camera_addr[15:0]	), 
	.cea		(camera_wrreq	), 
	.clka		(camera_wclk	), 
	//.rsta		(!rst_n			), 
	//read 22500*16
	.dob	      (vga_rddat		), 
	.addrb		(vga_rdaddr		), 
	.ceb	    	(vga_rden		),
	.clkb		(clk_lcd		)
	//.rstb		(!rst_n			)
);





 
//=======================
//SE_RAM信号控制地址赋值,同时也控制vga_rddat
 always @(posedge clk_lcd) begin
  		 SE_RAM_fft1 <= SE_RAM;
  end
 
always@( * )begin  //SE_RAM_fft1
if(SE_RAM_fft1 == 3'b000 )begin
   vga_data              =      vga_rddat ; //vga_rddat ;16'b1111_1111_1111_1111 Y
   vga_rdaddr          =      vga_addr ; 
   vga_rdaddr_C1  =0 ;
   vga_rdaddr_P1  =0 ;
   vga_rdaddr_C2  =0 ;
   vga_rdaddr_P2  =0 ;
   vga_rdaddr_end =0 ;
end   
else if( SE_RAM_fft1 ==3'b001 )begin
    vga_data             =         data_out_C1;    //  data_out_C1 ; 16'b0000_0111_1110_0000 C1
    vga_rdaddr         =0 ; 
    vga_rdaddr_C1  = vga_addr ;
    vga_rdaddr_P1  =0 ;
    vga_rdaddr_C2  =0 ;
    vga_rdaddr_P2  =0 ;
    vga_rdaddr_end =0 ;
end
else if(SE_RAM_fft1 == 3'b010 )begin
   vga_data              =     data_out_P1  ; // 16'b1111_1111_1111_1111 P1
   vga_rdaddr          =    0 ; 
   vga_rdaddr_C1  =    0  ;
   vga_rdaddr_P1  =    vga_addr    ;
   vga_rdaddr_C2  =0 ;
   vga_rdaddr_P2  =0 ;
   vga_rdaddr_end =0 ;
end   
else if(SE_RAM_fft1 ==3'b011)begin
    vga_data             =     data_out_C2       ;    //   16'b0000_0111_1110_0000C C2
    vga_rdaddr         =0 ; 
    vga_rdaddr_C1  = 0 ;
    vga_rdaddr_P1  =0 ;
    vga_rdaddr_C2  =  vga_addr    ;
    vga_rdaddr_P2  =0 ;
    vga_rdaddr_end =0 ;
end
else if(SE_RAM_fft1 ==3'b100)begin
    vga_data             =         { data_out_pre[7:3] , data_out_pre[7:2] , data_out_pre[7:3]  };    //   16'b0000_0111_1110_0000 P2  data_out_P2 
    vga_rdaddr         =0 ; 
    vga_rdaddr_C1  = 0 ;
    vga_rdaddr_P1  =0 ;
    vga_rdaddr_C2  =0 ;
    vga_rdaddr_P2  =   vga_addr    ;
    vga_rdaddr_end =0 ;
end 
else if(SE_RAM_fft1 ==3'b101)begin
    vga_data             =      { data_out_end[7:3] , data_out_end[7:2] , data_out_end[7:3]  } ;    //   16'b0000_0111_1110_0000 P2  data_out_P2 
    vga_rdaddr         =0 ; 
    vga_rdaddr_C1  = 0 ;
    vga_rdaddr_P1  =0 ;
    vga_rdaddr_C2  =0 ;
    vga_rdaddr_P2  =  0;
    vga_rdaddr_end = vga_addr  ;
end 
else begin
    vga_data              =         16'b0000_0000_0000_0000;    //  data_out_C1 ; 
    vga_rdaddr          = 0 ; 
    vga_rdaddr_C1  = 0 ;
    vga_rdaddr_P1  = 0 ;
    vga_rdaddr_C2  = 0 ;
    vga_rdaddr_P2  = 0 ;
    vga_rdaddr_end =0 ;
end
end  //*/
 
 //===========================
 
 
 //第一级Y原图到C1第一次CNN滤波
                                                           
CNN_RAM1 CNN_RAM_Y(             //写部分不变，读的接一个读控制模块。写入原数据，读出的数据进行第一级CNN滤波
	
      .dia         	(vga_rddat	), 
	.addra		(vga_rdaddr), 
      .cea	      (vga_rden	 ),  //&& clk_div 
    
      .dob          ( data_in1_C1 ),
	.addrb		(ram_raddr_C1 ),  //ram_raddr_C1
	.ceb		(1'b1	),        //vga_rden?接lcdsync:接CNN

	.clka		( clk_lcd	), 
	.clkb		( clk_lcd)
	);

	
    CNN_READ  CNN_READ_C1(
.clk_b( clk_lcd ),
.rstb_n( rst_n ),
.clk_div( clk_div ), ///negedge clk_div时开始读

.CNN_ready(ready_C1),
.CNN_start(start_C1),

.ram_raddr(ram_raddr_C1), 
.ram_waddr(ram_waddr_C1),
.ram_wen(ram_wen_C1)
	);
    

CNN3 CNN3_C1( 
	.clk_in ( clk_lcd ) ,
	.rst_n  ( rst_n ) , 
	.data_in(data_in1_C1 ),	  
	.start     (start_C1 )	,
	.data_out(data_out1_C1 ),
	.ready      (ready_C1 )
 );

CNN_RAM1 CNN_RAM_C1(   //C1图像 
      .dia		    (data_out1_C1  ), 
	.addra		    (ram_waddr_C1 ), 
      .cea		    (ram_wen_C1  ), //ram_wen_C1 
    
    . dob           (data_out_C1),
	.addrb		   (  addr_CV_C1   ),                      //   vga_rdaddr_C1   ),//  //    addr_CV_C1   ),  
	.ceb		(1'b1),       
    
	.clka		( clk_lcd ), 
	.clkb		( clk_lcd )
	
);
//===================================
 //*/   
   //C1第一次CNN滤波到P1第一次池化  
  
POOL_READ_P1  POOL_READ_P1_1(
.clk_b( clk_lcd  ),
.rstb_n(  rst_n    ),
.clk_div(   ram_wen_C1  ),     ///negedge clk_div  时开始读  ram_wen_C1

.POOL_ready(  ready_P1 ),
.POOL_start(  start_P1 ),

.ram_raddr(   ram_raddr_P1    ), 
.ram_waddr(  ram_waddr_P1  ),
.ram_wen(   ram_wen_P1 ) 
	);
    

POOL3 P1( 
	.clk( clk_lcd  ) ,
	.rst(  rst_n  ) , 
	.data_in( data_out_C1   ),	  
	.start(start_P1 )	,
	.data_out(    data_out1_P1 ),
	.ready(ready_P1 )
 );
   
RAM_02     RAM_02_P1(
        .dia		        (   data_out1_P1  ), 
    	.addra		    (  ram_waddr_P1 ), 
        .cea		        (   ram_wen_P1    ), //      ram_wen_P1 
    
    . dob             ( data_out_P1    ),
	.addrb		      (  addr_CV_P1 ),      ///addr_CV_P1
	.ceb		          ( 1'b1 ),       
    
	.clka		( clk_lcd ), 
	.clkb		( clk_lcd )
	
);
 //===================================
 //*/   
   //P1第一次池化到C2第二次CNN滤波
    
  CNN_READ_C2     CNN_READ_C2_1(
.clk_b( clk_lcd  ),
.rstb_n(  rst_n    ),
.clk_div(    ram_wen_P1    ),     ///negedge clk_div时开始读  ram_wen_C1

.CNN_ready(  ready_C2    ),
.CNN_start(  start_C2  ),

.ram_raddr(   ram_raddr_C2     ), 
.ram_waddr(  ram_waddr_C2   ),
.ram_wen(   ram_wen_C2  ) 
	);
    

CNN3 C1( 
	.clk_in( clk_lcd  ) ,
	.rst_n(  rst_n  ) , 
	.data_in(  data_out_P1   ),	  
	.start(start_C2  )	,
	.data_out(    data_out1_C2  ),
	.ready(ready_C2  )
 );
   
RAM_02     RAM_02_C2(
        .dia		        (   data_out1_C2   ), 
    	.addra		    (  ram_waddr_C2  ), 
        .cea		        (   ram_wen_C2     ), //      ram_wen_P1 
    
    . dob             ( data_out_C2     ),
	.addrb		      (  addr_CV_C2   ),  
	.ceb		          ( 1'b1 ),       
    
	.clka		( clk_lcd ), 
	.clkb		( clk_lcd )
	
);  
    
//===================================
 //*/   
   //C2第二次CNN滤波到P2第二次池化      

//===============================
  
POOL_READ_P2  POOL_READ_P2_1(
.clk_b( clk_lcd  ),
.rstb_n(  rst_n    ),
.clk_div(   ram_wen_C2  ),     ///negedge clk_div  时开始读  ram_wen_C1

.POOL_ready(  ready_P2 ),
.POOL_start(  start_P2 ),

.ram_raddr(   ram_raddr_P2    ), 
.ram_waddr(  ram_waddr_P2  ),
.ram_wen(   ram_wen_P2 ) 
	);
    

POOL3   P2( 
	.clk( clk_lcd  ) ,
	.rst(  rst_n  ) , 
	.data_in( data_out_C2   ),	  
	.start(start_P2 )	,
	.data_out(    data_out1_P2 ),
	.ready(ready_P2 )
 );
   //==========

   //=======
RAM03_512     RAM_02_P2(
        .dia		        (   data_out1_P2  ), 
    	.addra		    (  ram_waddr_P2 ), 
        .cea		        (   ram_wen_P2    ), //      ram_wen_P1 
    
    . dob             ( data_out_P2    ),            //
	.addrb		      (  pre_addrb ),      /// vga_rdaddr_P2
	.ceb		          ( 1'b1 ),       
    
	.clka		( clk_lcd ), 
	.clkb		( clk_lcd )
	
);   
//=================cnn_layers==

 PRE_LAYER  U_PRE_LAYER(
.clk(  clk_lcd  ),
.rst_n( rst_n ),
.data_in( data_out_P2 ),
.addrb(  pre_ram_raddr ),                           //读RAM_Y_748的地址
.ren_P2( ram_wen_P2),                       //表示P2可以被读取，ram_wen_P2 下降沿启动
.ceb(Y_ren ),
.dob( pre_dob ),
.addr_P2(  pre_addrb ),  //读P2的地址
.ren_Y748( ren_Y748 ),       //表示数据写入完毕，可以被读取 

.addrb_vga( vga_rdaddr_P2 ),  
.dob_vga( data_out_pre )
 ); 
 
 conv1_layer1 u_conv1_layer( 
.clk(  clk_lcd  ),
.rst_n( rst_n || reset_n_conv1  ),
.ren_Y748( ren_Y748 )   ,  //开始信号，下降沿开始
.data_in( pre_dob ),
.raddr( pre_ram_raddr ) ,    //读原图的地址 
.Y_ren( Y_ren ),              //原图读使能
.layer_ren( layer_ren ),
 
.ram_addrb( ram_raddr_conv2_layer ),
.ram_dob( data_in1_conv2_layer  ),      
.ram_ceb( Y_ren_conv2_layer ),
.reset_n( reset_n_conv1 )
);
    
conv2_layer2 u_conv2_layer( 
.clk( clk_lcd ),
.rst_n(  rst_n || reset_n_conv2  ),
.ren_Y748( layer_ren )   ,  //开始信号，下降沿开始
.data_in( data_in1_conv2_layer ),
.raddr( ram_raddr_conv2_layer ) ,    //读原图的地址 
.Y_ren( Y_ren_conv2_layer ),              //原图读使能
.layer_ren(  layer_ren_conv2_layer  ),

.ram_addrb( raddr_full_layer ),
.ram_dob( in_full_layer  ),      
.ram_ceb( Y_ren_full_layer ),

.reset_n( reset_n_conv2 )
);

 full_layer  u_full_layer( 
.clk( clk_lcd ),
.rst_n(  rst_n  || reset_n_full ),
.layer_ren( layer_ren_conv2_layer ) ,   //收到此信号下降沿开始读
.data_in( in_full_layer ),
.data_out( out_full_layer  ),              //输出0-9

.raddr( raddr_full_layer ),
.read_flag( Y_ren_full_layer ),

.reset_n( reset_n_full)
);
//==========输出层
output_layer  u_output_layer( 
.clk( clk_lcd ),
.rst_n(  rst_n ),
.nub( out_full_layer  ),
.raddr( vga_rdaddr_end ),  
.TX(data_out_end )
);

/* 
 //==================输出8字晶体管显示  
always@(  posedge clk_lcd or negedge rst_n   )begin
    if(  rst_n == 0 )begin
        slect_a <= 0 ;
        a_data_out <= 0 ;
    end
    else begin
        slect_a <= 4'b1110 ;
        case( out_full_layer )    //out_full_layer
            0:a_data_out <= 8'b11000000  ;
            1:a_data_out <= 8'b11111001 ;
            2:a_data_out <= 8'b10100100 ;
            3:a_data_out <= 8'b10110000 ;
            4:a_data_out <=  8'b10011001 ;
            5:a_data_out <= 8'b10010010 ;
            6:a_data_out <= 8'b10000010 ;
            7:a_data_out <= 8'b11111000 ;
            8:a_data_out <= 8'b10000000 ;
            9:a_data_out <= 8'b10010000 ;
            default:a_data_out <= 8'b11000110 ;
        endcase
    end
end     //*/

/*
0               abcdef                  8'b11000000    0xC0
1               bc                          8'b11111001    0xf9
2               abdeg                   8'b10100100    0xA4
3               abcdgh                 8'b10110000    0xb0
4               bcfg                       8'b10011001    0x99
5               acdfg                    8'b10010010    0x92
6               acdefg                  8'b10000010    0x82
7               abc                        8'b11111000    0xf8
8               abcdefg                8'b10000000    0x80    
9               abcdfg                  8'b10010000    0x90
A               abcefg                  10001000    0x88
b               cdefg                   10000011    0x83
C               adef                    11000110    0xc6
d               bcdeg                   10100001    0xA1
E               adefg                   10000110    0x86
F               aefg                    10001110    0x8e
*/
    
    
endmodule
