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
开始逻辑：start_fft1==1时有数据输入，将16位RGB565数据拆成三组的R、G、B寄存器
                                                                      10位宽R[10:0]= { 2'b00 , data_in[15:11] ,   data_in[13:11] ,1'b0 }    ，相当于R*2
                                                                      10位宽G[10:0]= { 3'b000 , data_in[10:5]   ,   data_in[6:5]  }
                                                                      10位宽B[10:0]= {  3'b000 , data_in[4:0]     ,   data_in[2:0]  }       

转换逻辑：start_fft2==1时，寄存器11位GRAY=R+G*5+B  ，后面要右移三位>>3相当于/8

写地址生成逻辑：wen==1时：
                                每一个posedge clk计算：waddr=143+cnt_22 +  cnt_18 * 28,,cnt_22<=cnt_22+1
                                                                             当cnt_22==21时：cnt_22<=0，cnt_18<=cnt_18+1    
                                                                             当wen==0时：cnt_22<=0，cnt_18<=0,waddr=0    
                                                                             

写使能生成逻辑：wen <=start_ff2

*/
//====================
module RGB2GRAY(
input clk,
input rst_n,
input [15:0]data_in,   //RGB565
input start,
output reg[7:0]data_out,  //写数据
output reg[9:0]waddr,       //写地址
output reg wen           //写使能信号
);
//================RGB
reg start_fft1,start_fft2 ,start_fft3 ;
reg [10:0]GRAY,R,G,B;
//=============地址计算寄存器
reg [5:0]cnt_18 ,  cnt_22;   //0-17 , 0-21
//================开始和转换逻辑
 always@( posedge clk  or negedge rst_n )begin  
     if( rst_n == 1'b0 )begin //复位
         start_fft1 <= 1'b0; 
         start_fft2 <= 1'b0; 
         wen  <= 1'b0;
         R <= 10'b00000_00000;
         G <= 10'b00000_00000; 
         B <= 10'b00000_00000; 
         GRAY <= 10'b00000_00000;           
     end
     else begin 
         start_fft1 <= start ;
         start_fft2 <= start_fft1 ;
         start_fft3 <= start_fft2 ;
         wen <= start_fft3 ;
         if( start_fft1 == 1'b1)begin
             R[10:0] <= {  2'b00    ,   data_in[15:11] ,   data_in[13:11] ,1'b0 } ;
             G[10:0] <= {  3'b000 ,   data_in[10:5]   ,   data_in[6:5]  } ;
             B[10:0] <= {  3'b000 ,   data_in[4:0]     ,   data_in[2:0]  } ; 
         end
         if( start_fft2 == 1'b1)begin
             GRAY <= ( R + G*5 + B > 1536 )?(R + G*5 + B): 0 ;                 //GRAY <= R + G*5 + B ;  
         end
     end 
end 
//==========================地址生成逻辑
 always@( posedge clk  or negedge rst_n )begin  
     if( rst_n == 1'b0 )begin //复位 
         data_out <= 8'b0000_0000;
         waddr <= 10'b00000_00000; 
         cnt_18 <= 5'b00000 ;
         cnt_22 <= 5'b00000 ;          
     end
     else begin  
         if( start_fft3 == 1'b1)begin
             data_out  <=  GRAY >>3 ; 
             waddr <= 106 + cnt_22* 28  -  cnt_18  ;
             cnt_22 <= cnt_22+1'b1 ;
             if( cnt_22 == 5'd21)begin
                   cnt_22 <= 0 ;
                   cnt_18 <= cnt_18 + 1  ;
              end
         end
         else begin
             data_out <= 8'b0000_0000;
             waddr <= 10'b00000_00000; 
             cnt_18 <= 5'b00000 ; 
             cnt_22 <= 5'b00000 ; 
         end
     end 
end 

endmodule
