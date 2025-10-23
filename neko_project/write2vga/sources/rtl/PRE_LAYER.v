`timescale 1ns/ 1ps
//===============
/*
预处理层
把之前视频最小的图像做预处理
有一下模块：
READ_RAMP2:从P2的RAM里读取图像18*22
RGB2GRTAY：把（16位宽）RGB565格式转成（8位）灰度256图像，顺便搞个阈值把低于128的数据置0，
                            同时负责给RAM_Y_748提供写地址
RAM_Y_784:存放灰度图像作为原图大小为28*28
                                                                    5行0
                        存放方法： 3列0         18行*22列     3列0 
                                                                    5行0
*/
//====================
module PRE_LAYER(
input clk,
input rst_n,
input [15:0]data_in,
input [9:0]addrb,                           //读RAM_Y_748的地址
input ren_P2,                         //表示P2可以被读取，ram_wen_P2 下降沿启动
input ceb,       //Y748的ceb
output [7:0]dob,
output [8:0]addr_P2,  //读P2的地址
output ren_Y748,       //0表示数据写入完毕，可以被读取 .1表示正在写

input [9:0]addrb_vga,  
output [7:0]dob_vga
 );
wire [7:0]gray ;
wire [9:0]addra;
wire start  ;                       //RAM_Y写使能


 READ_RAMP2    U_READ_RAMP2( 
.clk( clk ),
.rst_n( rst_n ),
.ren_P2( ren_P2 ),                         //表示P2可以被读取 ，ram_wen_P2 下降沿启动
.addr_P2(addr_P2),  //读P2的地址
.start( start )             //让RGB2GRAY开始运行 
);


RGB2GRAY  U_RGB2GRAY(
.clk( clk ),
.rst_n( rst_n ),
.data_in( data_in ),   //RGB565
.start( start ),
.data_out( gray ),  //写数据
.waddr( addra ),       //写地址
.wen( ren_Y748 )           //写使能信号
);



RAM04_1024     RAM_Y_784(
        .dia		        (   gray   ), 
    	.addra		    (  addra  ), 
        .cea		        (   ren_Y748    ), //      write_enable
    
    . dob             (   dob    ),
	.addrb		      (  addrb ),      ///
	.ceb		          (  ceb ),       
    
	.clka		( clk ), 
	.clkb		( clk )
	
);   


RAM04_1024     RAM_2vga(                  //2VGA
        .dia		        (   gray   ), 
    	.addra		    (  addra  ), 
        .cea		        (   ren_Y748    ), //      write_enable
    
    . dob             (   dob_vga    ),
	.addrb		      ( addrb_vga  ),      ///
	.ceb		          (  1 ),       
    
	.clka		( clk ), 
	.clkb		( clk )
	
);   






endmodule
