module vga_disp_rtl	
(
	input					clk25M,
	input					reset_n,
    output                 VGA_EN,
	output 				VGA_HSYNC,
	output 				VGA_VSYNC,
	input[23:0]  rgb,
	output [12:0]addr ,

	output reg [11:0] VGA_D
);		
wire dis_en;
reg  [9:0]		hcnt	;
reg  [9:0]		vcnt	;		
reg				hs		;	
reg   			vs		;


localparam integer FRAME_WIDTH  = 80;
localparam integer FRAME_HEIGHT = 100;
localparam integer X_OFFSET     = 16;
localparam integer Y_OFFSET     = 10;

wire [9:0] 		x     ;
wire [9:0] 		y     ;
wire [6:0] 		x_reg     ;
wire [6:0] 		y_reg     ;
wire 				x_in_range;
wire 				y_in_range;
wire [13:0] y_times_width;
wire [13:0] pixel_addr_full;
assign x = hcnt;
assign y = vcnt;
assign x_in_range = (x >= X_OFFSET) && (x < X_OFFSET + FRAME_WIDTH);
assign y_in_range = (y >= Y_OFFSET) && (y < Y_OFFSET + FRAME_HEIGHT);
assign x_reg = x_in_range ? x - X_OFFSET : 7'd0;
assign y_reg = y_in_range ? y - Y_OFFSET : 7'd0;
assign y_times_width = y_reg * 7'd80;
assign pixel_addr_full = y_times_width + x_reg;
assign addr = pixel_addr_full[12:0];
assign VGA_VSYNC = vs;
assign VGA_HSYNC = hs;
assign dis_en = x_in_range && y_in_range;
assign VGA_EN  = (((hcnt >= 8+8) && (hcnt < 8+8+640))
                 &&((vcnt >= 8+2) && (vcnt < 8+2+480)))
                 ?  1'b1 : 1'b0;


			
always @(posedge clk25M or negedge reset_n) begin			//水平扫描计数器
	if(!reset_n)
		hcnt <= 1'b0;
	else begin
		if (hcnt < 800)
			hcnt <= hcnt + 1'b1;
		else
			hcnt <= 1'b1;
	end
end
			
always @(posedge clk25M or negedge reset_n) begin			//垂直扫描计数器
	if(!reset_n)
		vcnt <= 1'b0;
	else begin
		if (hcnt == 800) begin
			if (vcnt < 10'd525)
				vcnt <= vcnt +1'b1;
			else
				vcnt <= 1'b1;
		end
	end
end
			
always @(posedge clk25M or negedge reset_n) begin			//场同步信号发生
	if(!reset_n)
		hs	<=	1'b1;
	else begin
		if((hcnt >= 640+8+8) & (hcnt < 640+8+8+96))
			hs <= 1'b0;
		else
			hs <= 1'b1;
	end
end
			
always @(vcnt or reset_n) begin							//行同步信号发生
	if(!reset_n)
		vs	<=	1'b1;
	else begin
		if((vcnt >= 480+8+2) && (vcnt < 480+8+2+2))
			vs	<=	1'b0;
		else
			vs	<=	1'b1;
	end
end
			
always @(posedge clk25M or negedge reset_n) begin
	if(!reset_n)
		VGA_D <= 1'b0;
	else begin
		if (VGA_EN && dis_en)	begin	//扫描终止
			VGA_D[11:8] <=  rgb[23:20];
			VGA_D[ 7:4] <=  rgb[15:12];
			VGA_D[ 3:0] <= rgb[7:4];
		end
		else begin
			VGA_D <= 0;
		end
	end
end


// reg  [9:0]		hcnt	;
// reg  [9:0]		vcnt	;		
// reg				hs		;	
// reg   			vs		;


// wire [2:0]  	rgb	;
// wire [9:0] 		x     ;
// wire [9:0] 		y     ;
// wire 				dis_en;

// assign x = hcnt;
// assign y = vcnt;
// assign VGA_VSYNC = vs;
// assign VGA_HSYNC = hs;
// assign dis_en = (x<10'd640 && y<10'd480);
// assign rgb = x[8:6]^y[8:6];
// assign VGA_EN  = (((hcnt >= 8+8) && (hcnt < 8+8+640))
//                  &&((vcnt >= 8+2) && (vcnt < 8+2+480)))
//                  ?  1'b1 : 1'b0;


			
// always @(posedge clk25M or negedge reset_n) begin			//水平扫描计数器
// 	if(!reset_n)
// 		hcnt <= 1'b0;
// 	else begin
// 		if (hcnt < 800)
// 			hcnt <= hcnt + 1'b1;
// 		else
// 			hcnt <= 1'b1;
// 	end
// end
			
// always @(posedge clk25M or negedge reset_n) begin			//垂直扫描计数器
// 	if(!reset_n)
// 		vcnt <= 1'b0;
// 	else begin
// 		if (hcnt == 800) begin
// 			if (vcnt < 10'd525)
// 				vcnt <= vcnt +1'b1;
// 			else
// 				vcnt <= 1'b1;
// 		end
// 	end
// end
			
// always @(posedge clk25M or negedge reset_n) begin			//场同步信号发生
// 	if(!reset_n)
// 		hs	<=	1'b1;
// 	else begin
// 		if((hcnt >= 640+8+8) & (hcnt < 640+8+8+96))
// 			hs <= 1'b0;
// 		else
// 			hs <= 1'b1;
// 	end
// end
			
// always @(vcnt or reset_n) begin							//行同步信号发生
// 	if(!reset_n)
// 		vs	<=	1'b1;
// 	else begin
// 		if((vcnt >= 480+8+2) && (vcnt < 480+8+2+2))
// 			vs	<=	1'b0;
// 		else
// 			vs	<=	1'b1;
// 	end
// end
			
// always @(posedge clk25M or negedge reset_n) begin
// 	if(!reset_n)
// 		VGA_D <= 1'b0;
// 	else begin
// 		if (hcnt < 10'd640 & vcnt < 10'd480 && dis_en)	begin	//扫描终止
// 			VGA_D[11:8] <= 1111;
// 			VGA_D[ 7:4] <= 0;
// 			VGA_D[ 3:0] <= 1111;
// 		end
// 		else begin
// 			VGA_D <= 0;
// 		end
// 	end
// end
endmodule 
