module sdram_read_align (
    input             clk,
    input             rst_n,
    input             sdr_rd_en,
    input      [23:0] sdr_rd_dout,
    output reg        sdr_rd_en_aligned,
    output reg [7:0]  image_r,
    output reg [7:0]  image_g,
    output reg [7:0]  image_b
);

reg        sdr_rd_en_d1, sdr_rd_en_d2;
reg [23:0] sdr_rd_dout_d1, sdr_rd_dout_d2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sdr_rd_en_d1       <= 1'b0;
        sdr_rd_en_d2       <= 1'b0;
        sdr_rd_en_aligned  <= 1'b0;
        sdr_rd_dout_d1     <= 24'd0;
        sdr_rd_dout_d2     <= 24'd0;
        image_r            <= 8'd0;
        image_g            <= 8'd0;
        image_b            <= 8'd0;
    end else begin
        sdr_rd_en_d1       <= sdr_rd_en;
        sdr_rd_en_d2       <= sdr_rd_en_d1;
        sdr_rd_en_aligned  <= sdr_rd_en_d2;

        sdr_rd_dout_d1     <= sdr_rd_dout;
        sdr_rd_dout_d2     <= sdr_rd_dout_d1;
        
        image_r            <= sdr_rd_dout_d2[23:16];
        image_g            <= sdr_rd_dout_d2[15:8];
        image_b            <= sdr_rd_dout_d2[7:0];
    end
end

endmodule
