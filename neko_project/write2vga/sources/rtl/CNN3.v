`timescale 1ns/ 1ps
module CNN3( 
	input		 						clk_in ,
	input								rst_n , 
	input signed	[15:0]	data_in ,	  
	input 	 start	,
	output reg signed	[15:0]data_out	,
	output 	 ready
 );


  wire [7:0] G1_VGA_R, G1_VGA_G, G1_VGA_B;
  wire [7:0] data_out1_R,data_out1_G,data_out1_B;
  wire ready_R,ready_G,ready_B;
  assign ready = ready_R && ready_G && ready_B ;
  assign G1_VGA_R[7:0]  	=  { data_in[15:11] , data_in[13:11] } ;
  assign G1_VGA_G[7:0]   	=  { data_in[10:5]   , data_in[6:5]     } ;
  assign G1_VGA_B[7:0]     =  { data_in[4:0]     , data_in[2:0]     }  ;
  //assign data_out[15:0]       =  {data_out1_R[7:3],data_out1_G[7:2],data_out1_B[7:3]};
 always @(posedge clk_in)begin
 data_out[15:0]    <=  { data_out1_R[7:3] , data_out1_G[7:2] , data_out1_B[7:3] } ;
 end



 CNN_L1_221009
 #(
	.bits(8),
    . filter_size(9),
    .filter_size_2 (4)
)
  CNN_L1_221009_R(
     .clk_in( clk_in),
	 .rst_n(rst_n), 
	 //IN
	 .data_in(G1_VGA_R),	//[7:0]
     .start(start),
	//deature map output 
	.data_out( data_out1_R ),   //[21:0]
	//enable next module
	.ready(ready_R)
	);   
    
     CNN_L1_221009
 #(
	.bits(8),
    . filter_size(9),
    .filter_size_2 (4)
)
  CNN_L1_221009_G(
     .clk_in( clk_in),
	 .rst_n(rst_n), 
	 //IN
	 .data_in(G1_VGA_G),	//[7:0]
     .start(start),
	//deature map output 
	.data_out( data_out1_G ),   //[21:0]
	//enable next module
	.ready(ready_G)
	);  
    
    CNN_L1_221009
 #(
	.bits(8),
    . filter_size(9),
    .filter_size_2 (4)
)
  CNN_L1_221009_B(
     .clk_in( clk_in),
	 .rst_n(rst_n), 
	 //IN
	 .data_in(G1_VGA_B),	//[7:0]
     .start(start),
	//deature map output 
	.data_out( data_out1_B ),   //[21:0]
	//enable next module
	.ready(ready_B)
	);   


endmodule
