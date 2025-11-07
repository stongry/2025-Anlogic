`timescale 1ns/ 1ps
// --------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>>> COPYRIGHT NOTICE <<<<<<<<<<<<<<<<<<<<<<<<<
// --------------------------------------------------------------------
// 
// Author: Anlogic
// 
// Description:
//
//		dvp_ov2640,摄像头数据缓存读写
// 
// Web: www.anlogic.com
// --------------------------------------------------------------------
module camera_reader          //拼数据模块，把CAM输出的B拼成HW
(
	input 	wire 		clk,
	input 	wire 		reset_n,
	
	output 	wire 		csi_xclk,         //就是clk
	
	input 	wire 		csi_pclk,        //像素时钟，一个CLK读一个像素P
	input 	wire [7:0] 	csi_data,
	input 	wire 		csi_vsync,    //场同步信号，为1时表示正在读一个场的数据，为0时表示一个场的数据已经读完，换下一个场读
	input 	wire 		csi_hsync,    //行同步信号，为1时表示正在读一个行的数据，为0时表示一个行的数据已经读完，换下一个行读
	
	output 	reg  [15:0] data_out = 0,     
	output 	wire 		wrreq,       //WRITE_REQ向RAM发送写请求，在这个信号的上升沿给 data_out 赋值
	output 	wire 		wrclk,       //摄像机DATA写到RAM里的时钟，周期是csi_pclk的两倍
	output 	reg  [19:0]	wraddr         //写到RAM里的地址，0是屏幕左上角，从左到右，然后换行，换场
);

reg [19:0] pixel_counter = 0;        //数读了多少个像素
assign csi_xclk  = (reset_n == 1) ? clk : 0;         //csi_xclk就是clk
reg vsync_passed = 0;                //场通过信号，为1时表示通过1场
reg write_pixel  = 0;
reg [7:0] 	subpixel;     //低8位像素， pixel_counter[0] == 0,就是像素计数器是偶数时，先寄存一个周期，在下一个周期给current_pixe[7:0]赋值
reg [15:0] 	current_pixel;  //pixel_counter[0] == 1,就是像素计数器是奇数时，current_pixel <= { csi_data , subpixel }拼接输入和暂存的低8位
reg wrclk1 = 0;

always@(posedge csi_pclk)  //控制wrclk，周期是csi_pclk的两倍
begin
	wrclk1 <= ~wrclk1;
end

always@(negedge wrclk1)  //控制write_pixel
begin
	if(csi_hsync == 1)   //在行间时是1，把在写标志置1
		write_pixel <= 1;
	else
		write_pixel <= 0;
end

always@(posedge wrreq ) //给 data_out 赋值
begin
	data_out <= current_pixel;
end

always@(posedge csi_pclk or negedge reset_n)
begin
	if(reset_n == 0)    ///==============复位，只针对P计数器和内部的场通过信号
	begin
		pixel_counter <= 0;
		vsync_passed <= 0;
	end           //======================
	else
	begin
		if(csi_vsync == 1)  //===========读完一场，
		begin
			pixel_counter <= 0;             //数读了多少个像素，读数置零
			vsync_passed <= 1;              //场通过信号，为1时表示通过1场
			wraddr <= 0;                              //一场读完，地址归零从头写入
		end   //==========================
		else //描述场间的行为
			if(csi_hsync == 1 && vsync_passed == 1)//没有换场和行，
			begin
				if(pixel_counter[0] == 0)
				begin
					pixel_counter <= pixel_counter + 1;//低8位像素， pixel_counter[0] == 0,就是像素计数器是偶数时，先寄存一个周期，在下一个周期给current_pixe[7:0]赋值
					subpixel <= csi_data;
				end
				else
				begin
					//current_pixel <= { subpixel, csi_data };
					current_pixel <= { csi_data , subpixel };
					pixel_counter <= pixel_counter + 1; //pixel_counter[0] == 1,就是像素计数器是奇数时，current_pixel <= { csi_data , subpixel }拼接输入和暂存的低8位
					wraddr <= wraddr + 1;//数据拼完，输入的地址+1
				end
			end//=======没有换场和行，==============
			else
			begin//换行或换场时
				if(write_pixel == 1) //由于RAM写的时间周期是CAM的两倍，且是下降沿触发表示是否在写（write_pixel == 1表示正在写）确实不能全pixel_counter <= 0;
					pixel_counter <= pixel_counter + 1;
				else
					pixel_counter <= 0;
			end
	end//===========描述场间的行为结束=============
end

assign wrreq = (write_pixel == 1) && pixel_counter > 2 ? wrclk1 : 0; //在写标志是1时发送写请求
assign wrclk = ~csi_pclk;//~csi_pclk;

endmodule
