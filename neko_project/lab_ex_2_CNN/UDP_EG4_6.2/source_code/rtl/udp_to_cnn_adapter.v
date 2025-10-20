/*
UDP Image to CNN Preprocessing Adapter
将UDP接收的80x100 RGB888图像适配到CNN预处理层
- 输入：80x100 RGB888图像（从UDP RAM读取）
- 输出：提供给PRE_LAYER的RGB565格式数据流
- 功能：RGB888->RGB565转换，生成控制信号
*/

module udp_to_cnn_adapter(
    input               clk,
    input               rst_n,

    // Control
    input               start_process,      // Start processing pulse (from button or auto-trigger)
    output reg          process_done,       // Processing complete

    // UDP RAM interface (80x100 RGB888)
    output reg  [12:0]  udp_ram_addr,       // Address to read UDP RAM (0-7999)
    input       [23:0]  udp_rgb_data,       // RGB888 from UDP RAM

    // PRE_LAYER interface (RGB565 input)
    output reg  [15:0]  pre_data_in,        // RGB565 to PRE_LAYER
    output reg          pre_ren_P2          // Enable signal for PRE_LAYER (acts as data valid)
);

// Image size parameters
localparam IMG_WIDTH  = 80;
localparam IMG_HEIGHT = 100;
localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;  // 8000

// State machine
localparam IDLE         = 3'd0;
localparam START        = 3'd1;
localparam READ_WAIT    = 3'd2;
localparam CONVERT      = 3'd3;
localparam OUTPUT       = 3'd4;
localparam DONE         = 3'd5;

reg [2:0] state;
reg [12:0] pixel_cnt;       // 0-7999
reg [1:0]  wait_cnt;        // Wait cycles for RAM read

// RGB888 to RGB565 conversion
wire [4:0] r5 = udp_rgb_data[23:19];  // Red: 8bit -> 5bit
wire [5:0] g6 = udp_rgb_data[15:10];  // Green: 8bit -> 6bit
wire [4:0] b5 = udp_rgb_data[7:3];    // Blue: 8bit -> 5bit
wire [15:0] rgb565 = {r5, g6, b5};

// State machine
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        pixel_cnt <= 13'd0;
        wait_cnt <= 2'd0;
        udp_ram_addr <= 13'd0;
        pre_data_in <= 16'd0;
        pre_ren_P2 <= 1'b0;
        process_done <= 1'b0;
    end
    else begin
        case (state)
            IDLE: begin
                pixel_cnt <= 13'd0;
                udp_ram_addr <= 13'd0;
                pre_ren_P2 <= 1'b0;
                process_done <= 1'b0;
                wait_cnt <= 2'd0;

                if (start_process) begin
                    state <= START;
                end
            end

            START: begin
                // Pulse pre_ren_P2 low to signal start
                pre_ren_P2 <= 1'b0;
                udp_ram_addr <= 13'd0;
                pixel_cnt <= 13'd0;
                state <= READ_WAIT;
            end

            READ_WAIT: begin
                // Wait for RAM read (2 cycles)
                wait_cnt <= wait_cnt + 1'b1;
                if (wait_cnt == 2'd2) begin
                    wait_cnt <= 2'd0;
                    state <= CONVERT;
                end
            end

            CONVERT: begin
                // Convert RGB888 to RGB565
                pre_data_in <= rgb565;
                state <= OUTPUT;
            end

            OUTPUT: begin
                // Output data with pre_ren_P2 high (data valid)
                pre_ren_P2 <= 1'b1;
                pixel_cnt <= pixel_cnt + 1'b1;

                // Check if all pixels processed
                if (pixel_cnt >= TOTAL_PIXELS - 1) begin
                    state <= DONE;
                end
                else begin
                    // Prepare next address
                    udp_ram_addr <= pixel_cnt + 1'b1;
                    state <= READ_WAIT;
                end
            end

            DONE: begin
                pre_ren_P2 <= 1'b0;
                process_done <= 1'b1;
                state <= IDLE;
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule
