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
//==================================================
根据reg  [39:0]clk_div;   //时钟分频和ren_P2控制开始。
开始产生读地址逻辑为：当clk_div[39]从1到0时:：拉高reg div<=1
                                            当ren_P2从1到0时，且reg div39==1时：把reg start_raddr<=1   ，且reg div<=0     
                                            当cnt=395时：把reg start_raddr<=0
                                            
地址生成逻辑为：当reg start_raddr==1 时：
                                          start <=1
                                           每一个posedge clk计算：addr_P2=cnt_22 +  cnt_18 * 23 ,cnt<=cnt+1,cnt_22<=cnt_22+1
                                               当cnt == 395时：从cnt<=0,cnt_18<=0,cnt_22<=0
                                                  当cnt_22==21时：cnt_22<=0，cnt_18<=cnt_18+1                              
*/
//====================
module READ_RAMP2( 
input clk,
input rst_n,
input ren_P2,                         //表示P2可以被读取 ，ram_wen_P2 下降沿启动
output reg[8:0]addr_P2,  //读P2的地址
output reg start             //让RGB2GRAY开始运行 
);
//=============ren寄存器，取样时间控制
reg  ren_P2_fft1;        //ren_P2打一拍
reg  [39:0]clk_div;      //时钟分频
reg  clk_div39 , clk_div39_fft1 ;  //clk_div[39]
reg  div;     //间隔判断寄存器
reg  start_raddr ;        //为1时开始生成addr_P2
//=============地址计算寄存器
reg [8:0]cnt; //0-395 ,18*22 ，数一共读出了几个地址
reg [5:0]cnt_18 ,  cnt_22;   //0-17 , 0-21
//============产生读地址逻辑
 always@( posedge clk  or negedge rst_n )begin  
     if( rst_n == 1'b0 )begin //复位
          ren_P2_fft1<=0 ;        
          clk_div<=0 ; 
          clk_div39 <=0 ;   
          clk_div39_fft1 <=0 ;    
          div <=0 ;   
          start_raddr<=0 ;          
     end
     else begin
              ren_P2_fft1 <=  ren_P2 ;
              clk_div <= clk_div +1'b1  ;
              clk_div39 <= clk_div[ 27 ] ;       //验证时用10，实际采样用39
              clk_div39_fft1 <= clk_div39  ;
             if( clk_div39_fft1 != clk_div39  && clk_div39_fft1==1 )begin 
                   div <= 1'b1;
             end
             if( ren_P2_fft1 != ren_P2  && ren_P2_fft1==1 && div == 1'b1 )begin 
                   start_raddr<=1'b1 ; 
                   div <= 1'b0;
             end
             if( cnt == 9'd395 )begin
                   start_raddr<=1'b0 ; 
             end
     end
end

//===============================地址生成逻辑：
 always@( posedge clk  or negedge rst_n )begin  
     if( rst_n == 1'b0 )begin //复位
          cnt <= 0 ;        
          cnt_22 <=0 ;
          cnt_18 <=0 ;     
          addr_P2<=0 ;
          start <= 0;          
     end
     else begin
             if( addr_P2 == 9'd412)begin
                 addr_P2<=0 ;
                 start <= 0;   
             end
             if( start_raddr == 1'b1 )begin
                  start <= 1'b1 ; 
                  addr_P2 <= cnt_22 +  cnt_18 * 5'd23;
                  cnt <= cnt+1'b1;
                  cnt_22 <= cnt_22+1'b1 ;
                  if( cnt_22 == 5'd21)begin
                       cnt_22 <= 0 ;
                       cnt_18 <= cnt_18 + 1  ;
                  end
                  if( cnt == 9'd395 )begin
                       cnt_18 <=0 ;
                       cnt <= 0 ;
                  end
             end
     end
end


endmodule
