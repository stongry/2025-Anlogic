`timescale 1ns/ 1ps
module output_layer( 
input clk,
input rst_n,
input [3:0]nub,
input [9:0]raddr,
output reg [7:0]TX
);
//============reg0-9
reg [7:0]T0[0:783] ;
reg [7:0]T1[0:783] ;
reg [7:0]T2[0:783] ;
reg [7:0]T3[0:783] ;
reg [7:0]T4[0:783] ;
reg [7:0]T5[0:783] ;
reg [7:0]T6[0:783] ;
reg [7:0]T7[0:783] ;
reg [7:0]T8[0:783] ;
reg [7:0]T9[0:783] ;
 initial begin                                               //这里路径要对  //$readmemh ("<数据文件名>",<数组名>,<起始地址>,<结束地址>)
   $readmemh("../../data/mnist_input/0_20.txt", T0);
   $readmemh("../../data/mnist_input/0_21.txt", T1);
   $readmemh("../../data/mnist_input/0_22.txt", T2);
   $readmemh("../../data/mnist_input/0_23.txt", T3);
   $readmemh("../../data/mnist_input/0_24.txt", T4);
   $readmemh("../../data/mnist_input/0_25.txt", T5);
   $readmemh("../../data/mnist_input/0_26.txt", T6);
   $readmemh("../../data/mnist_input/0_27.txt", T7);
   $readmemh("../../data/mnist_input/0_28.txt", T8);
   $readmemh("../../data/mnist_input/0_29.txt", T9);
 end
always@(posedge clk or negedge rst_n )begin
    if( rst_n == 1'b0 )begin
        TX <= 8'b0 ;
    end
    else begin
        case( nub )
            0: TX <= T0[raddr] ;
            1: TX <= T1[raddr] ;
            2: TX <= T2[raddr] ;
            3: TX <= T3[raddr] ;
            4: TX <= T4[raddr] ;
            5: TX <= T5[raddr] ;
            6: TX <= T6[raddr] ;
            7: TX <= T7[raddr] ;
            8: TX <= T8[raddr] ;
            9: TX <= T9[raddr] ;
            default : TX <= 8'b0 ;
        endcase 
    end 
end

endmodule
