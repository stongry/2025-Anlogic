module auto_created_cwc2 (  
    cwc_rst, cwc_control, cwc_status, cwc_trig_clk, cwc_bus_din, ram_data_din
);

    localparam CWC_BUS_NUM = 12;
    localparam CWC_BUS_DIN_NUM = 54;
	localparam CWC_CTRL_LEN = 212;
	localparam CWC_BUS_CTRL_LEN = 192;
    localparam RAM_LEN = 54;
    localparam INPUT_PIPE_NUM = 0;
    localparam OUTPUT_PIPE_NUM = 0;
    localparam RAM_DATA_DEPTH = 1024;
	localparam CWC_CAPTURE_CTRL_EXIST = 0;
    localparam integer CWC_BUS_WIDTH[0:11] = {1,1,1,8,8,8,1,8,1,8,8,1};
    localparam integer CWC_BUS_DIN_POS[0:11] = {0,1,2,3,11,19,27,28,36,37,45,53};    
    localparam integer CWC_BUS_CTRL_POS[0:11] = {0,4,8,12,40,68,96,100,128,132,160,188};    

    input                                            cwc_rst;       
    input  [CWC_CTRL_LEN-1:0]                        cwc_control;   
    output [23:0]                                    cwc_status;    //cwc status register 
    input                                            cwc_trig_clk;  //cwc trigger clock
    input  [CWC_BUS_DIN_NUM-1:0]                     cwc_bus_din;   //cwc trigger bus input
    input  [RAM_LEN-1:0]                             ram_data_din;

	top_cwc_hub #(
		.CWC_BUS_NUM(CWC_BUS_NUM),
		.CWC_BUS_DIN_NUM(CWC_BUS_DIN_NUM),
		.CWC_CTRL_LEN(CWC_CTRL_LEN),
		.CWC_BUS_CTRL_LEN(CWC_BUS_CTRL_LEN),
		.CWC_BUS_WIDTH(CWC_BUS_WIDTH),
		.CWC_BUS_DIN_POS(CWC_BUS_DIN_POS),
		.CWC_BUS_CTRL_POS(CWC_BUS_CTRL_POS),
		.RAM_DATA_DEPTH(RAM_DATA_DEPTH),
		.CWC_CAPTURE_CTRL_EXIST(CWC_CAPTURE_CTRL_EXIST),
		.RAM_LEN(RAM_LEN),  
        .INPUT_PIPE_NUM(INPUT_PIPE_NUM),
		.OUTPUT_PIPE_NUM(OUTPUT_PIPE_NUM)
	)

	wrapper_cwc_top(
		.cwc_trig_clk(cwc_trig_clk),
		.cwc_control(cwc_control),
		.cwc_status(cwc_status),
		.cwc_rst(cwc_rst),
		.cwc_bus_din(cwc_bus_din),
		.ram_data_din(ram_data_din)
	);

endmodule


