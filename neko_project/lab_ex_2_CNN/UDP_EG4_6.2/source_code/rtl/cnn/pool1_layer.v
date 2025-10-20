`timescale 1ns/ 1ps
//========================
/*
读数0-1727然后最大池化，逻辑同之前写的POOL_READ一样，只调整了参数，模板固定为2*2MAX
*/
//=========================
module pool1_layer#(
parameter DATA_BIT = 12, 
                   RADDR_BIT = 11 ,
                   WADDR_BIT = 9 ,
                   HALF_WIDTH = 12,   //原图长宽减半
                   HALF_HEIGHT = 12
)(
    input clk,               
    input rst_n,                    
    input clk_div,            
    output reg[ RADDR_BIT -1 :0]ram_raddr,     
    output reg[ WADDR_BIT -1 :0]ram_waddr,       
    output reg ram_wen,         

    input          POOL_ready,                
    output reg POOL_start            
    );
    
    //第二版，把ram_ren的关系改变,
    reg ram_ren=0;          //READ模块的启动信号，1时读
    reg ram_ren_fft1=0;  //ram_ren打一拍，为1时，在下一个周期拉高POOL_start
    reg [RADDR_BIT -1:0]cnt_ready;  //计数器，从49*39-1=HALF_WIDTH * HALF_HEIGHT - 1，每一个ready的posedge信号+1 //
    reg  clk_div_fft1;        //clk_div打一拍
 //======================这里使用的是2*2的===========
    //cnt_l和cnt_h用于计算每9个数据的起始地址
    reg [7:0]cnt_l; //数列数的，宽是2*HALF_WIDTH，由于是2*2的矩阵，应该从0加2到2*HALF_WIDTH-2
    reg [7:0]cnt_h;//数行数的，高是78，由于是2*2的矩阵，应该从0加2到76
    //起始地址为0+cnt_l+cnt_h
    reg [1:0]cnt;//从0数到3表示一轮
    wire cnt_n;//由cnt获得
    //===================
    assign cnt_n= cnt[1] ;
    //==============ram_ren控制部分
    always@(posedge  POOL_ready or negedge rst_n)begin
      if(rst_n == 1'b0)begin //复位
             cnt_ready<=0; 
      end
      else begin
            if( cnt_ready !=  HALF_WIDTH * HALF_HEIGHT - 1 && ram_raddr != 0)              //49*39-1=HALF_WIDTH * HALF_HEIGHT - 1
                cnt_ready <=  cnt_ready + 1'b1 ;
            else if( cnt_ready == HALF_WIDTH * HALF_HEIGHT - 1 )   //49*39-1=HALF_WIDTH * HALF_HEIGHT - 1
                cnt_ready <= 0 ;
      end
    end
   always@( posedge clk or negedge rst_n )begin
      if(rst_n == 1'b0)begin //复位
            ram_ren <= 0 ;  
            ram_ren_fft1<=0;
             clk_div_fft1<=0; 
      end
      else begin
             ram_ren_fft1<=ram_ren;
             clk_div_fft1<=clk_div; 
             if ( clk_div_fft1 != clk_div  && clk_div_fft1==1)
                 ram_ren <= 1 ; 
             else if( ram_raddr ==  4* HALF_WIDTH*HALF_HEIGHT-1 )   ////2*HALF_WIDTH*78-1=7643
                 ram_ren <= 0 ; 
      end
   end
    //================================================
    always@( posedge clk or negedge rst_n )begin  //读部分
     if(rst_n == 1'b0  || ram_ren == 1'b0 )begin //复位
         cnt_l<=0;  
         cnt_h<=0;
         cnt<=0; 
         ram_raddr<=0;
     end
     else begin
       if(ram_ren==1'd1)begin
        ram_raddr <= cnt_l+cnt_h*2*HALF_WIDTH+cnt+cnt_n*(2*HALF_WIDTH-2)    ;//计算地址     //  2*HALF_WIDTH*78-1=7643 
    //地址相关计数器跳转 
          begin
             if(cnt>= 0 && cnt<=2) 
                  cnt <= cnt+1; 
             else if(cnt == 3)
                  cnt <= 0;
          end
          if(cnt == 3)begin
             if(cnt_l >= 0 && cnt_l <= (2*HALF_WIDTH-4))        // 2*HALF_WIDTH*78-1=7643 
                  cnt_l <= cnt_l + 2 ; 
             else if( cnt_l == (2*HALF_WIDTH-2) )                      // 2*HALF_WIDTH*78-1=7643
                  cnt_l <= 0;
          end
          if(  cnt==3 && cnt_l == (2*HALF_WIDTH-2))begin         // 2*HALF_WIDTH*78-1=7643 
             if(cnt_h >= 0 && cnt_h <= (2*HALF_HEIGHT-4))     //12*HALF_WIDTH*162-1=32075,7D4B//2*HALF_WIDTH*78-1=(2*HALF_HALF_HEIGHT-2)43 
                  cnt_h <= cnt_h + 2  ;
             else if( cnt_h == (2*HALF_HEIGHT-2)  )                   //12*HALF_WIDTH*162-1=32075,7D4B //2*HALF_WIDTH*78-1=(2*HALF_HALF_HEIGHT-2)43  
                  cnt_h <= 0;
          end
       end
     end      
    end
   //=============================        
    always@( posedge clk or negedge rst_n )begin//写入数据 ram_waddr和写使能ram_wen
      if(rst_n == 1'b0)begin //复位
             ram_waddr<=0;  
             ram_wen<=0; 
      end
      else begin
            if( POOL_ready  ==  1 &&  ram_waddr  != HALF_WIDTH * HALF_HEIGHT - 2  &&   ram_raddr != 0 )begin         ///49*39-1=HALF_WIDTH * HALF_HEIGHT - 1
               ram_waddr <=cnt_ready - 1'b1 ;
               ram_wen<=1; 
            end
             else if( ram_waddr ==  HALF_WIDTH * HALF_HEIGHT - 2 &&  POOL_ready ==1 )begin         ///49*39-1=HALF_WIDTH * HALF_HEIGHT - 1
               ram_waddr<=HALF_WIDTH * HALF_HEIGHT - 1 ;                                                                    // /49*39-1=HALF_WIDTH * HALF_HEIGHT - 1
               ram_wen<=1; 
            end
            else if( ram_waddr == HALF_WIDTH * HALF_HEIGHT - 1 )begin           //1/49*39-1=HALF_WIDTH * HALF_HEIGHT - 1
               ram_waddr<=0;
               ram_wen<=0; 
            end
      end
    end
   
      //=============================        
    always@( posedge clk or negedge rst_n )begin//POOL_start 卷积核启动信号控制
      if(rst_n == 1'b0)begin //复位
             POOL_start <=0;   
      end
      else begin
            if(   ram_ren_fft1 ==1'b1)
               POOL_start <=1'b1;
            if(  ram_ren_fft1 ==1'b0)
               POOL_start <=1'b0;
      end
    end 
      
endmodule

