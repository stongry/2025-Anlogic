`timescale 1ns/ 1ps
// --------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>>> COPYRIGHT NOTICE <<<<<<<<<<<<<<<<<<<<<<<<<
// --------------------------------------------------------------------
// 
// AuTHor: Anlogic
// 
// Description:
//
//		dvp_ov2640,摄像头VGA配置
// 
// Web: www.anlogic.com
// --------------------------------------------------------------------
module lcd_sync
#(
 	//display image at pos
	parameter IMG_W = 80,  //图片行像素点个数
	parameter IMG_H =  100,  //图片场像素点个数
	parameter IMG_X =  0,
	parameter IMG_Y =   0
)
(
	input 	wire 		clk,
	input 	wire 		rest_n,
	output 	wire 		lcd_clk,
	output 	wire 		lcd_pwm,
	output 	wire 		lcd_hsync, 
	output 	wire 		lcd_vsync, 
	output 	wire 		lcd_de,
	output 	wire [10:0] hsync_cnt,
	output 	wire [10:0] vsync_cnt,
	output 	wire 		img_ack,
	output 	reg  [15:0]	addr,
    output clk_div,             //自己加的时钟分频,//CLK周期*2048倍，39KHZ
    output  reg    [2:0]SE_RAM, //自己加的ram选择信号
    output 	wire 		img_ack_ALL ////控制TOP层的 vga_r、g、b
	);
    //================时钟分配。配一个慢2048倍的时钟周期clk_div，这个周期上半CLK在做CNN&POOLING,下班在读出数据（》9*4*9*4）
  
 
reg[31:0] divider = 0; 

always@(posedge clk)
begin
	divider <= divider + 1;
end

assign clk_div = divider[20];//17
//====================================
//640*480
localparam VGA_H = 640;  
localparam VGA_V = 480; 

localparam THB 	 = 160;
localparam TH 	 = VGA_H + THB;

localparam TVB   = 45;
localparam TV    = VGA_V + TVB;

reg [10:0] counter_hs;
reg [10:0] counter_vs;

reg [15:0] read_addr;             //读图片数据rom地址   

reg [10:0] img_hbegin = 0;   //图片左上角第一个像素点在VGA的行向坐标
reg [10:0] img_vbegin = 0;   //图片左上角第一个像素点在VGA的场向坐标

always@(posedge clk or negedge rest_n   ) 
begin
	if(rest_n == 1'b0)
		counter_hs <= 0;
	else if(counter_hs == TH )
		counter_hs <= 0;
	else
		counter_hs <= counter_hs + 1;
end 

always@(posedge clk or negedge rest_n   )
begin
	if(rest_n == 1'b0)
		counter_vs <= 0;
	else if(counter_hs == TH && counter_vs == TV)				
		counter_vs <= 0;
	else if(counter_hs == TH && counter_vs != TV)
		counter_vs <= counter_vs + 1;
end  

assign lcd_clk   = (rest_n == 1) ? clk  : 1'b0;
assign lcd_pwm   = (rest_n == 1) ? 1'b1 : 1'b0;
assign lcd_hsync = ( counter_hs >= 16 && counter_hs < 112 ) ? 1 : 0;
assign lcd_vsync = ( counter_vs >= 10 && counter_vs < 12 ) ? 1 : 0;
assign lcd_de    = ( counter_hs >= THB && counter_hs <= TH && counter_vs >= TVB  && counter_vs < TV) ? 1 : 0;
assign hsync_cnt = counter_hs;
assign vsync_cnt = counter_vs;

assign img_ack = lcd_de &&                // clk_div&&                     //增加了clk_div&&
((counter_hs - THB) >= IMG_X && (counter_hs - THB) < (IMG_X + IMG_W)) && 
((counter_vs - TVB) >= IMG_Y && (counter_vs - TVB) < (IMG_Y + IMG_H)) ? 1'b1 : 1'b0;

always@(posedge clk or negedge rest_n)
 begin
	 if(!rest_n)
		 read_addr <= 16'd0;
	 else if(img_ack)
		 read_addr <= (79 - (counter_hs - IMG_X - THB))* IMG_H + (counter_vs - IMG_Y - TVB) ;
	 else
		 read_addr <= 16'd0;  
 end

    //==========================
	//自己添加的图片C1,98*78 ,左上角为（IMG_W，0）
    wire img_ack_C1;
    reg [15:0] read_addr_C1;             //读图片数据ram_C1地址
    
   assign img_ack_C1 = lcd_de &&        // clk_div&&                    
((counter_hs - THB) >= ( IMG_X +  IMG_W )  && (counter_hs - THB) < ( IMG_X +  IMG_W + 78     )) && 
((counter_vs - TVB) >= IMG_Y      && (counter_vs - TVB) < ( IMG_Y  + 98     )) ? 1'b1 : 1'b0;
    
 always@(posedge clk or negedge rest_n)
 begin
	 if(!rest_n)
	    read_addr_C1 <= 16'd0;
	 else if(img_ack_C1)
		read_addr_C1 <=  ( 77 -(counter_hs - IMG_X -  IMG_W - THB)) * 98 + (counter_vs - IMG_Y  - TVB);
	 else
		read_addr_C1 <= 16'd0;  
 end
  //    */
  //==================================
  //自己添加的图片P1,49*39 ,左上角为（IMG_W +78，0）
    wire img_ack_P1;
    reg signed  [15:0] read_addr_P1;             //读图片数据ram_P1地址
    
   assign img_ack_P1 = lcd_de &&        // clk_div&&                    
((counter_hs - THB) >= ( IMG_X +  IMG_W + 78   )  && (counter_hs - THB) < ( IMG_X +  IMG_W + 78  + 39   )) && 
((counter_vs - TVB) >= IMG_Y      && (counter_vs - TVB) < ( IMG_Y  + 49     )) ? 1'b1 : 1'b0;
    
 always@(posedge clk or negedge rest_n)
 begin
	 if(!rest_n)
	    read_addr_P1 <= 16'd0;
	 else if(img_ack_P1   )
		read_addr_P1 <= ( 39 -(counter_hs - IMG_X -  IMG_W - THB - 78 )) * 49 + (counter_vs - IMG_Y  - TVB);      //   (counter_hs - IMG_X  -  IMG_W  -98 - THB) + (counter_vs - IMG_Y  - TVB) * 49 ;
	 else if (img_ack_P1 && read_addr_P1 == 1910  )
		read_addr_P1 <= 16'd0;  
 end
  //    */
   //==================================
  //自己添加的图片C2,47*37 ,左上角为（0，IMG_H ）
    wire img_ack_C2; 
    reg [15:0] read_addr_C2;             //读图片数据ram_C2地址
    
   assign img_ack_C2 = lcd_de &&        // clk_div&&                    
((counter_hs - THB) >= ( IMG_X   )  && (counter_hs - THB) < ( IMG_X   + 37   )) && 
((counter_vs - TVB) >= ( IMG_Y  + IMG_H ) && (counter_vs - TVB) < ( IMG_Y + IMG_H  + 47     )) ? 1'b1 : 1'b0;
 
    
 always@(posedge clk or negedge rest_n)
 begin
	 if(!rest_n)
	    read_addr_C2 <= 16'd0;
	 else if(img_ack_C2 && read_addr_C2  != 1738  )
		read_addr_C2 <=   ( 37 -(counter_hs - IMG_X -  IMG_W - THB )) * 47 + (counter_vs - IMG_Y  - TVB - 47 );         // (counter_hs - IMG_X -  IMG_W - 98 - THB) + (counter_vs - IMG_Y  - TVB) * 47;
	 else if(img_ack_C2 && read_addr_C2  == 1738  )
		read_addr_C2 <= 16'd0;  
 end
  //    */ 
     //==================================
  //自己添加的图片P2,28*28 ,左上角为（IMG_W，IMG_H ）
    wire img_ack_P2;
    reg [15:0] read_addr_P2;             //读图片数据ram_P2地址
    
   assign img_ack_P2 = lcd_de &&        // clk_div&&                    
((counter_hs - THB) >= ( IMG_X   +  IMG_W  )  && (counter_hs - THB) < ( IMG_X   +  IMG_W  + 28  )) && 
((counter_vs - TVB) >= ( IMG_Y  + IMG_H ) && (counter_vs - TVB) < ( IMG_Y + IMG_H  + 28     )) ? 1'b1 : 1'b0;
    
 always@(posedge clk or negedge rest_n)
 begin
	 if(!rest_n)
	    read_addr_P2 <= 16'd0;
	 else if(img_ack_P2 && read_addr_P2  !=  783 )
		read_addr_P2 <=    read_addr_P2 +1'b1;        // (counter_hs - IMG_X -  IMG_W - 98 - THB) + (counter_vs - IMG_Y  - TVB) * 23;
	 else  if(img_ack_P2 && read_addr_P2  ==  783 )
		read_addr_P2 <= 16'd0;  
 end
  //    */ 
//==================================
  //数字识别结果,25*25 ,左上角为（IMG_W+78，IMG_H ）
    wire img_ack_end;
    reg [15:0] read_addr_end;             //读图片数据ram_P2地址
    
   assign img_ack_end = lcd_de &&        // clk_div&&                    
((counter_hs - THB) >= ( IMG_X   +  IMG_W + 78  )  && (counter_hs - THB) < ( IMG_X   +  IMG_W  + 78 + 28  )) && 
((counter_vs - TVB) >= ( IMG_Y  + IMG_H ) && (counter_vs - TVB) < ( IMG_Y + IMG_H  + 28     )) ? 1'b1 : 1'b0;
    
 always@(posedge clk or negedge rest_n)
 begin
	 if(!rest_n)
	    read_addr_end <= 16'd0;
	 else if(img_ack_end && read_addr_end  !=  783 )
		read_addr_end <=    read_addr_end +1'b1;        //  
	 else  if(img_ack_end && read_addr_end  ==  783 )
		read_addr_end <= 16'd0;  
 end
  //    */ 
   //========================== 
  //assign addr = read_addr;//改成组合逻辑,同时控制RAM选择信号SE_RAM
always@( posedge clk or negedge rest_n )begin
if(!rest_n)begin
         addr = 16'd0;
         SE_RAM =3'b111;
 end
 else begin
   if( img_ack )begin
       addr = read_addr;
       SE_RAM =3'b000 ;
       end
  else if(img_ack_C1)begin
       addr = read_addr_C1;
       SE_RAM =3'b001;
       end
  else if(img_ack_P1)begin
       addr = read_addr_P1;
       SE_RAM =3'b010;
       end
  else if(img_ack_C2)begin
       addr = read_addr_C2;
       SE_RAM =3'b011;
       end
  else if(img_ack_P2)begin
       addr = read_addr_P2;
       SE_RAM =3'b100;
       end 
  else if(img_ack_end)begin
       addr = read_addr_end;
       SE_RAM =3'b101;
       end 
   else begin
        addr = 16'd0; 
        SE_RAM =3'b111;
   end
end
end
//======================
  //控制TOP层的 vga_r、g、b
assign  img_ack_ALL=img_ack || img_ack_C1 || img_ack_P1 || img_ack_C2 || img_ack_P2 || img_ack_end ;
  
  
     //    */

  
  
  
  
      
endmodule
