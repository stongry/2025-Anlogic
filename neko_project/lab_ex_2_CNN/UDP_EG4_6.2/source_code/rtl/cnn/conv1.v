`timescale 1ns/ 1ps
//===============
/*
卷积1层和池化1层，模型变化：28*28*1----5*5*3conv---->24*24*3-----2*2*3maxpool------->12*12*3
conv1：读Y748图像，并把数据放入BUF中. state：IDLE：空闲。当REN_Y748下降沿时进入FULL_BUF
                                                                                          FULL_BUF：1、填满5*28的buf。2、填满时发出 脉冲ready_buf 信号给calc。发出ready_buf进入CALC
                                                                                          CALC: 当前buf在进行5*5CLAC, 生成24*3个数据放入RAM里，写完后更新一行，重复此流程直到结束信号长生返回IDLE
      
            呃呃下面所有的cnt都打成con了，抱歉
BUF工作状态描述：FULL_BUF：raddr= 0-139,从Y中读数据。填满时发出 脉冲ready_buf 信号给calc。发出ready_buf(Y_ren下降沿)进入CALC
                                    CALC: 当收到cnt_f=2（控制当前是第几个模板，0，1，2），开始从最左列开始换数据：buffer[0(+cnt_28)]<=buffer[28] ; buffer[28]<=buffer[56] ; buffer[56]<=buffer[84] ; buffer[56]<=buffer[112] ; buffer[112]<=addr_in ; cnt_28数0-27的寄存器，
                                    cnt_28=27时发出发出ready_buf(Y_ren下降沿)

5*5CLAC工作状态： 当收到ready_buf时，cnt_24=23时, cnt_f= con_f+1（组合逻辑控制当前是第几个模板，0，1，2）  进行5*5乘累加计算，写入RAM12_1024 （命名错了，12位宽，2048个数据）
                                                         RAM地址生成逻辑：0-575 通道0 ， 576-1151通道1，1152-1728通道2 。waddr=cnt_f*576 + 24*cnt_h24 + cnt_l24 ;                                                       

*/
//====================
module conv1( 
input clk,
input rst_n,
input ren_Y748,  //开始信号，下降沿开始
input [7:0]data_in,
input ram_ceb,
input [10:0]ram_addrb,
output reg  [9:0]raddr ,    //读原图的地址 
output reg Y_ren,              //原图读使能
output reg conv1_ren,         //下降沿表示数据更新完成
output signed[11:0]ram_dob
);
//state_localparam && reg  state、n_state
reg [1:0]state ,n_state;
reg ren_Y748_fft1 , ren_Y748_fft2 ;   //用于检测开始信号下降沿
localparam IDLE = 2'b00 ;
localparam FULL_BUF = 2'b01 ;
localparam CALC = 2'b10 ;
//=====================================5*28矩阵相关寄存器
reg [7:0] buffer [0:139] ;   //5*28矩阵
reg  [9:0]buf_addr;        //读地址延迟一个时钟
reg Y_ren_fft1;              //原图读使能打一拍
reg  flag_28;              //当收到cnt_f=2时置1，当con_28=28时置0
reg [4:0]con_28 ;       //0-27
//===================5*5fliter模板reg
reg [1:0]con_f ,con_f_fft1 ;
reg [4:0]con_24 ;       //0-23
reg [4:0]con_h24 ;       //0-23
reg [4:0]con_l24 ;       //0-23
 reg signed [7:0] weight_1 [0:24];
 reg signed [7:0] weight_2 [0:24];
 reg signed [7:0] weight_3 [0:24];
 reg signed [7:0] weight_con [0:24];
 reg signed [7:0] bias [0:2];
 reg signed [15:0] bias_con ; 
 reg  signed[8:0] data_con [0:24];
 reg signed [19:0] conv_out;
 reg [10:0]waddr;
 reg wen,wen_fft1;
 reg flag_con; //Y_ren下降沿触发开始算数
  initial begin
   $readmemh("../../data/conv1_weight_1.txt", weight_1);
   $readmemh("../../data/conv1_weight_2.txt", weight_2);
   $readmemh("../../data/conv1_weight_3.txt", weight_3);
   $readmemh("../../data/conv1_bias.txt", bias);
 end
//==================state2n_state
always@( posedge clk or negedge rst_n  )begin
    if( rst_n == 1'b0 ) begin
        ren_Y748_fft1 <= 1'b0 ;
        ren_Y748_fft2 <= 1'b0 ;
    end 
    else begin
        ren_Y748_fft1 <= ren_Y748 ;
        ren_Y748_fft2 <= ren_Y748_fft1 ;
    end 
end

    always @(posedge clk or negedge rst_n ) begin
        if( rst_n == 1'b0 )
            state   <=   IDLE ;
        else begin
            state   <=  n_state;
        end  
    end

always@(* )begin
    if( rst_n == 1'b0 )
            n_state   <=   IDLE ;
    else
    case( state )
        IDLE:             n_state = (  ren_Y748_fft1 != ren_Y748_fft2   &&  ren_Y748_fft2 ==1  )?  FULL_BUF  :IDLE ;
        FULL_BUF:  n_state = (  Y_ren_fft1 != Y_ren   &&  Y_ren_fft1==1  )? CALC :  FULL_BUF ;
        CALC:           n_state = (  waddr == 1727  )?IDLE:CALC;
        default:n_state<=IDLE;
    endcase
end 
//==================================
//========conv1_ren //下降沿表示数据更新完成

//============组合逻辑，根据cnt_f控制当前是第几个模板，0，1，2
always@(posedge clk)begin
   if( con_f == 2'b00)begin
       weight_con[0] <= weight_1[0] ;       weight_con[1] <= weight_1[1] ;     weight_con[2] <= weight_1[2] ;      weight_con[3] <= weight_1[3] ;      weight_con[4] <= weight_1[4] ;  
       weight_con[5] <= weight_1[5] ;       weight_con[6] <= weight_1[6] ;     weight_con[7] <= weight_1[7] ;      weight_con[8] <= weight_1[8] ;      weight_con[9] <= weight_1[9] ;
       weight_con[10] <= weight_1[10] ;  weight_con[11] <= weight_1[11] ; weight_con[12] <= weight_1[12] ;  weight_con[13] <= weight_1[13] ; weight_con[14] <= weight_1[14] ;  
       weight_con[15] <= weight_1[15] ;  weight_con[16] <= weight_1[16] ; weight_con[17] <= weight_1[17] ;  weight_con[18] <= weight_1[18] ; weight_con[19] <= weight_1[19] ;
       weight_con[20] <= weight_1[20] ;  weight_con[21] <= weight_1[21] ; weight_con[22] <= weight_1[22] ;  weight_con[23] <= weight_1[23] ; weight_con[24] <= weight_1[24] ; 
       bias_con <={ bias[0] ,8'b0}  ;
   end 
   if( con_f == 2'b01)begin
       weight_con[0] <= weight_2[0] ;       weight_con[1] <= weight_2[1] ;     weight_con[2] <= weight_2[2] ;      weight_con[3] <= weight_2[3] ;      weight_con[4] <= weight_2[4] ;  
       weight_con[5] <= weight_2[5] ;       weight_con[6] <= weight_2[6] ;     weight_con[7] <= weight_2[7] ;      weight_con[8] <= weight_2[8] ;      weight_con[9] <= weight_2[9] ;
       weight_con[10] <= weight_2[10] ;  weight_con[11] <= weight_2[11] ; weight_con[12] <= weight_2[12] ;  weight_con[13] <= weight_2[13] ; weight_con[14] <= weight_2[14] ;  
       weight_con[15] <= weight_2[15] ;  weight_con[16] <= weight_2[16] ; weight_con[17] <= weight_2[17] ;  weight_con[18] <= weight_2[18] ; weight_con[19] <= weight_2[19] ;
       weight_con[20] <= weight_2[20] ;  weight_con[21] <= weight_2[21] ; weight_con[22] <= weight_2[22] ;  weight_con[23] <= weight_2[23] ; weight_con[24] <= weight_2[24] ; 
       bias_con <= { bias[1] ,8'b0}  ;  
   end 
   if( con_f == 2'b10)begin
       weight_con[0] <= weight_3[0] ;       weight_con[1] <= weight_3[1] ;     weight_con[2] <= weight_3[2] ;      weight_con[3] <= weight_3[3] ;      weight_con[4] <= weight_3[4] ;  
       weight_con[5] <= weight_3[5] ;       weight_con[6] <= weight_3[6] ;     weight_con[7] <= weight_3[7] ;      weight_con[8] <= weight_3[8] ;      weight_con[9] <= weight_3[9] ;
       weight_con[10] <= weight_3[10] ;  weight_con[11] <= weight_3[11] ; weight_con[12] <= weight_3[12] ;  weight_con[13] <= weight_3[13] ; weight_con[14] <= weight_3[14] ;  
       weight_con[15] <= weight_3[15] ;  weight_con[16] <= weight_3[16] ; weight_con[17] <= weight_3[17] ;  weight_con[18] <= weight_3[18] ; weight_con[19] <= weight_3[19] ;
       weight_con[20] <= weight_3[20] ;  weight_con[21] <= weight_3[21] ; weight_con[22] <= weight_3[22] ;  weight_con[23] <= weight_3[23] ; weight_con[24] <= weight_3[24] ; 
       bias_con <= { bias[2] ,8'b0}  ; 
   end 
end 
//=============5*28矩阵buffer
always@(posedge clk or negedge rst_n   )begin
    if( rst_n == 1'b0 || state  == IDLE  )begin
        Y_ren <= 1'b0;
        Y_ren_fft1 <= 1'b0;
        raddr <= 10'd0;
        buf_addr <= 10'd0;
        flag_28  <=1'b0 ;              //当收到cnt_f=2时置1，当con_28=28时置0,置1时表示进入读数操作
        con_28 <= 5'b0 ;
    end
    else begin
        Y_ren_fft1 <= Y_ren ;
        if( state  ==  FULL_BUF )begin
            Y_ren <= 1'b1;     //其下降沿触发，进入CLAC
            buf_addr <= raddr ; 
            if ( Y_ren  == 1'b1 && raddr != 140 )begin
                raddr <= raddr + 1'b1;
                buffer[ buf_addr ] <= data_in ;
            end
            if( raddr == 140 )begin
                Y_ren <= 1'b0;
                buffer[ buf_addr ] <= data_in ; 
            end
        end
        if( state  ==  CALC )begin
            if( con_f == 2'b10  )begin
                flag_28 <=1'b1;
            end 
            if( flag_28 == 1'b1 )begin
                Y_ren <= 1'b1;
                begin
                    if(  con_28 == 5'd27  )begin
                        Y_ren <= 1'b0; 
                        raddr <= raddr ;
                    end
                    else
                        raddr <= raddr +1'b1 ;
                end
                if( Y_ren == 1'b1 )begin 
                    begin
                        if(  con_28 == 5'd27  )begin
                            con_28 <=5'b00000;
                            flag_28 <=1'b0;
                        end
                        else
                            con_28 <= con_28 + 1'b1 ;
                    end
                    buffer[ 0 + con_28 ]<=buffer[ 28 + con_28 ] ; 
                    buffer[ 28 + con_28 ]<=buffer[ 56 + con_28 ] ; 
                    buffer[ 56 + con_28 ]<=buffer[ 84 + con_28 ] ; 
                    buffer[ 84 + con_28 ]<=buffer[ 112 + con_28 ] ;
                    buffer[ 112 + con_28 ] <= data_in ; 
                end
            end
        end
    end
end
//=====================CALC
always@(posedge clk or negedge rst_n   )begin
    if(  rst_n == 1'b0  || state  == IDLE )begin
        con_f <= 2'b00 ;   //模板选择
        con_f_fft1 <= 2'b00 ;
        con_24 <= 5'b00000  ;       //0-23,计算次数数量
        con_h24 <= 5'b00000  ;       //0-23，计算地址行数
        con_l24 <= 5'b00000  ;       //0-23，计算地址列数
        conv_out <= 12'd0 ;
        waddr <= 11'd0 ;
        wen <= 1'b0 ;
        wen_fft1 <= 1'b0 ;
        flag_con <=1'b0 ;
        conv1_ren <= 1'b0 ;
    end
    else  begin
        wen_fft1 <= wen ;
        con_f_fft1 <= con_f ;
        if( state  ==  CALC )begin
            conv1_ren <= 1'b1 ;
            if( con_24 == 23 && con_f ==2'b00 )begin
                con_f <=2'b01 ;
            end
            if( con_24 == 23 && con_f ==2'b01 )begin
                con_f <=2'b10 ;
            end
            if( con_24 == 23 && con_f ==2'b10 )begin
                con_f <=2'b00 ;
            end
           data_con[0] <= {1'b0,buffer[ 0 + con_24 ]} ; data_con[1] <= {1'b0,buffer[ 1 + con_24 ]} ; data_con[2] <= {1'b0,buffer[ 2 + con_24 ]} ; data_con[3] <= {1'b0,buffer[ 3 + con_24 ] }; data_con[4] <= {1'b0,buffer[ 4 + con_24 ] };
           data_con[5] <= {1'b0,buffer[ 28 + con_24 ]} ; data_con[6] <={1'b0, buffer[ 29 + con_24 ]} ; data_con[7] <= {1'b0,buffer[ 30 + con_24 ]} ; data_con[8] <= {1'b0,buffer[ 31 + con_24 ] }  ; data_con[9] <= {1'b0,buffer[ 32 + con_24 ] };
           data_con[10] <={1'b0, buffer[ 56 + con_24 ]} ; data_con[11] <= {1'b0,buffer[ 57 + con_24 ]} ; data_con[12] <={1'b0, buffer[ 58 + con_24 ]} ; data_con[13] <= {1'b0,buffer[ 59 + con_24 ]    } ; data_con[14] <={1'b0, buffer[ 60 + con_24 ]} ;
           data_con[15] <= {1'b0,buffer[ 84 + con_24 ] }; data_con[16] <= {1'b0,buffer[ 85 + con_24 ]} ; data_con[17] <={1'b0, buffer[ 86 + con_24 ]} ; data_con[18] <= {1'b0,buffer[ 87 + con_24 ] }; data_con[19] <={1'b0, buffer[ 88 + con_24 ]} ;
           data_con[20] <= {1'b0,buffer[ 112 + con_24 ]} ; data_con[21] <={1'b0, buffer[ 113 + con_24 ]} ; data_con[22] <={1'b0, buffer[ 114 + con_24 ] }; data_con[23] <= {1'b0,buffer[ 115 + con_24 ] }; data_con[24] <={1'b0, buffer[ 116 + con_24 ]} ; 
           if(( Y_ren_fft1 != Y_ren   &&  Y_ren_fft1==1 ) || conv1_ren == 1'b0  )begin
               flag_con <=1'b1 ;
           end
           if( flag_con ==1'b1 )begin
               wen <= 1'b1 ;
               conv_out <= data_con[0]*weight_con[0] + data_con[1]*weight_con[1] + data_con[2]*weight_con[2] + data_con[3]*weight_con[3] +  data_con[4]*weight_con[4] +
                                     data_con[5]*weight_con[5] + data_con[6]*weight_con[6] + data_con[7]*weight_con[7] + data_con[8]*weight_con[8] +  data_con[9]*weight_con[9] +
                                     data_con[10]*weight_con[10] + data_con[11]*weight_con[11] + data_con[12]*weight_con[12] + data_con[13]*weight_con[13] +  data_con[14]*weight_con[14] +
                                     data_con[15]*weight_con[15] + data_con[16]*weight_con[16] + data_con[17]*weight_con[17] + data_con[18]*weight_con[18] +  data_con[19]*weight_con[19] +
                                     data_con[20]*weight_con[20] + data_con[21]*weight_con[21] + data_con[22]*weight_con[22] + data_con[23]*weight_con[23] +  data_con[24]*weight_con[24] + bias_con ;
                begin
                    if( con_24 == 23 || ( con_f_fft1 == 2'b10  && con_l24 == 23 ) )
                         con_24 <= 0 ;
                    else
                        con_24 <=  con_24 +1'b1 ;
                end
                if( wen == 1'b1 )begin
                    waddr <= con_f_fft1*576 + 24*con_h24 + con_l24 ; 
                    begin
                        if( con_l24 == 23 )begin
                            con_l24 <= 0 ;
                            if( con_f_fft1 == 2'b10 )begin
                                begin
                                    if( con_h24 == 23 )
                                        con_h24 <= 0 ;
                                    else
                                        con_h24 <=  con_h24 +1'b1 ;
                                end    
                                wen <= 1'b0 ;
                                flag_con  <=1'b0 ;
                            end 
                        end
                        else
                            con_l24 <=  con_l24 +1'b1 ;
                    end 
                end
           end  
        end
    end 
end

//=======================卷积结果寄存器，0-575 通道0 ， 576-1151通道1，1152-1728通道2 。
RAM12_1024   RAM1(   //原始图像 
    .dia		    ( conv_out[19:8] 	), 
	.addra		( waddr	), 
    .cea		    ( wen_fft1 ), 
    
    .dob        ( ram_dob     ),
	.addrb		( ram_addrb ),  
	.ceb		    ( ram_ceb     ),

	.clka		( clk	), 
	.clkb		( clk	)	
);
endmodule
