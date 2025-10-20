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

//=======================比conv1增加：输出输入位宽
                                                                                cnt_3,表示当前处理的是第几张图片，RAM,12BIT,12*12*3 ,pool1*3,0-143,144-287,288-431，在读写地址方面要加144、64。循环也要做相应的调整
                                                                                因此要多增加两组weight和bias并通过cnt_3进行片选
                                                                                两组[19:0]add1[0:7]计算中间值寄存器，把前几次循环的值放在中间，然后结果为：(19:6)[13:0]data_out=[19:0]add1+add2+conv_out，之后在存入RAM8*8*3
                                                                                //=====================22_11_17发现卷积逻辑搞错了，调整循环
*/
//====================
module conv2( 
input clk,
input rst_n,
input ren_Y748,  //开始信号，下降沿开始
input signed[11:0]data_in,
input ram_ceb,
input [7:0]ram_addrb,
output   [8:0]raddr1 ,    //读原图的地址 
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
//============cont_3相关
reg conv2_ren,conv2_ren_fft1,re_start,re_start_fft1,flag_wait;
reg [1:0]cnt_3;
reg [2:0]cnt_8;
reg [8:0]raddr;
//=====================================5*28矩阵相关寄存器
reg [11:0] buffer [0:59] ;   //5*12矩阵
reg  [8:0]buf_addr;        //raddr读地址延迟一个时钟
reg Y_ren_fft1;              //原图读使能打一拍
reg  flag_12;              //当收到cnt_f=2时置1，当con_12=12时置0
reg [3:0]con_12 ;       //0-11
//===================5*5fliter模板reg
reg [1:0]con_f ,con_f_fft1,con_f_fft2 ,con_f_fft3 ;
reg [2:0]con_8 ;       //0-7
reg [4:0]con_h8,con8h ;       //0-23con8h用于结果 ，conh8用于中间值
reg [2:0]con_l8 ;       //0-7
//reg [2:0]con_add8,con_add8_fft1,con_add8_fft2,con_add81 ;       //0-7数con_f_fft2时加了8次，得到8个中间值
 reg signed [7:0] weight_1 [0:24];
 reg signed [7:0] weight_2 [0:24];
 reg signed [7:0] weight_3 [0:24];
 reg signed [7:0] weight_4 [0:24];
 reg signed [7:0] weight_5 [0:24];
 reg signed [7:0] weight_6 [0:24];
 reg signed [7:0] weight_7 [0:24];
 reg signed [7:0] weight_8 [0:24];
 reg signed [7:0] weight_9 [0:24];
 reg signed [7:0] weight_con [0:24];
 reg signed [7:0] bias [0:2];
 wire signed [11:0] exp_bias [0:2];
 reg signed [11:0] data_con [0:24];
 reg signed [19:0] conv_out;
wire signed [19:0] conv_out_add0;
wire signed [19:0] conv_out_add1;
reg signed [19:0] add;
reg signed [11:0] data_out;
 reg [7:0] conv_raddr;
 reg [7:0] conv_addr;
 reg [7:0] waddr;
 reg [2:0]con_wh8,con_wl8 ;//算输出地址
 reg [1:0]con_w3 ; //算输出地址
 reg wen,wen_fft1;  //conv2修改后不作为RAM的使能，纯标志
 reg write,write_flag,waddr_flag ; //conv2的写RAM使能
 reg flag_con; //Y_ren下降沿触发开始算数
  initial begin
     //BIAS
     $readmemh("../../data/conv2_bias.txt", bias);
     //clac1
     $readmemh("../../data/conv2_weight_11.txt", weight_1);
     $readmemh("../../data/conv2_weight_12.txt", weight_2);
	 $readmemh("../../data/conv2_weight_13.txt", weight_3);
     //clac2
     $readmemh("../../data/conv2_weight_21.txt", weight_4);
	 $readmemh("../../data/conv2_weight_22.txt", weight_5);
	 $readmemh("../../data/conv2_weight_23.txt", weight_6);
     //clac3
     $readmemh("../../data/conv2_weight_31.txt", weight_7);
	 $readmemh("../../data/conv2_weight_32.txt", weight_8);
	 $readmemh("../../data/conv2_weight_33.txt", weight_9);
 end
//==================state2n_state
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
        IDLE:             n_state = ( re_start_fft1 != re_start   &&  re_start_fft1 ==1  )?  FULL_BUF  :IDLE ;
        FULL_BUF:  n_state = (  Y_ren_fft1 != Y_ren   &&  Y_ren_fft1==1  )? CALC :  FULL_BUF ;
        CALC:           n_state = (  conv_addr == 191  )?IDLE:CALC;
        default:n_state<=IDLE;
    endcase
end 
//==================================raddr和raddr1
assign raddr1 = raddr + cnt_3*144;
//========conv2_ren //下降沿表示数据更新完成//cnt_3相关，当conv2_ren下降沿时cnt_3<=cnt_3+1;重新发出类似于REN_Y748信号重新计数使conv重新工作
always@(  posedge clk or negedge rst_n   )begin
    if( rst_n == 1'b0 )begin
        cnt_3 <=2'b00 ;
        re_start <= 1'b0 ;
        re_start_fft1  <= 1'b0 ;
        conv2_ren_fft1 <= 1'b0 ;
        cnt_8 <= 3'b000;
        flag_wait <= 1'b0;
        ren_Y748_fft1 <= 1'b0 ;
        ren_Y748_fft2 <= 1'b0 ;
        conv1_ren <= 1'b0 ;
    end
    else  begin
        ren_Y748_fft1 <= ren_Y748 ;
        ren_Y748_fft2 <= ren_Y748_fft1 ;
        re_start_fft1  <= re_start ;
        conv2_ren_fft1 <= conv2_ren ;
        begin
            if( conv2_ren_fft1 != conv2_ren   &&  conv2_ren_fft1==1  && cnt_3 ==2'b10 )
                conv1_ren <= 1'b0 ;
            else
                conv1_ren <= 1'b1 ;
        end
       if( conv2_ren_fft1 != conv2_ren   &&  conv2_ren_fft1==1  && cnt_3 ==2'b10 )begin
           cnt_3 <= 2'b00 ;
       end
       begin
           if(  ren_Y748_fft1 != ren_Y748_fft2   &&  ren_Y748_fft2 ==1  )begin
               re_start <= 1'b0 ; 
           end
           else if( conv2_ren_fft1 != conv2_ren   &&  conv2_ren_fft1==1  && cnt_3 !=2'b10 )begin
               flag_wait <= 1'b1;
           end
           else 
               re_start <= 1'b1 ; 
       end
       if( flag_wait == 1'b1 )begin
           if(cnt_8 != 7 )
               cnt_8 <= cnt_8 +1 ;
           else begin
               re_start <= 1'b0 ; 
               cnt_3 <= cnt_3 + 2'b01 ;
               cnt_8 <= 0 ;
               flag_wait <= 1'b0;
           end
       end
    end
end

//============逻辑，根据cnt_f控制当前是第几个模板，0，1，2
 assign exp_bias[0] = (bias[0][7] == 1) ? {4'b1111, bias[0]} : {4'b0000, bias[0]};
 assign exp_bias[1] = (bias[1][7] == 1) ? {4'b1111, bias[1]} : {4'b0000, bias[1]};
 assign exp_bias[2] = (bias[2][7] == 1) ? {4'b1111, bias[2]} : {4'b0000, bias[2]};
always@(posedge clk)begin
    if ( cnt_3 == 0 )begin 
       // bias_con <= (bias[0][7] == 1) ? {4'b1111, bias[0]} : {4'b0000, bias[0]};
        if( con_f == 2'b00 )begin
           weight_con[0] <= weight_1[0] ;       weight_con[1] <= weight_1[1] ;     weight_con[2] <= weight_1[2] ;      weight_con[3] <= weight_1[3] ;      weight_con[4] <= weight_1[4] ;  
           weight_con[5] <= weight_1[5] ;       weight_con[6] <= weight_1[6] ;     weight_con[7] <= weight_1[7] ;      weight_con[8] <= weight_1[8] ;      weight_con[9] <= weight_1[9] ;
           weight_con[10] <= weight_1[10] ;  weight_con[11] <= weight_1[11] ; weight_con[12] <= weight_1[12] ;  weight_con[13] <= weight_1[13] ; weight_con[14] <= weight_1[14] ;  
           weight_con[15] <= weight_1[15] ;  weight_con[16] <= weight_1[16] ; weight_con[17] <= weight_1[17] ;  weight_con[18] <= weight_1[18] ; weight_con[19] <= weight_1[19] ;
           weight_con[20] <= weight_1[20] ;  weight_con[21] <= weight_1[21] ; weight_con[22] <= weight_1[22] ;  weight_con[23] <= weight_1[23] ; weight_con[24] <= weight_1[24] ;    
       end 
       if( con_f == 2'b01)begin
           weight_con[0] <= weight_4[0] ;       weight_con[1] <= weight_4[1] ;     weight_con[2] <= weight_4[2] ;      weight_con[3] <= weight_4[3] ;      weight_con[4] <= weight_4[4] ;  
           weight_con[5] <= weight_4[5] ;       weight_con[6] <= weight_4[6] ;     weight_con[7] <= weight_4[7] ;      weight_con[8] <= weight_4[8] ;      weight_con[9] <= weight_4[9] ;
           weight_con[10] <= weight_4[10] ;  weight_con[11] <= weight_4[11] ; weight_con[12] <= weight_4[12] ;  weight_con[13] <= weight_4[13] ; weight_con[14] <= weight_4[14] ;  
           weight_con[15] <= weight_4[15] ;  weight_con[16] <= weight_4[16] ; weight_con[17] <= weight_4[17] ;  weight_con[18] <= weight_4[18] ; weight_con[19] <= weight_4[19] ;
           weight_con[20] <= weight_4[20] ;  weight_con[21] <= weight_4[21] ; weight_con[22] <= weight_4[22] ;  weight_con[23] <= weight_4[23] ; weight_con[24] <= weight_4[24] ; 
       end 
       if( con_f == 2'b10)begin
           weight_con[0] <= weight_7[0] ;       weight_con[1] <= weight_7[1] ;     weight_con[2] <= weight_7[2] ;      weight_con[3] <= weight_7[3] ;      weight_con[4] <= weight_7[4] ;  
           weight_con[5] <= weight_7[5] ;       weight_con[6] <= weight_7[6] ;     weight_con[7] <= weight_7[7] ;      weight_con[8] <= weight_7[8] ;      weight_con[9] <= weight_7[9] ;
           weight_con[10] <= weight_7[10] ;  weight_con[11] <= weight_7[11] ; weight_con[12] <= weight_7[12] ;  weight_con[13] <= weight_7[13] ; weight_con[14] <= weight_7[14] ;  
           weight_con[15] <= weight_7[15] ;  weight_con[16] <= weight_7[16] ; weight_con[17] <= weight_7[17] ;  weight_con[18] <= weight_7[18] ; weight_con[19] <= weight_7[19] ;
           weight_con[20] <= weight_7[20] ;  weight_con[21] <= weight_7[21] ; weight_con[22] <= weight_7[22] ;  weight_con[23] <= weight_7[23] ; weight_con[24] <= weight_7[24] ;
           
       end 
    end 
    if ( cnt_3 == 1 )begin 
      //  bias_con <= (bias[1][7] == 1) ? {4'b1111, bias[1]} : {4'b0000, bias[1]};
        if( con_f == 2'b00 )begin
           weight_con[0] <= weight_2[0] ;       weight_con[1] <= weight_2[1] ;     weight_con[2] <= weight_2[2] ;      weight_con[3] <= weight_2[3] ;      weight_con[4] <= weight_2[4] ;  
           weight_con[5] <= weight_2[5] ;       weight_con[6] <= weight_2[6] ;     weight_con[7] <= weight_2[7] ;      weight_con[8] <= weight_2[8] ;      weight_con[9] <= weight_2[9] ;
           weight_con[10] <= weight_2[10] ;  weight_con[11] <= weight_2[11] ; weight_con[12] <= weight_2[12] ;  weight_con[13] <= weight_2[13] ; weight_con[14] <= weight_2[14] ;  
           weight_con[15] <= weight_2[15] ;  weight_con[16] <= weight_2[16] ; weight_con[17] <= weight_2[17] ;  weight_con[18] <= weight_2[18] ; weight_con[19] <= weight_2[19] ;
           weight_con[20] <= weight_2[20] ;  weight_con[21] <= weight_2[21] ; weight_con[22] <= weight_2[22] ;  weight_con[23] <= weight_2[23] ; weight_con[24] <= weight_2[24] ;   
       end 
       if( con_f == 2'b01)begin
           weight_con[0] <= weight_5[0] ;       weight_con[1] <= weight_5[1] ;     weight_con[2] <= weight_5[2] ;      weight_con[3] <= weight_5[3] ;      weight_con[4] <= weight_5[4] ;  
           weight_con[5] <= weight_5[5] ;       weight_con[6] <= weight_5[6] ;     weight_con[7] <= weight_5[7] ;      weight_con[8] <= weight_5[8] ;      weight_con[9] <= weight_5[9] ;
           weight_con[10] <= weight_5[10] ;  weight_con[11] <= weight_5[11] ; weight_con[12] <= weight_5[12] ;  weight_con[13] <= weight_5[13] ; weight_con[14] <= weight_5[14] ;  
           weight_con[15] <= weight_5[15] ;  weight_con[16] <= weight_5[16] ; weight_con[17] <= weight_5[17] ;  weight_con[18] <= weight_5[18] ; weight_con[19] <= weight_5[19] ;
           weight_con[20] <= weight_5[20] ;  weight_con[21] <= weight_5[21] ; weight_con[22] <= weight_5[22] ;  weight_con[23] <= weight_5[23] ; weight_con[24] <= weight_5[24] ; 
       end 
       if( con_f == 2'b10)begin
           weight_con[0] <= weight_8[0] ;       weight_con[1] <= weight_8[1] ;     weight_con[2] <= weight_8[2] ;      weight_con[3] <= weight_8[3] ;      weight_con[4] <= weight_8[4] ;  
           weight_con[5] <= weight_8[5] ;       weight_con[6] <= weight_8[6] ;     weight_con[7] <= weight_8[7] ;      weight_con[8] <= weight_8[8] ;      weight_con[9] <= weight_8[9] ;
           weight_con[10] <= weight_8[10] ;  weight_con[11] <= weight_8[11] ; weight_con[12] <= weight_8[12] ;  weight_con[13] <= weight_8[13] ; weight_con[14] <= weight_8[14] ;  
           weight_con[15] <= weight_8[15] ;  weight_con[16] <= weight_8[16] ; weight_con[17] <= weight_8[17] ;  weight_con[18] <= weight_8[18] ; weight_con[19] <= weight_8[19] ;
           weight_con[20] <= weight_8[20] ;  weight_con[21] <= weight_8[21] ; weight_con[22] <= weight_8[22] ;  weight_con[23] <= weight_8[23] ; weight_con[24] <= weight_8[24] ; 
       end 
    end
    if ( cnt_3 == 2 )begin 
     //   bias_con <= (bias[2][7] == 1) ? {4'b1111, bias[2]} : {4'b0000, bias[2]};
        if( con_f == 2'b00 )begin
           weight_con[0] <= weight_3[0] ;       weight_con[1] <= weight_3[1] ;     weight_con[2] <= weight_3[2] ;      weight_con[3] <= weight_3[3] ;      weight_con[4] <= weight_3[4] ;  
           weight_con[5] <= weight_3[5] ;       weight_con[6] <= weight_3[6] ;     weight_con[7] <= weight_3[7] ;      weight_con[8] <= weight_3[8] ;      weight_con[9] <= weight_3[9] ;
           weight_con[10] <= weight_3[10] ;  weight_con[11] <= weight_3[11] ; weight_con[12] <= weight_3[12] ;  weight_con[13] <= weight_3[13] ; weight_con[14] <= weight_3[14] ;  
           weight_con[15] <= weight_3[15] ;  weight_con[16] <= weight_3[16] ; weight_con[17] <= weight_3[17] ;  weight_con[18] <= weight_3[18] ; weight_con[19] <= weight_3[19] ;
           weight_con[20] <= weight_3[20] ;  weight_con[21] <= weight_3[21] ; weight_con[22] <= weight_3[22] ;  weight_con[23] <= weight_3[23] ; weight_con[24] <= weight_3[24] ;    
       end 
       if( con_f == 2'b01)begin
           weight_con[0] <= weight_6[0] ;       weight_con[1] <= weight_6[1] ;     weight_con[2] <= weight_6[2] ;      weight_con[3] <= weight_6[3] ;      weight_con[4] <= weight_6[4] ;  
           weight_con[5] <= weight_6[5] ;       weight_con[6] <= weight_6[6] ;     weight_con[7] <= weight_6[7] ;      weight_con[8] <= weight_6[8] ;      weight_con[9] <= weight_6[9] ;
           weight_con[10] <= weight_6[10] ;  weight_con[11] <= weight_6[11] ; weight_con[12] <= weight_6[12] ;  weight_con[13] <= weight_6[13] ; weight_con[14] <= weight_6[14] ;  
           weight_con[15] <= weight_6[15] ;  weight_con[16] <= weight_6[16] ; weight_con[17] <= weight_6[17] ;  weight_con[18] <= weight_6[18] ; weight_con[19] <= weight_6[19] ;
           weight_con[20] <= weight_6[20] ;  weight_con[21] <= weight_6[21] ; weight_con[22] <= weight_6[22] ;  weight_con[23] <= weight_6[23] ; weight_con[24] <= weight_6[24] ; 
       end 
       if( con_f == 2'b10)begin
           weight_con[0] <= weight_9[0] ;       weight_con[1] <= weight_9[1] ;     weight_con[2] <= weight_9[2] ;      weight_con[3] <= weight_9[3] ;      weight_con[4] <= weight_9[4] ;  
           weight_con[5] <= weight_9[5] ;       weight_con[6] <= weight_9[6] ;     weight_con[7] <= weight_9[7] ;      weight_con[8] <= weight_9[8] ;      weight_con[9] <= weight_9[9] ;
           weight_con[10] <= weight_9[10] ;  weight_con[11] <= weight_9[11] ; weight_con[12] <= weight_9[12] ;  weight_con[13] <= weight_9[13] ; weight_con[14] <= weight_9[14] ;  
           weight_con[15] <= weight_9[15] ;  weight_con[16] <= weight_9[16] ; weight_con[17] <= weight_9[17] ;  weight_con[18] <= weight_9[18] ; weight_con[19] <= weight_9[19] ;
           weight_con[20] <= weight_9[20] ;  weight_con[21] <= weight_9[21] ; weight_con[22] <= weight_9[22] ;  weight_con[23] <= weight_9[23] ; weight_con[24] <= weight_9[24] ; 
       end 
    end
end 
//=============5*28矩阵buffer
always@(posedge clk or negedge rst_n   )begin
    if( rst_n == 1'b0 || state  == IDLE  )begin
        Y_ren <= 1'b0;
        Y_ren_fft1 <= 1'b0;
        raddr <= 10'd0;
        buf_addr <= 10'd0;
        flag_12  <=1'b0 ;              //当收到cnt_f=2时置1，当con_12=12时置0,置1时表示进入读数操作
        con_12 <= 4'b0000 ;
    end
    else begin
        Y_ren_fft1 <= Y_ren ;
        if( state  ==  FULL_BUF )begin
            Y_ren <= 1'b1;     //其下降沿触发，进入CLAC
            buf_addr <= raddr ; 
            if ( Y_ren  == 1'b1 && raddr != 60 )begin
                raddr <= raddr + 1'b1;
                buffer[ buf_addr ] <= data_in ;
            end
            if( raddr == 60 )begin
                Y_ren <= 1'b0;
                buffer[ buf_addr ] <= data_in ; 
            end
        end
        if( state  ==  CALC )begin
            if( con_f == 2'b10  )begin
                flag_12 <=1'b1;
            end 
            if( flag_12 == 1'b1 )begin
                Y_ren <= 1'b1;
                begin
                    if(  con_12 == 4'd11  )begin
                        Y_ren <= 1'b0; 
                        raddr <= raddr ;
                    end
                    else
                        raddr <= raddr +1'b1 ;
                end
                if( Y_ren == 1'b1 )begin 
                    begin
                        if(  con_12 == 4'd11  )begin
                            con_12 <=4'b0000;
                            flag_12 <=1'b0;
                        end
                        else
                            con_12 <= con_12 + 1'b1 ;
                    end
                    buffer[ 0 + con_12 ]<=buffer[ 12 + con_12 ] ; 
                    buffer[ 12 + con_12 ]<=buffer[ 24 + con_12 ] ; 
                    buffer[ 24 + con_12 ]<=buffer[ 36 + con_12 ] ; 
                    buffer[ 36 + con_12 ]<=buffer[ 48 + con_12 ] ;
                    buffer[ 48 + con_12 ] <= data_in ; 
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
        con_f_fft2 <= 2'b00 ;
        con_f_fft3 <= 2'b00 ;
        con_8 <= 3'b000  ;       //0-7,计算次数数量
        con_h8 <= 5'b000  ;       //0-8*3-1，计算地址行数
        con_l8 <= 3'b000  ;       //0-7，计算地址列数
        conv_out <= 20'd0 ; 
        conv_addr <= 8'd0 ; 
        wen <= 1'b0 ;
        wen_fft1 <= 1'b0 ;
        flag_con <=1'b0 ;
        conv2_ren <= 1'b0 ;
    end
    else  begin
        wen_fft1 <= wen ;
        con_f_fft1 <= con_f ;
        con_f_fft2 <= con_f_fft1 ;
        con_f_fft3 <= con_f_fft2 ;
        if( state  ==  CALC )begin
            conv2_ren <= 1'b1 ;
            if( con_8 == 7 && con_f ==2'b00 )begin
                con_f <=2'b01 ;
            end
            if( con_8 == 7 && con_f ==2'b01 )begin
                con_f <=2'b10 ;
            end
            if( con_8 == 7 && con_f ==2'b10 )begin
                con_f <=2'b00 ;
            end
           data_con[0] <= buffer[ 0 + con_8 ] ; data_con[1] <= buffer[ 1 + con_8 ] ; data_con[2] <= buffer[ 2 + con_8 ] ; data_con[3] <= buffer[ 3 + con_8 ] ; data_con[4] <= buffer[ 4 + con_8 ] ;
           data_con[5] <= buffer[ 12 + con_8 ] ; data_con[6] <= buffer[ 13 + con_8 ] ; data_con[7] <= buffer[ 14 + con_8 ] ; data_con[8] <= buffer[ 15 + con_8 ] ; data_con[9] <= buffer[ 16 + con_8 ] ;
           data_con[10] <= buffer[ 24 + con_8 ] ; data_con[11] <= buffer[ 25 + con_8 ] ; data_con[12] <= buffer[ 26 + con_8 ] ; data_con[13] <= buffer[ 27 + con_8 ] ; data_con[14] <= buffer[ 28 + con_8 ] ;
           data_con[15] <= buffer[ 36 + con_8 ] ; data_con[16] <= buffer[ 37 + con_8 ] ; data_con[17] <= buffer[ 38 + con_8 ] ; data_con[18] <= buffer[ 39 + con_8 ] ; data_con[19] <= buffer[ 40 + con_8 ] ;
           data_con[20] <= buffer[ 48 + con_8 ] ; data_con[21] <= buffer[ 49 + con_8 ] ; data_con[22] <= buffer[ 50 + con_8 ] ; data_con[23] <= buffer[ 51 + con_8 ] ; data_con[24] <= buffer[ 52 + con_8 ] ; 
           if(( Y_ren_fft1 != Y_ren   &&  Y_ren_fft1==1 ) || conv2_ren == 1'b0  )begin
               flag_con <=1'b1 ;
           end
        
           if( flag_con ==1'b1 )begin
               wen <= 1'b1 ;
               conv_out <= data_con[0]*weight_con[0] + data_con[1]*weight_con[1] + data_con[2]*weight_con[2] + data_con[3]*weight_con[3] +  data_con[4]*weight_con[4] +
                                     data_con[5]*weight_con[5] + data_con[6]*weight_con[6] + data_con[7]*weight_con[7] + data_con[8]*weight_con[8] +  data_con[9]*weight_con[9] +
                                     data_con[10]*weight_con[10] + data_con[11]*weight_con[11] + data_con[12]*weight_con[12] + data_con[13]*weight_con[13] +  data_con[14]*weight_con[14] +
                                     data_con[15]*weight_con[15] + data_con[16]*weight_con[16] + data_con[17]*weight_con[17] + data_con[18]*weight_con[18] +  data_con[19]*weight_con[19] +
                                     data_con[20]*weight_con[20] + data_con[21]*weight_con[21] + data_con[22]*weight_con[22] + data_con[23]*weight_con[23] +  data_con[24]*weight_con[24]  ;
                begin
                    if( con_8 == 7 || ( con_f_fft1 == 2'b10  && con_l8 == 7 ) )
                         con_8 <= 0 ;
                    else
                        con_8 <=  con_8 +1'b1 ;
                end
                
                if( wen == 1'b1 )begin//缓存数据地址生成，以及缓存写使能
                        conv_addr <= con_h8*8 + con_l8 ;  
                    begin
                        if( con_l8 == 7 )begin
                            con_l8 <= 0 ;
                            begin
                                    if( con_h8 == 23 )
                                        con_h8 <= 0 ;
                                    else
                                        con_h8 <=  con_h8 +1'b1 ;
                            end  
                            if( con_f_fft1 == 2'b10 )begin
                                wen <= 1'b0 ;
                                flag_con  <=1'b0 ;
                            end 
                        end
                        else
                            con_l8 <=  con_l8 +1'b1 ;
                    end 
                end
           end  
        end
    end 
end
//===============结果输出部分：
always@(posedge clk or negedge rst_n   )begin
    if(  rst_n == 1'b0   )begin
        data_out <= 12'd0 ; 
        waddr <= 8'd0 ;
        conv_raddr <= 8'd0 ;
        write<= 1'b0 ;
        write_flag<= 1'b0 ;
        waddr_flag <= 1'b0 ;
        con8h <=5'b00000 ;
        add <= 20'd0 ;
        con_wh8 <= 3'b000 ;
        con_wl8 <= 3'b000 ;
        con_w3 <= 2'b00 ;
    end
    else begin 
        if( cnt_3 == 2 && state == CALC )begin
            write_flag<= 1'b1 ;
        end
        begin
            if( write_flag  ==  1'b0 )begin
            end 
            else begin
                write <= waddr_flag ;
                begin
                    if( con_8 + con8h*8 > 191)
                        conv_raddr <= 191 ;
                    else
                        conv_raddr <= con_8 + con8h*8 ;
                end
                if( con_8 == 7 )begin
                    con8h <= con8h + 1  ;
                end
                if( wen_fft1 )begin
                    add <= conv_out_add0 + conv_out_add1 + conv_out  ;
                end
                data_out <=  add[19:7] + exp_bias[con_w3] ;
                waddr <= con_wl8 + con_wh8*8 + con_w3*64  ;
                begin//=== write == 1 时===输入地址waddr控制跳转
                    if( wen_fft1 &&  con_l8 == 1 )begin
                        waddr_flag <= 1 ;
                    end
                    if( waddr_flag == 1 )begin
                        if( con_wl8 == 7 )begin
                            con_wl8 <= 0 ;
                            if( con_w3 == 2 )begin
                                con_w3 <= 0 ;
                                con_wh8 <= con_wh8 + 1 ;
                                 waddr_flag <= 0 ;
                            end
                            else
                                con_w3 <=con_w3 + 1 ;
                        end
                        else
                            con_wl8 <= con_wl8 + 1 ;
                    end
                end//======输入地址waddr控制跳转
            end
        end
    end
end   

//========0-7 TU1*W1 8-15 TU*W4 16-23 TU*W7
RAM20_191   RAMT1(   
    .dia		    ( conv_out	), 
	.addra		( conv_addr ), 
    .cea		    ( wen_fft1 && cnt_3 == 0 ), 
    
    .dob        (  conv_out_add0   ),
	.addrb		(  conv_raddr ),  
	.ceb		    (  write_flag   ),

	.clka		( clk	), 
	.clkb		( clk	)	
);

RAM20_191   RAMT2(   
    .dia		    ( conv_out	), 
	.addra		( conv_addr ), 
    .cea		    ( wen_fft1 && cnt_3 == 1 ), 
    
    .dob        ( conv_out_add1    ),
	.addrb		( conv_raddr  ),  
	.ceb		    (  write_flag   ),

	.clka		( clk	), 
	.clkb		( clk	)	
);

//=======================卷积结果寄存器，0-575 通道0 ， 576-1151通道1，1152-1728通道2 。
RAM14_256   RAM1(   //原始图像 
    .dia		    (  data_out	), 
	.addra		(  waddr ), 
    .cea		    ( write ), 
    
    .dob        ( ram_dob     ),
	.addrb		( ram_addrb ),  
	.ceb		    ( ram_ceb     ),

	.clka		( clk	), 
	.clkb		( clk	)	
);
endmodule
