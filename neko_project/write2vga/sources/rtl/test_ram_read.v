`timescale 1ns/ 1ps
module test_ram_read();
      parameter                    clk_lcd_period=10;//时钟周期
      //clk_lcd&reg
    reg          clk_lcd ,rst_n   ,clk_lcd_div;
   
   
    reg signed[11:0]test1,add1,add2;
    reg signed[7:0]test2;
    wire  signed[11:0]test3;
    
/*       //IN
 reg [7:0]YUAN[0:783] ;
 
 //=============================
wire Y_ren ,ren_Y748,layer_ren, layer_ren_conv2_layer   ;
reg [7:0]pre_dob;
wire [8:0]pre_addrb;
wire [9:0]pre_ram_raddr;
wire signed[11:0]data_in1_conv2_layer;
wire [10:0]ram_raddr_conv2_layer;
wire Y_ren_conv2_layer;   
wire signed[11:0] in_full_layer;
wire [3:0]out_full_layer ;
wire [6:0]raddr_full_layer ;
wire Y_ren_full_layer;

//===========
 initial begin                                               //这里路径要对  //$readmemh ("<数据文件名>",<数组名>,<起始地址>,<结束地址>)
   $readmemh("D:/YJS_TCL_FPGA/22_11_1_py_test/CNN-Implementation-in-Verilog-master/CNN-Implementation-in-Verilog-master/pyTorch/mnist_cnn/mnist_input/0_29.txt", YUAN);   
 end
// Read image text file
initial begin
  $readmemh("D:/YJS_TCL_FPGA/22_11_1_py_test/CNN-Implementation-in-Verilog-master/CNN-Implementation-in-Verilog-master/pyTorch/mnist_cnn/mnist_input/0_21.txt", pixels);
end
*/
initial
begin    
// Initialize Inputs
  clk_lcd = 1'b1;
  clk_lcd_div=1'b1;
  rst_n = 1'b0;
  
  test1 = 12'd20 ;
  test2 = 8'b0 ;
  
 //data_in = 0;   
// addr_in = 0;   
// Wait 100 ns for global reset to finish
  #100;
   rst_n= 1'b1; 
  #700;
   
  clk_lcd_div=1'b0;

end

always    #(clk_lcd_period/2)  clk_lcd = ~clk_lcd; //时钟
 
always    #1000000   clk_lcd_div=  ~clk_lcd_div;
 
 
 
/* 
always@(posedge clk_lcd)begin
if(rst_n == 1'b1 && addr_in != 748) begin 
data_in <= data_in + 1'b1;
addr_in <= addr_in + 1'b1;
end
else begin
data_in <= data_in;
addr_in <= addr_in;
end
end
//*/ /*
 //===========读pre_layer/addrb 
 always@( posedge clk_lcd )begin
 pre_dob <= YUAN[pre_ram_raddr] ;
end
//=================cnn_layers==


 conv1_layer1  u_conv1_layer( 
.clk(  clk_lcd  ),
.rst_n( rst_n ),
.ren_Y748( clk_lcd_div )   ,  //开始信号，下降沿开始
.data_in( pre_dob ),
.raddr( pre_ram_raddr ) ,    //读原图的地址 
.Y_ren( Y_ren ),              //原图读使能
.layer_ren( layer_ren ),
 
.ram_addrb( ram_raddr_conv2_layer ),
.ram_dob( data_in1_conv2_layer  ),      
.ram_ceb( Y_ren_conv2_layer )
);
    
conv2_layer2  u_conv2_layer( 
.clk( clk_lcd ),
.rst_n(  rst_n ),
.ren_Y748( layer_ren )   ,  //开始信号，下降沿开始
.data_in( data_in1_conv2_layer ),
.raddr( ram_raddr_conv2_layer ) ,    //读原图的地址 
.Y_ren( Y_ren_conv2_layer ),              //原图读使能
.layer_ren(  layer_ren_conv2_layer  ),

.ram_addrb( raddr_full_layer ),
.ram_dob( in_full_layer  ),      
.ram_ceb( Y_ren_full_layer )
);

 full_layer  u_full_layer( 
.clk( clk_lcd ),
.rst_n(  rst_n ),
.layer_ren( layer_ren_conv2_layer ) ,   //收到此信号下降沿开始读
.data_in( in_full_layer ),
.data_out( out_full_layer  ),              //输出0-9

.raddr( raddr_full_layer ),
.read_flag( Y_ren_full_layer )
);
 
///==================
 /*reg [7:0] pixels [0:783];
reg [9:0] img_idx;
reg [7:0] data_in;

wire signed [11:0] conv_out_1, conv_out_2, conv_out_3;
wire signed [11:0] conv2_out_1, conv2_out_2, conv2_out_3;
wire signed [11:0] max_value_1, max_value_2, max_value_3;
wire signed [11:0] max2_value_1, max2_value_2, max2_value_3;
wire signed [11:0] fc_out_data;

wire [3:0] decision;

wire valid_out_1, valid_out_2, valid_out_3, valid_out_4, valid_out_5, valid_out_6;

// Module Instantiation
conv1_layer conv1_layer(
  .clk(clk_lcd),
  .rst_n(rst_n),
  .data_in(data_in),
  .conv_out_1(conv_out_1),
  .conv_out_2(conv_out_2),
  .conv_out_3(conv_out_3),
  .valid_out_conv(valid_out_1)
);

maxpool_relu #(.CONV_BIT(12), .HALF_WIDTH(12), .HALF_HEIGHT(12), .HALF_WIDTH_BIT(4))
maxpool_relu_1(
  .clk(clk_lcd),
  .rst_n(rst_n),
  .valid_in(valid_out_1),
  .conv_out_1(conv_out_1),
  .conv_out_2(conv_out_2),
  .conv_out_3(conv_out_3),
  .max_value_1(max_value_1),
  .max_value_2(max_value_2),
  .max_value_3(max_value_3),
  .valid_out_relu(valid_out_2)
);

conv2_layer conv2_layer(
  .clk(clk_lcd),
  .rst_n(rst_n),
  .valid_in(valid_out_2),
  .max_value_1(max_value_1),
  .max_value_2(max_value_2),
  .max_value_3(max_value_3),
  .conv2_out_1(conv2_out_1),
  .conv2_out_2(conv2_out_2),
  .conv2_out_3(conv2_out_3),
  .valid_out_conv2(valid_out_3)
);

maxpool_relu #(.CONV_BIT(12), .HALF_WIDTH(4), .HALF_HEIGHT(4), .HALF_WIDTH_BIT(3))
maxpool_relu_2(
  .clk(clk_lcd),
  .rst_n(rst_n),
  .valid_in(valid_out_3),
  .conv_out_1(conv2_out_1),
  .conv_out_2(conv2_out_2),
  .conv_out_3(conv2_out_3),
  .max_value_1(max2_value_1),
  .max_value_2(max2_value_2),
  .max_value_3(max2_value_3),
  .valid_out_relu(valid_out_4)
);

fully_connected #(.INPUT_NUM(48), .OUTPUT_NUM(10), .DATA_BITS(8))
fully_connected(
  .clk(clk_lcd),
  .rst_n(rst_n),
  .valid_in(valid_out_4),
  .data_in_1(max2_value_1),
  .data_in_2(max2_value_2),
  .data_in_3(max2_value_3),
  .data_out(fc_out_data),
  .valid_out_fc(valid_out_5)
);

comparator comparator(
  .clk(clk_lcd),
  .rst_n(rst_n),
  .valid_in(valid_out_5),
  .data_in(fc_out_data),
  .decision(decision),
  .valid_out(valid_out_6)
);

// Clock generation
 



always @(posedge  clk_lcd) begin
  if(~rst_n) begin
    img_idx <= 0;
  end else begin
    if(img_idx < 10'd784) begin
      img_idx <= img_idx + 1'b1;
    end
    data_in <= pixels[img_idx];
  end
end  */
//=============================
assign test3 = (test2[7] == 1) ? {4'b1111, test2} : {4'b0000, test2};
always@( posedge  clk_lcd )begin
    test2 <= test2 + 1;
    add1 <= test1 + test2 ;
    add2 <= test1 + test3 ;
end





endmodule
