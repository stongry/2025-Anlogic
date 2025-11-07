`timescale 1ns/ 1ps
module POOL_CORE    //MAX_POOLING
    #(parameter				   	   bits=8,
      parameter                       filter_size = 4, //核的大小a*a
      parameter                        filter_size_2 =2//log2（9）后向上取整
      )
    (
	//system clock
	input	 clk_in ,
	input	 rst_n   ,
	//feature map input 
	input signed	[bits-1:0]	data_in,
	//enable conv
	input 							start	 ,   //计算时要一直置一,经过仿真，从输入start开始算起要6个时钟周期出第一个结果。在10周期出第二个结果，每4个周期出一个。
	//deature map output 
	output reg signed	[bits-1:0]	data_out	 ,
	//enable next module
	output reg				ready       //可以下一次计算
	);
	
reg signed		[bits-1:0]		pool_result , pool_result_fft1  ;

 
reg 																		flag;  //为1时表示正在计算
reg 				[filter_size_2-1:0]								cnt;//比大小时用到的计数器，0-filter_size
reg				[1:0]													out_flag; //控制out_ready何时为1
reg																		out_ready; //为1时就开始配置ready和data_out了
reg		out_cnt;  //输出时间计数器?这里改成了1位，输出保持1个时钟周期

wire  bigger;
assign bigger =( pool_result  <=  data_in )?1'b1:1'b0;

always@(posedge clk_in or negedge rst_n)
begin
	if(~rst_n  || (start == 1'b0 && flag == 1'b0  ))
	begin
		cnt 			    	<=						0;
		pool_result 	<=						0;
		flag			    	<=						0;
	end
	else
	begin
		if(flag == 1'b1 || start == 1'b1)//计算乘累加的过程，结果存到temp_out里，flag为1是表示正在计算，算完置0
		begin
			if(cnt	==	0)
			begin
				cnt					    <=					cnt	+	1'b1;
				pool_result		    <=					data_in;
                pool_result_fft1 <= pool_result ;
				flag				    	<=					1'b1;
			end
			else if(cnt < filter_size-1)
			begin
				cnt					    <=					cnt	+	1'b1;
				pool_result		    <=					( bigger)?data_in:pool_result;
				flag					    <=					1'b1;
			end
			else if(cnt == filter_size-1)
			begin
				pool_result		<=					( bigger)?data_in:pool_result;
                
				flag					<=					1'b0;
				cnt					<=					1'b0;
			end
		end//==================================================
	end
end

always@(posedge clk_in or negedge rst_n)
begin
	if(~rst_n || (start == 1'b0 && flag == 1'b0  ))
	begin
		out_cnt					<=					0;
		out_ready				<=					0; 
        ready				        <=		            0;
        data_out 			    <=		            0;
        out_flag 				<= 0;
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
				data_out 							<=	                	pool_result_fft1 ;			 
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
