
module seg_decoder
(
	input[3:0]      bin_data,     // bin data input
	output reg[6:0] seg_data      // seven segments LED output
);

always@(*)
begin
	case(bin_data)
		4'd0:seg_data <= 7'b100_0000;  // 0
		4'd1:seg_data <= 7'b111_1001;  // 1
		4'd2:seg_data <= 7'b010_0100;  // 2
		4'd3:seg_data <= 7'b011_0000;  // 3
		4'd4:seg_data <= 7'b001_1001;  // 4
		4'd5:seg_data <= 7'b001_0010;  // 5
		4'd6:seg_data <= 7'b000_0010;  // 6
		4'd7:seg_data <= 7'b111_1000;  // 7
		4'd8:seg_data <= 7'b000_0000;  // 8
		4'd9:seg_data <= 7'b001_0000;  // 9
		4'ha:seg_data <= 7'b000_1000;  // A
		4'hb:seg_data <= 7'b000_0011;  // b
		4'hc:seg_data <= 7'b100_0110;  // C
		4'hd:seg_data <= 7'b010_0001;  // d
		4'he:seg_data <= 7'b000_0110;  // E
		4'hf:seg_data <= 7'b011_1111;  // 负号 "-" (只点亮中间横杠，即g段)
		default:seg_data <= 7'b111_1111;  // 全灭
	endcase
end
endmodule