module cam_data(
    input           clk,
    input           reset,
    input  [23:0]   cam_data,
    output reg [7:0]  udp_data,
    output reg [15:0] udp_data_length
);

localparam [31:0] FRAME_HEADER = 32'hAA55AA55;
localparam [15:0] TOTAL_BYTES  = 16'd7; // 4 bytes header + 3 bytes RGB

reg [2:0]  byte_sel;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        byte_sel         <= 3'd0;
        udp_data         <= 8'd0;
        udp_data_length  <= TOTAL_BYTES;
    end else begin
        udp_data_length <= TOTAL_BYTES;
        case (byte_sel)
            3'd0: udp_data <= FRAME_HEADER[31:24];
            3'd1: udp_data <= FRAME_HEADER[23:16];
            3'd2: udp_data <= FRAME_HEADER[15:8];
            3'd3: udp_data <= FRAME_HEADER[7:0];
            3'd4: udp_data <= cam_data[23:16];
            3'd5: udp_data <= cam_data[15:8];
            default: udp_data <= cam_data[7:0];
        endcase

        if (byte_sel == 3'd6)
            byte_sel <= 3'd0;
        else
            byte_sel <= byte_sel + 3'd1;
    end
end

endmodule
