module vga_disp_rtl
(
	input					clk25M,
	input					reset_n,
	input	[23:0]			rgb,
    output                 VGA_EN,
	output 				VGA_HSYNC,
	output 				VGA_VSYNC,
	output	[12:0]			addr,
	output reg [11:0] VGA_D
);

reg  [9:0]		hcnt	;
reg  [9:0]		vcnt	;
reg				hs		;
reg   			vs		;


wire [2:0]  	rgb_test	;
wire [9:0] 		x     ;
wire [9:0] 		y     ;
wire 				dis_en;

assign x = hcnt;
assign y = vcnt;
assign VGA_VSYNC = vs;
assign VGA_HSYNC = hs;
assign dis_en = (x<10'd640 && y<10'd480);
assign rgb_test = x[8:6]^y[8:6];

// Address generation for 80x100 image
assign addr = (x < 10'd80 && y < 10'd100) ? (y * 10'd80 + x) : 13'd0;

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
		if (hcnt < 10'd80 & vcnt < 10'd100 && dis_en)	begin
			// Display 80x100 image from RAM in top-left corner
			VGA_D[11:8] <= rgb[23:20];
			VGA_D[ 7:4] <= rgb[15:12];
			VGA_D[ 3:0] <= rgb[ 7: 4];
		end
		else if (hcnt < 10'd640 & vcnt < 10'd480 && dis_en)	begin
			// Rest of screen - white background
			VGA_D[11:8] <= 4'hf;
			VGA_D[ 7:4] <= 4'hf;
			VGA_D[ 3:0] <= 4'hf;
		end
		else begin
			VGA_D <= 1'b0;
		end
	end
end

endmodule
