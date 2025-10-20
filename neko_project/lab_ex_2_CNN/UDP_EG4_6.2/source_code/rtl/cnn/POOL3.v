module POOL3( 
	input	 clk ,
	input	 rst  , 
	input signed	[15:0]	data_in ,	  
	input 	 start	,
	output reg signed	[15:0]data_out	,
	output 	 ready
);
 
  wire [7:0] G1_VGA_R, G1_VGA_G, G1_VGA_B;
  wire [7:0] data_out1_R,data_out1_G,data_out1_B;
  wire ready_R,ready_G,ready_B;
  //wire ready_fft1;//比ready快一个周期
  assign  ready = ready_R && ready_G && ready_B ;
  assign G1_VGA_R[7:0]  	=  { data_in[15:11] , data_in[13:11] } ;
  assign G1_VGA_G[7:0]   	=  { data_in[10:5]   , data_in[6:5]     } ;
  assign G1_VGA_B[7:0]     =  { data_in[4:0]     , data_in[2:0]     }  ;
  //assign data_out[15:0]       =  {data_out1_R[7:3],data_out1_G[7:2],data_out1_B[7:3]};
 always @(posedge clk )begin
 data_out[15:0]    <=  { data_out1_R[7:3] , data_out1_G[7:2] , data_out1_B[7:3] } ;
// ready <=ready_fft1;
 end



POOL_CORE 
 #(
    . bits(8),
    . filter_size(4),
    . filter_size_2 (2)
)
  POOL_CORE_R(
       .clk_in( clk),
	 .rst_n(rst), 
	 //IN
	 .data_in(G1_VGA_R),	
     .start(start),
	//deature map output 
	.data_out( data_out1_R ),  
	//enable next module
	.ready(ready_R)
	);  
    
    
    
    
    POOL_CORE 
 #(
    . bits(8),
    . filter_size(4),
    . filter_size_2 (2)
)
  POOL_CORE_G(
       .clk_in( clk),
	 .rst_n(rst), 
	 //IN
     .data_in(G1_VGA_G),	
     .start(start),
	//deature map output 
	.data_out( data_out1_G ),  
	//enable next module
	.ready(ready_G)
	); 
    
    
    
     
    POOL_CORE 
 #(
    . bits(8),
    . filter_size(4),
    . filter_size_2 (2)
)
  POOL_CORE_B(
        .clk_in( clk),
	 .rst_n(rst), 
	 //IN
	 .data_in(G1_VGA_B),	
     .start(start),
	//deature map output 
	.data_out( data_out1_B ),  
	//enable next module
	.ready(ready_B)
	);  
endmodule
