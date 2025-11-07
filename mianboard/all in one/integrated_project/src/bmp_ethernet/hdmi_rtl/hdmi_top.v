module hdmi_top(   
		input   PXLCLK_I,
        input   PXLCLK_5X_I,
		input	RST_I,
        
		input   		DEN_TPG,
		input [3:0] 	TPG_mode,
		input			LOCKED_I,

		//HDMI
		output			HDMI_CLK_P,
		output			HDMI_D2_P,
		output			HDMI_D1_P,
		output			HDMI_D0_P,
		
		output			SERDES_CLK_TEST,
		output			SERDES_DATA1_TEST,
		output			SERDES_DATA2_TEST,
		
		output			ODDR_CLK_TEST,
		output			ODDR_DATA1_TEST,
		output			ODDR_DATA2_TEST,		
		
		output			VGA_HS,
		output			VGA_VS,
			
    	output [7:0]	VGA_R,		
		output [7:0]	VGA_G,		
		output [7:0]	VGA_B	
	);
wire [15:0]	       addr;
wire  			VGA_DE;
wire [11:0]        VGA_D;
	
	
assign VGA_R = {VGA_D[11:8],4'b0};	
assign VGA_G = {VGA_D[7:4],4'b0};
assign VGA_B = {VGA_D[3:0],4'b0};
/*
video_tpg_12801024p u2_tpg(   
		.PCLK(PXLCLK_I),
        .Reset(RST_I),
		.DEN_TPG(DEN_TPG),
		.TPG_mode(TPG_mode),
		.PDEN(VGA_DE),
        .HSYNC(VGA_HS),    
        .VSYNC(VGA_VS ), 
        .PDATA(VGA_RGB)
	);	
	*/

//color

//color to VGA_D
vga_disp_rtl u_vga_disp_rtl (
	.clk25M 	(PXLCLK_I),
	.reset_n    (RST_I),
	//.rgb		(rgb),
    //output
	.VGA_HSYNC	(VGA_HS),
	.VGA_VSYNC	(VGA_VS),
    .VGA_EN     (VGA_DE),
	//.addr		(addr),
	.VGA_D		(VGA_D)
);

hdmi_tx #(.FAMILY("EG4"))	//EF2、EF3、EG4、AL3、PH1

 u3_hdmi_tx
	(
		.PXLCLK_I(PXLCLK_I),
		.PXLCLK_5X_I(PXLCLK_5X_I),

		.RST_N (RST_I),
		
		//VGA
		.VGA_HS (VGA_HS ),
		.VGA_VS (VGA_VS ),
		.VGA_DE (VGA_DE ),
		.VGA_RGB({VGA_R,VGA_G,VGA_B}),

		//HDMI
		.HDMI_CLK_P(HDMI_CLK_P),
		.HDMI_D2_P (HDMI_D2_P ),
		.HDMI_D1_P (HDMI_D1_P ),
		.HDMI_D0_P (HDMI_D0_P )	
		
	);
	

endmodule

