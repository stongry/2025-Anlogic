`timescale 1ns/ 1ps
// --------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>>> COPYRIGHT NOTICE <<<<<<<<<<<<<<<<<<<<<<<<<
// --------------------------------------------------------------------
// 
// AuTHor: 
// 层级只做到L1
// Description:比起网页版做了以下改动
//1、b不再由外部输入，而内部直接用查找表case完成，顺序是从第一行左到右，然后下一行
//                          |   1    3      4      3      1
//                          |   3    8     10     8      3
//高斯矩阵      b: 1/128*   |   4   10    12     10     4
//                          |   3   8     10     8      3
//                          |   1   3     4     3      1
//2、除去了偏移量输入bias
//3、最后结果右移7位，相当除以128
//4、把输出时间计数器out_cnt改成了1位
//5、把乘法改成了组合逻辑，这可能会带来额外的功耗。不过后面可以改
//6、看了一下，系统是下降沿复位，不用改
//                              |  1   2   1
//7、用3*3的矩阵     b: 1/16 *  |  2   4   2    改变矩阵大小时改三个地方，1参数，2矩阵选择，3右移大小
//                   右移4位    |  1   2   1
// 参考web:https://github.com/MasLiang/CNN-On-FPGA/blob/master/verilog/Conv_unsign_sign.v
//                  https://blog.csdn.net/qq_38798425/article/details/108948168
//经过仿真，从输入start开始算起要12个时钟周期出第一个结果。在21周期出第二个结果，每9个周期出一个。
// --------------------------------------------------------------------
module CNN_L1_221009
    #(parameter				   	   bits=8,
      parameter                    filter_size = 9,
      parameter                    filter_size_2 =4//log2（9）后向上取整
      )
    (
	//system clock
	input		 						clk_in		,
	input								rst_n			,
	//feature map input & bias & weight
	input signed	[bits-1:0]	data_in		,	
	//input signed   [(bits<<1)-1:0]	bias			,
	//input	signed	[bits-1:0]	weight		,
	//enable conv
	input 							start			,//计算时要一直置一
	//deature map output 
	output reg signed	[bits-1:0]	data_out		,
	//enable next module
	output reg						ready//握手？可以下一次计算
	);
	
reg signed		[(bits<<1)-1+filter_size_2:0]					add_result;
wire signed		[bits-1:0]										a;
reg signed	    	[bits-1:0]										b;
reg signed		[(bits<<1)-1:0]									p;
assign 	a = data_in;
//assign 	b 		= 														weight;
reg 																		flag;  //为1时表示正在算乘累加
reg 				[filter_size_2-1:0]								cnt;//计算乘累加时用到的计数器，
reg				[1:0]													out_flag; //控制out_ready何时为1
reg																		out_ready; //为1时就开始配置ready和data_out了
reg signed		[(bits<<1)-1+filter_size_2:0]					temp_out;//乘累加结果寄存器，距离最后的结果还差/128 
reg		out_cnt;  //输出时间计数器?这里改成了1位，输出保持1个时钟周期
//reg																		start_delay1;
//reg																		start_delay2;

//mult mult_16_unsign_sign (
//  .clk					(clk_in), // input clk
//  .a						(a), // input [15 : 0] a
//  .b						(b), // input [15 : 0] b
 // .p						(p) // output [31 : 0] p
//  );

//=============这里把上面的乘改为组合逻辑了，还在这里写了b的5*5查找表================
/*
always@(*)begin
  case(cnt)
  0:b=1;
  1:b=3;
  2:b=4;
  3:b=3;
  4:b=1;
  5:b=3;
  6:b=8;
  7:b=10;
  8:b=8;
  9:b=3;
  10:b=4;
  11:b=10;
  12:b=12;
  13:b=10;
  14:b=4;
  15:b=3;
  16:b=8;
  17:b=10;
  18:b=8;
  19:b=3;
  20:b=1;
  21:b=3;
  22:b=4;
  23:b=3;
  24:b=1;
  default :b=0;
  endcase 
   p=a*b;
end
*/
//=============b的3*3查找表================
always@(*)begin
  case(cnt)
  0:b=1;
  1:b=2;    //2
  2:b=1;
  3:b=2;  //2
  4:b=4;//4
  5:b=2;//2
  6:b=1;
  7:b=2; //2
  8:b=1; 
  default :b=0;
  endcase 
   p=a*b;
end


always@(posedge clk_in or negedge rst_n)
begin
	if(~rst_n || start == 1'b0 )
	begin
		cnt 							<=						0;
		add_result					<=						0;
		flag							<=						0;
		temp_out						<=						0;
	end
	else
	begin
	/*	if(start)//==========================有点让费资源了可以改成start_ff1<=start;start_ff2<=start_ff1;经过仿真实际只延迟了一个周期
		begin
			start_delay1         	<=						1'b1;
		end
		else
		begin
			start_delay1				<=						1'b0;
		end//======
		if(start_delay1)
		begin
			start_delay2         	<=						1'b1;
		end
		else
		begin
			start_delay2				<=						1'b0;
		end*/
        //==============================================	
		if(flag == 1'b1 || start == 1'b1)//计算乘累加的过程，结果存到temp_out里，flag为1是表示正在计算，算完置0
		begin
			if(cnt	==	0)
			begin
				cnt					<=					cnt	+	1'b1;
				add_result			<=					p;
				flag					<=					1'b1;
			end
			else if(cnt < filter_size-1)
			begin
				cnt					<=					cnt	+	1'b1;
				add_result			<=					add_result	+	p;
				flag					<=					1'b1;
			end
			else if(cnt == filter_size-1)
			begin
				add_result			<=					add_result	+	p;
				flag					<=					1'b0;
				temp_out				<=					add_result  +	p;
				cnt					<=					1'b0;
			end
		end//==================================================
	end
end

always@(posedge clk_in or negedge rst_n)
begin  
	if(~rst_n  )
	begin
		out_cnt					<=					0;
		out_ready				<=					0; 
        ready				        <=		            0;
        data_out 			    <=		            0;
	end
	else
	begin
		out_flag 				<=					{out_flag[0],flag};     
		if(out_flag[0]&&(~flag))//==================out_ready置1表示正在输出ready，data_out
		begin 
			out_ready				<=					1'b1;
		end
		if(out_ready)                 ////=======/正在输出ready，data_out?
		begin
			if(out_cnt == 0)
			begin
				ready									<=						1'b1;	
				data_out 							<=		temp_out>>4;				//右移4位?/16			
				out_cnt<=	out_cnt  +  1'b1;			
			end
			else if(out_cnt == 1'b1) //这
			begin
				out_cnt								<=						1'b0;
				out_ready							<=						1'b0;
				ready									<=						1'b0;	
			end
		end
	end
end
endmodule