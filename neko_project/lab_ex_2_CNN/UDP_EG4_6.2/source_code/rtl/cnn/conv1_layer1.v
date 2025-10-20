`timescale 1ns/ 1ps
//===============
/*
卷积1层和池化1层，模型变化：28*28*1----5*5*3conv---->24*24*3-----2*2*3maxpool------->12*12*3
conv1：读Y748图像，并把数据放入BUF中. state：IDLE：空闲。当REN_Y748下降沿时进入FULL_BUF
                                                                                          FULL_BUF：1、填满5*28的buf。2、填满时发出 脉冲ready_buf 信号给calc。发出ready_buf进入CALC
                                                                                          CALC: 当前buf在进行5*5CLAC, 生成24*3个数据放入RAM里，写完后更新一行，重复此流程直到结束
*/
//====================
module conv1_layer1(
input clk,   
input  rst_n,
input  ren_Y748,
input  [7:0]data_in,
output [9:0]raddr, 
output Y_ren,
output reg layer_ren,
//======读RAM
input ram_ceb,
input [8:0]ram_addrb,
output signed[11:0]ram_dob,
//=========reset
output reg reset_n
 );
 //============互连线
wire conv1_ren,start,ready,pool1_ram_wen;
wire [10:0]pool1_ram_raddr;
wire [8:0]pool1_ram_waddr;
wire [11:0]pool1_data_in , pool1_data_out;
reg [11:0]pool1_data_out_fft1;
//==========================重复模块寄存器
reg [1:0]cnt_3; //数3 :0,1,2
reg [2:0]cnt_8;//wait 8clk
reg pool1_layer_start, conv1_ren_fft1,pool1_ram_wen_fft1 ,flag_wait ;
//===================
conv1 u_conv1( 
.clk( clk ),
.rst_n( rst_n ),
.ren_Y748( ren_Y748 )   ,  //开始信号，下降沿开始
.data_in( data_in ),
.raddr( raddr  ) ,    //读原图的地址 
.Y_ren( Y_ren ),              //原图读使能
.conv1_ren( conv1_ren ),         //下降沿表示数据更新完成
.ram_addrb( pool1_ram_raddr + cnt_3*576 ),
.ram_dob( pool1_data_in  ),      
.ram_ceb( 1'b1 )
);
//===================layer_ren
always@(  posedge clk or negedge rst_n   )begin
if( rst_n == 1'b0 )
layer_ren <= 1'b1;
else begin
if(  pool1_ram_waddr+144*cnt_3 == 431)
  layer_ren <= 1'b0;
  else 
  layer_ren <= 1'b1;
end
end
//========重复读三次模块，每多一次地址+576，
always@(  posedge clk or negedge rst_n   )begin
    if( rst_n == 1'b0 )begin
        cnt_3 <=2'b00 ;
        pool1_layer_start <= 1'b0 ;
        conv1_ren_fft1 <= 1'b0 ;
        pool1_ram_wen_fft1 <= 1'b0 ;
        cnt_8 <= 3'b000;
        flag_wait <= 1'b0;
    end
    else  begin
       conv1_ren_fft1 <=  conv1_ren ;
       pool1_ram_wen_fft1 <= pool1_ram_wen ;
       if( pool1_ram_wen_fft1 != pool1_ram_wen   &&  pool1_ram_wen_fft1==1 && cnt_3 ==2'b10 )begin
           cnt_3 <= 2'b00 ;
       end
       begin
           if( conv1_ren_fft1 != conv1_ren   &&  conv1_ren_fft1==1  )begin
               pool1_layer_start <= 1'b0 ; 
           end
           else if( pool1_ram_wen_fft1 != pool1_ram_wen   &&  pool1_ram_wen_fft1==1 && cnt_3 !=2'b10 )begin
               flag_wait <= 1'b1;
           end
           else 
               pool1_layer_start <= 1'b1 ; 
       end
       if( flag_wait == 1'b1 )begin
           if(cnt_8 != 7 )
               cnt_8 <= cnt_8 +1 ;
           else begin
               pool1_layer_start <= 1'b0 ; 
               cnt_3 <= cnt_3 + 2'b01 ;
               cnt_8 <= 0 ;
               flag_wait <= 1'b0;
           end
       end
    end
end
//==================
pool1_layer#(
.DATA_BIT (12), 
.RADDR_BIT (11) ,
.WADDR_BIT  (9) ,
.HALF_WIDTH  (12),    
.HALF_HEIGHT(12)
)
  u_pool1_layer(
.clk( clk ),
.rst_n( rst_n ),                  
.clk_div( pool1_layer_start ),            
.ram_raddr( pool1_ram_raddr ),     
.ram_waddr( pool1_ram_waddr),       
.ram_wen( pool1_ram_wen ),         

.POOL_ready( ready ),                
.POOL_start( start )            
    );

pool_core0 
 #(
    . bits(12),
    . filter_size(4),
    . filter_size_2 (2)
)
  POOL_CORE_R(
.clk_in( clk),
.rst_n(   rst_n ), 

.data_in( pool1_data_in  ),	
.start(start),

.data_out( pool1_data_out ),  

.ready( ready )
	);  
 always @(posedge clk )begin
pool1_data_out_fft1    <=  pool1_data_out;
// ready <=ready_fft1;
 end
 ////================RAM,12BIT,12*12*3 ,pool1*3,0-143,144-287,288-431
 RAM12_512   RAM1(   //原始图像 
    .dia		    ( pool1_data_out_fft1	), 
	.addra		( pool1_ram_waddr+144*cnt_3	), 
    .cea		    ( pool1_ram_wen ), 
    
    .dob        ( ram_dob     ),
	.addrb		( ram_addrb ),    //[8:0]
	.ceb		    ( ram_ceb     ),

	.clka		( clk	), 
	.clkb		( clk	)	
);
 
 //reset_n
always@(  posedge clk or negedge rst_n   )begin
    if( rst_n == 1'b0 )begin
        reset_n <= 1 ;
     end
     else if ( layer_ren == 1'b0)
      reset_n <= 0 ;
 end
 
endmodule
