`timescale 1ns / 1ps

module seven_seg_static_display(
    input  wire [3:0] digit,
    output wire [3:0] seg_sel,
    output reg  [7:0] seg_data
);

    assign seg_sel = 4'b1110;

    always @* begin
        case (digit)
            4'd0: seg_data = 8'b1100_0000;
            4'd1: seg_data = 8'b1111_1001;
            4'd2: seg_data = 8'b1010_0100;
            4'd3: seg_data = 8'b1011_0000;
            4'd4: seg_data = 8'b1001_1001;
            4'd5: seg_data = 8'b1001_0010;
            4'd6: seg_data = 8'b1000_0010;
            4'd7: seg_data = 8'b1111_1000;
            4'd8: seg_data = 8'b1000_0000;
            4'd9: seg_data = 8'b1001_0000;
            default: seg_data = 8'b1111_1111;
        endcase
    end

endmodule
