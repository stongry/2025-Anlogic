`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// Create Date: 2022/10/11 10:13:36
// Design Name: 
// Module Name: CNN_READ
// Project Name: 
// Target Devices: 用来从IP_RAM里读数据的，开始读的时候给CNN_L1发送start信号，然后当CNN_L1发出ready信号时把信号输出到下一个IP_RAM里
// Tool Versions: 
// Description: 
//img_cache CNN1_img //IP_RAM接口
//write 45000*8，下一级的写//测试用第一级写入的改成原图的输出算了
//	.dia		(camera_wrdat	),         //核CNN_L1的计算结果data_out给这里  //测试用
//	.addra		(camera_addr[15:0]	),  //写的地址
//	.cea		(camera_wrreq	),      //写请求，等到收到核的ready信号就拉高这个
//	.clka		(camera_wclk	), 
//	.rsta		(!rst_n			), 
///	//read 22500*16当前级的读
//	.dob		(vga_rddat		), //数据，后面直接给卷积核，是a、接data_in
//	.addrb		(vga_rdaddr		), //由READ模块生成的地址
//	.ceb		(vga_rden		),//基于lcd.sync文件参考生成的如果相同可以直接调用，这里第一版也把这个看成READ模块的启动信号，到了直接开读
//	.clkb		(clk_lcd		),                   //读时钟快9倍，因为读的要读9个数据
//	.rstb		(!rst_n			)
/*CNN_L1_221009  test_CNN_L1_221009 //CNN_L1卷积核接口
	 .data_in(data_in),	//[7:0]
     .start(start),                //CHH_READ给
	//deature map output 
	.data_out( data_out ),   //[21:0]
	//enable next module
	.ready(ready)                 //给CNN_READ
*/
// Revision:  10_18最后确定原图像大小为100_80
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module CNN_READ(
//CLK&&RST
    input clk_b,                      //和上一级IP_RAM的读接同样的时钟，下一级IP_RAM写也用这个,对应.clkb(clk_lcd), 
    input rstb_n,                     //和整个系统一样，接时钟下降沿。0时复位，对应.rstb(!rst_n)
    
    input clk_div,            //时钟分频,当negedge clk_div时把ram_ren置1
     
// RAM_READ,地址和使能。从上一级RAM读   
    output reg[15:0]ram_raddr,       //取地址	对应addrb(vga_rdaddr), 
  //  input ram_ren,                   //基于lcd.sync文件参考生成的如果相同可以直接调用，这里第一版也把这个看成READ模块的启动信号，到了直接开读
// RAM_WRITE,地址和使能。当收到ready信号时，把卷积核的结果数据写     
    output reg[15:0]ram_waddr,       //	.addra(camera_addr[15:0]), //写的地址//这里也是写地址的计数器，数到198*162-1=32075,7D4B //98*78-1=7643
    output reg ram_wen,              //	.cea(camera_wrreq), //写请求，等到收到核的ready信号就拉高这个
//CNN_CORE卷积核的
    input  CNN_ready,                //收到CORE的ready的posedge信号后，控制cnt_ready+1当加到198*162-1=32075时把ram_ren置0，//7643
    output reg CNN_start                 //待或仿真跑一下时序,来确定什么时候开始给CNN_L1写数据
    );
    
    //第二版，把ram_ren的关系改变,
    reg ram_ren=0;          //READ模块的启动信号，1时读
    reg ram_ren_fft1=0;  //ram_ren打一拍，为1时，在下一个周期拉高CNN_start
    reg [14:0]cnt_ready;  //计数器，从0-32075，每一个ready的posedge信号+1 //
    reg  clk_div_fft1;        //clk_div打一拍
 //======================这里使用的是3*3的===========
    //cnt_l和cnt_h用于计算每9个数据的起始地址
    reg [7:0]cnt_l; //数列数的，宽是200，由于是3*3的矩阵，应该从0加到197；97
    reg [7:0]cnt_h;//数行数的，高是164，由于是3*3的矩阵，应该从0加到161；81
    //起始地址为0+cnt_l+cnt_h
    reg [3:0]cnt;//从0数到8表示一轮
    wire [1:0]cnt_n;//由cnt获得
    //===================
    
    
    //就一轮而言当前的地址为，起始地址+cnt+cnt_n*197
   // /用逻辑给出cnt_n 
    /*always@(*)begin
    if(rstb_n == 1'b0)  //复位 
             cnt_n=0;
    else begin
    case (cnt)
    0:cnt_n<=0;
    1:cnt_n<=0;
    2:cnt_n<=0;
    3:cnt_n<=1;
    4:cnt_n<=1;
    5:cnt_n<=1;
    6:cnt_n<=2;
    7:cnt_n<=2;
    8:cnt_n<=2;
    default:cnt_n<=0;
    endcase
    end
    end*/
    assign cnt_n[0]=(cnt[2:0]==3'b011 || cnt[2:0]==3'b100 || cnt[2:0]==3'b101 )?1'b1:1'b0;
    assign cnt_n[1]=(cnt[2:0]==3'b110 || cnt[2:0]==3'b111 || cnt[3]==1'b1 )?1'b1:1'b0;
    
    //==============ram_ren控制部分
    always@(posedge  CNN_ready or negedge rstb_n)begin
      if(rstb_n == 1'b0)begin //复位
             cnt_ready<=0; 
      end
      else begin
            if( cnt_ready !=  7643)              //198*162-1=32075,7D4B //98*78-1=7643
                cnt_ready <=  cnt_ready + 1'b1 ;
            else if( cnt_ready == 7643 )   //198*162-1=32075,7D4B 98*78-1=7643
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
             else if( ram_raddr ==  7999 )   //198*162-1=32075,7D4B 98*78-1=7643,100*80-1=7999
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
        ram_raddr <= cnt_l+cnt_h*100+cnt+cnt_n*97;//计算地址     //198*162-1=32075,7D4B 98*78-1=7643 
    //地址相关计数器跳转
    //这一部分是伪码
    /* for(cnt_h=0;cnt_h<198;cnt_h=cnt_h+1)begin
                    for(cnt_l=0;cnt_l<162;cnt_l=cnt_l+1)begin
                      for(cnt=0;cnt<9;cnt=cnt+1)begin
                             read_addr <=cnt_l+cnt_h+cnt+cnt_n*197;
                          end
              end
         end  */
          begin
             if(cnt>= 0 && cnt<=7) 
                  cnt <= cnt+1; 
             else if(cnt == 8)
                  cnt <= 0;
          end
          if(cnt == 8)begin
             if(cnt_l >= 0 && cnt_l <= 96)    //198*162-1=32075,7D4B98*78-1=7643 
                  cnt_l <= cnt_l + 1 ; 
             else if( cnt_l == 97 )                      //198*162-1=32075,7D4B 98*78-1=7643
                  cnt_l <= 0;
          end
          if(cnt==8 && cnt_l == 97)begin         //198*162-1=32075,7D4B//98*78-1=7643 
             if(cnt_h >= 0 && cnt_h <= 76)     //198*162-1=32075,7D4B//98*78-1=7643 
                  cnt_h <= cnt_h + 1 ;
             else if( cnt_h == 77 )                   //198*162-1=32075,7D4B //98*78-1=7643  
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
            if( CNN_ready == 1 && ram_waddr != 7642)begin         //198*162-1=32075,7D4B //98*78-1=7643  
               ram_waddr <=cnt_ready - 1'b1 ;
               ram_wen<=1; 
            end
             else if( ram_waddr == 7642 &&  CNN_ready ==1 )begin         //198*162-1=32075,7D4B //98*78-1=7643  
               ram_waddr<=7643;                            //198*162-1=32075,7D4B //98*78-1=7643 
               ram_wen<=1; 
            end
            else if( ram_waddr == 7643 )begin           //198*162-1=32075,7D4B //98*78-1=7643
               ram_waddr<=0;
               ram_wen<=0; 
            end
      end
    end
   
      //=============================        
    always@( posedge clk_b or negedge rstb_n )begin//CNN_start 卷积核启动信号控制
      if(rstb_n == 1'b0)begin //复位
             CNN_start <=0;   
      end
      else begin
            if(   ram_ren_fft1 ==1'b1)
               CNN_start <=1'b1;
            if(  ram_ren_fft1 ==1'b0)
               CNN_start <=1'b0;
      end
    end 
      
    
    
endmodule
