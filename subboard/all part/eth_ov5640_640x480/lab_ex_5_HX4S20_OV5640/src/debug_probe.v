// ============================================================================
// Debug Probe Module
// 用于逻辑分析仪调试的关键信号探针
// ============================================================================
module debug_probe(
    // 时钟和复位
    input wire          clk,
    input wire          rst_n,

    // SDRAM 控制信号
    input wire          sdram_init_done,
    input wire          sdram_busy,
    input wire          sdram_wr_en,
    input wire          sdram_rd_en,
    input wire [20:0]   sdram_wr_addr,
    input wire [20:0]   sdram_rd_addr,
    input wire [15:0]   sdram_wr_data,
    input wire [15:0]   sdram_rd_data,

    // UDP/网络数据
    input wire [15:0]   rgb_data,
    input wire          rgb_data_valid,
    input wire          udp_write_req,
    input wire          udp_write_req_ack,

    // VGA 信号
    input wire          vga_hsync,
    input wire          vga_vsync,
    input wire          vga_de,
    input wire [15:0]   video_read_data,
    input wire          video_read_en,
    input wire          video_read_req,
    input wire          video_read_req_ack,

    // 调试输出 (32-bit debug bus)
    output reg [31:0]   debug_bus
);

// 选择要观察的信号组
parameter DEBUG_MODE = 2'd0;  // 0=SDRAM, 1=UDP, 2=VGA, 3=DATA

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        debug_bus <= 32'd0;
    end else begin
        case (DEBUG_MODE)
            2'd0: begin  // SDRAM Debug Mode
                debug_bus <= {
                    sdram_init_done,        // [31]
                    sdram_busy,             // [30]
                    sdram_wr_en,            // [29]
                    sdram_rd_en,            // [28]
                    sdram_wr_addr[11:0],    // [27:16] 写地址低12位
                    sdram_rd_data[15:0]     // [15:0]  读数据
                };
            end

            2'd1: begin  // UDP/Network Debug Mode
                debug_bus <= {
                    rgb_data_valid,         // [31]
                    udp_write_req,          // [30]
                    udp_write_req_ack,      // [29]
                    1'b0,                   // [28] reserved
                    4'h0,                   // [27:24] reserved
                    4'h0,                   // [23:20] reserved
                    rgb_data[15:12],        // [19:16] RGB red
                    rgb_data[11:0]          // [15:0]  RGB GB
                };
            end

            2'd2: begin  // VGA Debug Mode
                debug_bus <= {
                    vga_hsync,              // [31]
                    vga_vsync,              // [30]
                    vga_de,                 // [29]
                    video_read_en,          // [28]
                    video_read_req,         // [27]
                    video_read_req_ack,     // [26]
                    2'b0,                   // [25:24] reserved
                    4'h0,                   // [23:20] reserved
                    video_read_data[15:12], // [19:16] RGB red
                    video_read_data[11:0]   // [15:0]  RGB GB
                };
            end

            2'd3: begin  // Data Compare Mode (UDP vs SDRAM)
                debug_bus <= {
                    rgb_data_valid,         // [31]
                    sdram_wr_en,            // [30]
                    (rgb_data == sdram_wr_data), // [29] 数据匹配
                    sdram_rd_en,            // [28]
                    4'h0,                   // [27:24] reserved
                    rgb_data[15:8],         // [23:16] UDP数据高字节
                    sdram_wr_data[15:8],    // [15:8]  SDRAM写数据高字节
                    sdram_rd_data[7:0]      // [7:0]   SDRAM读数据低字节
                };
            end
        endcase
    end
end

endmodule
