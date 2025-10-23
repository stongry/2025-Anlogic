`timescale 1ns / 1ps
module POOL_READ_P1( 
//CLK&&RST
    input clk_b,                      //和上一级IP_RAM的读接同样的时钟，下一级IP_RAM写也用这个,对应.clkb(clk_lcd), 
    input rstb_n,                     //和整个系统一样，接时钟下降沿。0时复位，对应.rstb(!rst_n)
    input clk_div,            //时钟分频,当negedge clk_div时把ram_ren置1
     
// RAM_READ,地址和使能。从上一级RAM读   
    output reg[15:0]ram_raddr,       //取地址	对应addrb(vga_rdaddr), //98*78-1=7643
  //  input ram_ren,                   //基于lcd.sync文件参考生成的如果相同可以直接调用，这里第一版也把这个看成READ模块的启动信号，到了直接开读
// RAM_WRITE,地址和使能。当收到ready信号时，把卷积核的结果数据写     
    output reg[10:0]ram_waddr,       //	.addra(camera_addr[15:0]), //写的地址//这里也是写地址的计数器，数到49*39-1=1910
    output reg ram_wen,              //	.cea(camera_wrreq), //写请求，等到收到核的ready信号就拉高这个
// 卷积核的
    input          POOL_ready,                //收到CORE的ready的posedge信号后，控制cnt_ready+1当数到49*39-1=1910时把ram_ren置0， 
    output reg POOL_start               //待或仿真跑一下时序,来确定什么时候开始给CNN_L1写数据
  
    );
    
    //第二版，把ram_ren的关系改变,
    reg ram_ren=0;          //READ模块的启动信号，1时读
    reg ram_ren_fft1=0;  //ram_ren打一拍，为1时，在下一个周期拉高POOL_start
    reg [11:0]cnt_ready;  //计数器，从49*39-1=1910，每一个ready的posedge信号+1 //
    reg  clk_div_fft1;        //clk_div打一拍
 //======================这里使用的是2*2的===========
    //cnt_l和cnt_h用于计算每9个数据的起始地址
    reg [7:0]cnt_l; //数列数的，宽是98，由于是2*2的矩阵，应该从0加2到96
    reg [7:0]cnt_h;//数行数的，高是78，由于是2*2的矩阵，应该从0加2到76
    //起始地址为0+cnt_l+cnt_h
    reg [1:0]cnt;//从0数到3表示一轮
    wire cnt_n;//由cnt获得
    //===================
    assign cnt_n= cnt[1] ;
     
    
    
    //==============ram_ren控制部分
    always@(posedge  POOL_ready or negedge rstb_n)begin
      if(rstb_n == 1'b0)begin //复位
             cnt_ready<=0; 
      end
      else begin
            if( cnt_ready !=  1910 && ram_raddr != 0)              //49*39-1=1910
                cnt_ready <=  cnt_ready + 1'b1 ;
            else if( cnt_ready == 1910 )   //49*39-1=1910
                cnt_ready <= 0 ;
      end
    end
   always@( posedge clk_b or negedge rstb_n )begin
      if(rstb_n == 1'b0)begin //复位
            ram_ren <= 0 ;  
            ram_ren_fft1<=0;
             clk_div_fft1<=0; 
      end
      else begin
             ram_ren_fft1<=ram_ren;
             clk_div_fft1<=clk_div; 
             if ( clk_div_fft1 != clk_div  && clk_div_fft1==1)
                 ram_ren <= 1 ; 
             else if( ram_raddr ==  7643 )   ////98*78-1=7643
                 ram_ren <= 0 ; 
      end
   end
    //================================================
    always@( posedge clk_b or negedge rstb_n )begin  //读部分
     if(rstb_n == 1'b0  || ram_ren == 1'b0 )begin //复位
         cnt_l<=0;  
         cnt_h<=0;
         cnt<=0; 
         ram_raddr<=0;
     end
     else begin
       if(ram_ren==1'd1)begin
        ram_raddr <= cnt_l+cnt_h*98+cnt+cnt_n*96;//计算地址     //  98*78-1=7643 
    //地址相关计数器跳转 
          begin
             if(cnt>= 0 && cnt<=2) 
                  cnt <= cnt+1; 
             else if(cnt == 3)
                  cnt <= 0;
          end
          if(cnt == 3)begin
             if(cnt_l >= 0 && cnt_l <= 94)        // 98*78-1=7643 
                  cnt_l <= cnt_l + 2 ; 
             else if( cnt_l == 96 )                      // 98*78-1=7643
                  cnt_l <= 0;
          end
          if(  cnt==3 && cnt_l == 96)begin         // 98*78-1=7643 
             if(cnt_h >= 0 && cnt_h <= 74)     //198*162-1=32075,7D4B//98*78-1=7643 
                  cnt_h <= cnt_h + 2  ;
             else if( cnt_h == 76  )                   //198*162-1=32075,7D4B //98*78-1=7643  
                  cnt_h <= 0;
          end
       end
     end      
    end
   //=============================        
    always@( posedge clk_b or negedge rstb_n )begin//写入数据 ram_waddr和写使能ram_wen
      if(rstb_n == 1'b0)begin //复位
             ram_waddr<=0;  
             ram_wen<=0; 
      end
      else begin
            if( POOL_ready == 1 && ram_waddr != 1909  && ram_raddr != 0 )begin         ///49*39-1=1910
               ram_waddr <=cnt_ready - 1'b1 ;
               ram_wen<=1; 
            end
             else if( ram_waddr == 1909 &&  POOL_ready ==1 )begin         ///49*39-1=1910
               ram_waddr<=1910 ;                                                                    // /49*39-1=1910
               ram_wen<=1; 
            end
            else if( ram_waddr == 1910 )begin           //1/49*39-1=1910
               ram_waddr<=0;
               ram_wen<=0; 
            end
      end
    end
   
      //=============================        
    always@( posedge clk_b or negedge rstb_n )begin//POOL_start 卷积核启动信号控制
      if(rstb_n == 1'b0)begin //复位
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
