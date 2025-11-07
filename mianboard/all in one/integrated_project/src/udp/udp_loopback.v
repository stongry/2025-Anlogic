`timescale 1ns / 1ps
//********************************************************************** 
// -------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>Copyright Notice<<<<<<<<<<<<<<<<<<<<<<<<<<<< 
// ------------------------------------------------------------------- 
//             /\ --------------- 
//            /  \ ------------- 
//           / /\ \ -----------
//          / /  \ \ ---------
//         / /    \ \ ------- 
//        / /      \ \ ----- 
//       / /_ _ _   \ \ --- 
//      /_ _ _ _ _\  \_\ -
//*********************************************************************** 
// Author: suluyang 
// Email:luyang.su@anlogic.com 
// Date:2020/10/26 
// Description: 
// 
// web：www.anlogic.com 
//------------------------------------------------------------------- 
//*********************************************************************/
module udp_loopback(

input   wire		app_rx_clk		   ,
input   wire		app_tx_clk		   ,
input   wire		reset              ,
input   wire [7:0]	app_rx_data        ,
input   wire		app_rx_data_valid  ,
input   wire [15:0] app_rx_data_length ,
			
input   wire		udp_tx_ready       ,
input   wire		app_tx_ack         ,
output  wire  [7:0] app_tx_data        ,
output	reg  		app_tx_data_request,
output	reg  		app_tx_data_valid  ,
output  reg  [15:0]	udp_data_length	   
			
);
parameter  			 	DEVICE            = "EG4";//"PH1","EG4"

reg         app_tx_data_read;
wire [11:0] udp_packet_fifo_data_cnt;
reg  [15:0] fifo_read_data_cnt;
reg  [15:0] udp_data_length_reg_ff1;
reg  [15:0] udp_data_length_reg_ff2;
wire [7:0]  app_tx_data_reg;




assign app_tx_data = app_tx_data_reg;

reg [1:0]   STATE;
localparam  WAIT_UDP_DATA   = 2'd0;
localparam  WAIT_ACK        = 2'd1;
localparam  SEND_UDP_DATA   = 2'd2;
localparam  DELAY           = 2'd3;

// assign udp_packet_fifo_data_cnt = 1;



ram_fifo#
(
	.DEVICE       	(DEVICE       	),//"PH1","EG4","SF1","EF2","EF3","AL"
	.DATA_WIDTH_W 	(8 				),//写数据位宽
	.ADDR_WIDTH_W 	(12 			),//写地址位宽
	.DATA_WIDTH_R 	(8 				),//读数据位宽
	.ADDR_WIDTH_R 	(12 			),//读地址位宽
	.SHOW_AHEAD_EN	(1				)//普通/SHOWAHEAD模式
)
udp_packet_fifo
(
	.rst			(reset				), 
	.di				(app_rx_data		), 
	.clkw			(app_rx_clk			), 
	.we				(app_rx_data_valid	),
	.clkr			(app_tx_clk			), 
	.re				(app_tx_data_read	), 
	.do				(app_tx_data_reg	), 
	.empty_flag		(					), 
	.full_flag		(					), 
	.wrusedw		(					), 
	.rdusedw		(udp_packet_fifo_data_cnt)
);



always@(posedge app_tx_clk or posedge reset)
begin
	if(reset) begin
		udp_data_length_reg_ff1 <= 16'd0;
		udp_data_length_reg_ff2 <= 16'd0;
	end	
	else if(app_rx_data_valid)
	begin 
		udp_data_length_reg_ff1 <= app_rx_data_length;
		udp_data_length_reg_ff2 <= udp_data_length_reg_ff1;
	end
end

always@(posedge app_tx_clk or posedge reset)
begin
	if(reset) begin
		app_tx_data_request <= 1'b0;
		app_tx_data_read 	<= 1'b0;
		app_tx_data_valid 	<= 1'b0;
		fifo_read_data_cnt 	<= 16'd0;
		udp_data_length 	<= 16'd0;
		STATE 				<= WAIT_UDP_DATA;
	end
	else begin
	   case(STATE)
			WAIT_UDP_DATA: // 0
				begin
					if((udp_packet_fifo_data_cnt > 12'd0) && (~app_rx_data_valid) && udp_tx_ready) begin
						app_tx_data_request <= 1'b1;
						STATE 				<= WAIT_ACK;
					end
					else begin
						app_tx_data_request <= 1'b0;
						STATE 				<= WAIT_UDP_DATA;
					end
				end
			WAIT_ACK: // 1
				begin
				   if(app_tx_ack) begin
						app_tx_data_request <= 1'b0;
						app_tx_data_read 	<= 1'b1;
						app_tx_data_valid 	<= 1'b1;
						udp_data_length 	<= udp_data_length_reg_ff2;//
						STATE 				<= SEND_UDP_DATA;
					end
					else begin
						app_tx_data_request <= 1'b1;
						app_tx_data_read	<= 1'b0;
						app_tx_data_valid 	<= 1'b0;
						udp_data_length 	<= 16'd0;
						STATE 				<= WAIT_ACK;
					end
				end
			SEND_UDP_DATA: // 2
				begin
					if(fifo_read_data_cnt == (udp_data_length_reg_ff2 - 1'b1)) begin
						fifo_read_data_cnt 	<= 16'd0;
						app_tx_data_valid 	<= 1'b0;
						app_tx_data_read 	<= 1'b0;
						STATE 				<= WAIT_UDP_DATA;
					end
					else begin
						fifo_read_data_cnt 	<= fifo_read_data_cnt + 1'b1;
						app_tx_data_valid  	<= 1'b1;
						app_tx_data_read 	<= 1'b1;
						STATE 				<= SEND_UDP_DATA;
					end						
				end
			DELAY:
				begin
					if(app_rx_data_valid)
						STATE 	<= WAIT_UDP_DATA;
					else
						STATE 	<= DELAY;
				end
			default: STATE 		<= WAIT_UDP_DATA;
		endcase
	end
end

endmodule
