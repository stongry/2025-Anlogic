/*
UDP to CNN Bridge Module
将UDP接收的80x100 RGB888图像转换为CNN预处理层需要的格式
- 输入：80x100 RGB888图像（从RAM读取）
- 输出：提供给CNN预处理层的RGB565格式数据
- 功能：缩放、格式转换、数据流控制
*/

module udp_to_cnn_bridge(
    input               clk,
    input               rst_n,

    // UDP RAM interface (80x100 RGB888)
    input       [23:0]  udp_rgb_data,       // RGB888 from UDP RAM
    output reg  [12:0]  udp_ram_addr,       // Address to read UDP RAM (0-7999)

    // CNN preprocessing layer interface (compatible with PRE_LAYER)
    output reg  [15:0]  cnn_data_out,       // RGB565 to CNN
    output reg          cnn_data_valid,     // Data valid signal
    output reg          cnn_frame_start,    // Frame start pulse

    // Control
    input               start_convert,      // Start conversion pulse
    output reg          convert_done        // Conversion complete
);

// State machine
localparam IDLE         = 3'd0;
localparam WAIT_START   = 3'd1;
localparam READ_DATA    = 3'd2;
localparam CONVERT      = 3'd3;
localparam OUTPUT       = 3'd4;
localparam DONE         = 3'd5;

reg [2:0] state;
reg [2:0] next_state;

// Image size parameters
localparam IMG_WIDTH  = 80;
localparam IMG_HEIGHT = 100;
localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;  // 8000

// Counters
reg [12:0] pixel_cnt;       // 0-7999
reg [1:0]  delay_cnt;       // Delay for RAM read

// RGB888 to RGB565 conversion
wire [4:0] r5 = udp_rgb_data[23:19];  // Red: 8bit -> 5bit
wire [5:0] g6 = udp_rgb_data[15:10];  // Green: 8bit -> 6bit
wire [4:0] b5 = udp_rgb_data[7:3];    // Blue: 8bit -> 5bit
wire [15:0] rgb565 = {r5, g6, b5};

// State machine - sequential logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

// State machine - combinational logic
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (start_convert)
                next_state = WAIT_START;
        end

        WAIT_START: begin
            next_state = READ_DATA;
        end

        READ_DATA: begin
            if (delay_cnt == 2'd2)
                next_state = CONVERT;
        end

        CONVERT: begin
            next_state = OUTPUT;
        end

        OUTPUT: begin
            if (pixel_cnt >= TOTAL_PIXELS - 1)
                next_state = DONE;
            else
                next_state = READ_DATA;
        end

        DONE: begin
            next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
end

// Control logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pixel_cnt <= 13'd0;
        delay_cnt <= 2'd0;
        udp_ram_addr <= 13'd0;
        cnn_data_out <= 16'd0;
        cnn_data_valid <= 1'b0;
        cnn_frame_start <= 1'b0;
        convert_done <= 1'b0;
    end
    else begin
        case (state)
            IDLE: begin
                pixel_cnt <= 13'd0;
                delay_cnt <= 2'd0;
                udp_ram_addr <= 13'd0;
                cnn_data_valid <= 1'b0;
                cnn_frame_start <= 1'b0;
                convert_done <= 1'b0;
            end

            WAIT_START: begin
                cnn_frame_start <= 1'b1;  // Pulse frame start
                udp_ram_addr <= 13'd0;
                delay_cnt <= 2'd0;
            end

            READ_DATA: begin
                cnn_frame_start <= 1'b0;
                delay_cnt <= delay_cnt + 1'b1;
                // Keep address stable for RAM read
            end

            CONVERT: begin
                // Convert RGB888 to RGB565
                cnn_data_out <= rgb565;
                delay_cnt <= 2'd0;
            end

            OUTPUT: begin
                // Output valid data
                cnn_data_valid <= 1'b1;
                pixel_cnt <= pixel_cnt + 1'b1;

                // Prepare next address
                if (pixel_cnt < TOTAL_PIXELS - 1)
                    udp_ram_addr <= pixel_cnt + 1'b1;
            end

            DONE: begin
                cnn_data_valid <= 1'b0;
                convert_done <= 1'b1;
            end

            default: begin
                cnn_data_valid <= 1'b0;
            end
        endcase
    end
end

endmodule
