module app (
    input                   	sys_clk		,
    input                   	udp_rx_clk	,
    input                   	udp_tx_clk	,
    input                   	reset		,

//udp2app signal    
    input               		app_rx_data_valid	,
    input  [7:0]         		app_rx_data			,
    input wire [15:0]        	app_rx_data_length	,
    input wire [15:0]        	app_rx_port_num		,
    

    output [11:0]              	VGA_D				,
    output                     	VGA_HSYNC			,
    output                     	VGA_VSYNC			,
    output                     	rd_en				,
	output   					VGA_EN
);
wire        wr_en;

reg       clk25M;
wire [23:0]  ram_data;
wire [23:0]  rgb;
wire [16:0] wr_addr;
wire [16:0] addr;
wire [23:0] ram_data_1;

always @(posedge sys_clk or negedge reset) begin
	if (!reset)
		clk25M <= 0;
	else
		clk25M <= ~clk25M;
end

addr_crt u_addr_crt(
 .      clk   (udp_rx_clk),
 .      rst_n  (reset),
 .      udp_data (app_rx_data),
 .      udp_vaild  (app_rx_data_valid),
 .      udp_length (app_rx_data_length),
 .      wr_addr (wr_addr),
 .      wr_en  (wr_en),
 .      rd_en  (rd_en),
 .      ram_data (ram_data)
);
assign ram_data_1=ram_data[23:0];
ram  u_ram (
	.dia   (ram_data_1	)	, 
	.addra (wr_addr)	, 
	.clka  (udp_rx_clk	)	,
	.dob	(rgb	)	, 
	.addrb (addr)	, 
	.clkb  (sys_clk ),
	.wea(wr_en),
	.cea(wr_en)
);
/*rom_bmp u_rom_bmp (
	.addra 	(addr),
	.clka 		(clk25M),
	.doa 			(rgb)
);*/
vga_disp_rtl u_vga_disp_rtl(
	.clk25M 	(sys_clk),
	.reset_n    (reset),
	.rgb		(rgb),
    //output
	.VGA_HSYNC	(VGA_HSYNC),
	.VGA_VSYNC	(VGA_VSYNC),
    .VGA_EN     (VGA_EN),
	.addr		(addr),
	.VGA_D		(VGA_D)
);
// vga_disp u_vga_disp(
// 	.	clk25M		(sys_clk),
// 	.	reset_n     (reset),
// 	.   rgb	        (rgb),
// 	.	VGA_HSYNC	(VGA_HSYNC),
// 	. 	VGA_VSYNC 	(VGA_VSYNC),
// 	.	addr        (addr),
// 	.   VGA_D       (VGA_D),
// 	.dis_en       (dis_en)
// );    
endmodule


