// SD卡控制模块 - 封装sd_ctrl_top和sd_read_photo及相关逻辑
module sd_card_ctrl (
    input  wire        clk_50m,
    input  wire        clk_50m_180deg,
    input  wire        rst_n,
    input  wire        sd_miso,
    input  wire        sd_reset_rd,
    input  wire        cmd_sd_read_enable,
    input  wire        use_sd_data,
    input  wire        Sdr_init_done,
    
    output wire        sd_clk,
    output wire        sd_cs,
    output wire        sd_mosi,
    output wire        sd_init_done,
    output wire        sd_path_wr_en,
    output wire [23:0] sd_path_wr_data,
    output wire        full_flag_sdr,
    output wire        sd_rd_start_en,
    output wire [31:0] sd_rd_sec_addr,
    input  wire        sd_rd_busy,
    input  wire        sd_rd_val_en,
    input  wire [15:0] sd_rd_val_data
);

// 内部信号
wire        sd_card_clk;
wire        sd_reset_rd_flag;

// SD卡顶层控制模块
sd_ctrl_top u_sd_ctrl_top (
    .clk_ref        (clk_50m),
    .clk_ref_180deg (clk_50m_180deg),
    .rst_n          (rst_n),
    .sd_miso        (sd_miso),
    .sd_clk         (sd_card_clk),
    .sd_cs          (sd_cs),
    .sd_mosi        (sd_mosi),
    .rd_start_en    (sd_rd_start_en),
    .rd_sec_addr    (sd_rd_sec_addr),
    .rd_busy        (sd_rd_busy),
    .rd_val_en      (sd_rd_val_en),
    .rd_val_data    (sd_rd_val_data),
    .sd_init_done   (sd_init_done)
);

assign sd_clk = sd_card_clk;

// SD复位信号同步
reg sd_reset_rd_d0, sd_reset_rd_d1;
always @(posedge clk_50m or negedge rst_n) begin
    if (!rst_n) begin
        sd_reset_rd_d0 <= 1'b0;
        sd_reset_rd_d1 <= 1'b0;
    end else begin
        sd_reset_rd_d0 <= sd_reset_rd;
        sd_reset_rd_d1 <= sd_reset_rd_d0;
    end
end

// use_sd_data信号同步
reg use_sd_rst_d0, use_sd_rst_d1;
always @(posedge clk_50m or negedge rst_n) begin
    if (!rst_n) begin
        use_sd_rst_d0 <= 1'b0;
        use_sd_rst_d1 <= 1'b0;
    end else begin
        use_sd_rst_d0 <= use_sd_data;
        use_sd_rst_d1 <= use_sd_rst_d0;
    end
end

// SD复位门控逻辑
wire sd_reset_rd_gate = (use_sd_rst_d1 && {sd_reset_rd_d0, sd_reset_rd_d1} == 2'b10) ? 1'b0 : use_sd_rst_d1;
assign sd_reset_rd_flag = cmd_sd_read_enable ? sd_reset_rd_gate : 1'b0;

// SD卡读取照片模块
sd_read_photo u_sd_read_photo (
    .clk            (clk_50m),
    .rst_n          (rst_n & Sdr_init_done & sd_init_done & sd_reset_rd_flag),
    .ddr_max_addr   (24'd307200),
    .sd_sec_num     (16'd1801),
    .rd_busy        (sd_rd_busy),
    .sd_rd_val_en   (sd_rd_val_en),
    .sd_rd_val_data (sd_rd_val_data),
    .rd_start_en    (sd_rd_start_en),
    .rd_sec_addr    (sd_rd_sec_addr),
    .sdr_wr_en      (sd_path_wr_en),
    .sdr_wr_data    (sd_path_wr_data),
    .full_flag_sdr  (full_flag_sdr)
);

endmodule