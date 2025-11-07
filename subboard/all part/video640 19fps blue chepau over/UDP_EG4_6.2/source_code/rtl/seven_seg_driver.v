`timescale 1ns / 1ps

module seven_seg_driver #(
    parameter integer REFRESH_DIV = 16'd5000  // adjust to suit display refresh
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  digit0,
    input  wire [3:0]  digit1,
    input  wire [3:0]  digit2,
    input  wire [3:0]  digit3,
    input  wire [3:0]  digit4,
    output reg  [6:0]  seg_data,
    output reg  [4:0]  seg_sel
);
    reg [15:0] refresh_cnt;
    reg [2:0]  active_digit;
    reg [3:0]  current_value;

    localparam [6:0] SEG_OFF = 7'b1111111;

    function automatic [6:0] encode_digit;
        input [3:0] value;
        begin
            case (value)
                4'd0: encode_digit = 7'b1000000;
                4'd1: encode_digit = 7'b1111001;
                4'd2: encode_digit = 7'b0100100;
                4'd3: encode_digit = 7'b0110000;
                4'd4: encode_digit = 7'b0011001;
                4'd5: encode_digit = 7'b0010010;
                4'd6: encode_digit = 7'b0000010;
                4'd7: encode_digit = 7'b1111000;
                4'd8: encode_digit = 7'b0000000;
                4'd9: encode_digit = 7'b0010000;
                default: encode_digit = SEG_OFF;
            endcase
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            refresh_cnt  <= 16'd0;
            active_digit <= 3'd0;
            seg_sel      <= 5'b11111;
            seg_data     <= SEG_OFF;
        end else begin
            if (refresh_cnt >= REFRESH_DIV) begin
                refresh_cnt  <= 16'd0;
                if (active_digit == 3'd4)
                    active_digit <= 3'd0;
                else
                    active_digit <= active_digit + 3'd1;
            end else begin
                refresh_cnt <= refresh_cnt + 16'd1;
            end

            case (active_digit)
                3'd0: current_value = digit0;
                3'd1: current_value = digit1;
                3'd2: current_value = digit2;
                3'd3: current_value = digit3;
                3'd4: current_value = digit4;
                default: current_value = 4'hF;
            endcase

            seg_data <= encode_digit(current_value);
            seg_sel  <= ~(5'b00001 << active_digit);
        end
    end
endmodule
