// ============================================================================
// Simple Color Bar Data Generator - 精简版彩条数据生成器
// ✅ 修改：添加 write_req/ack 握手机制，仿照 bmp_read 的设计
// 用于测试SDRAM读写功能
// ============================================================================
module colorbar_simple(
    input wire          clk,            // 时钟 (ext_mem_clk)
    input wire          rst_n,          // 复位（低有效）
    input wire          enable,         // 使能信号（SDRAM初始化完成）

    // ✅ 新增：写请求握手信号
    output reg          write_req,      // 写请求（保持高直到 ack）
    input wire          write_req_ack,  // 写请求应答（来自 frame_fifo_write）

    output reg [15:0]   rgb565_data,    // RGB565数据输出
    output reg          data_valid      // 数据有效信号
);

// 640x480 分辨率参数
parameter H_ACTIVE = 640;
parameter V_ACTIVE = 480;
parameter TOTAL_PIXELS = H_ACTIVE * V_ACTIVE;  // 307200

// 像素计数器 (0~307199)
reg [18:0] pixel_cnt;  // 19位足够计数到307200

// 水平位置计数器 (0~639)
reg [9:0] x_pos;

// 数据输出速率控制（模仿UDP的数据速率）
// 每N个时钟周期输出一个像素
parameter RATE_DIV = 4'd8;  // 分频系数，可调整输出速率
reg [3:0] rate_cnt;

// 彩条宽度: 640 / 8 = 80 像素
parameter BAR_WIDTH = 80;

// 8色RGB565定义
parameter WHITE   = 16'hFFFF;  // 白色
parameter YELLOW  = 16'hFFE0;  // 黄色
parameter CYAN    = 16'h07FF;  // 青色
parameter GREEN   = 16'h07E0;  // 绿色
parameter MAGENTA = 16'hF81F;  // 洋红
parameter RED     = 16'hF800;  // 红色
parameter BLUE    = 16'h001F;  // 蓝色
parameter BLACK   = 16'h0000;  // 黑色

// ============================================================================
// ✅ 新增：写请求状态机（仿照 bmp_read 的 S_IDLE/S_READ_WAIT/S_READ/S_END）
// ============================================================================
localparam S_IDLE       = 3'd0;  // 等待使能
localparam S_REQ_WAIT   = 3'd1;  // 发送写请求，等待应答
localparam S_DATA       = 3'd2;  // 发送数据
localparam S_END        = 3'd3;  // 一帧结束

reg [2:0] state;

// 状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        write_req <= 1'b0;
    end else begin
        case (state)
            S_IDLE: begin
                // ✅ 使能后立即发起写请求（类似 bmp_read 的 S_FIND->S_READ_WAIT）
                if (enable) begin
                    state <= S_REQ_WAIT;
                    write_req <= 1'b1;  // 发起写请求
                end
            end

            S_REQ_WAIT: begin
                // ✅ 等待 frame_fifo_write 应答（类似 bmp_read 的 write_req_ack）
                if (write_req_ack) begin
                    state <= S_DATA;
                    write_req <= 1'b0;  // 取消请求
                end
            end

            S_DATA: begin
                // ✅ 发送一帧数据（307200 个像素）
                if (pixel_cnt >= TOTAL_PIXELS - 1 && data_valid) begin
                    state <= S_END;
                end
                // ✅ 如果外部取消使能，回到空闲
                if (!enable) begin
                    state <= S_IDLE;
                end
            end

            S_END: begin
                // ✅ 一帧结束后，回到空闲等待下一次使能
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

// ============================================================================
// 速率控制计数器（只在 S_DATA 状态工作）
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rate_cnt <= 4'd0;
    end else if (state == S_DATA) begin
        if (rate_cnt == RATE_DIV - 1)
            rate_cnt <= 4'd0;
        else
            rate_cnt <= rate_cnt + 1'b1;
    end else begin
        rate_cnt <= 4'd0;
    end
end

// ============================================================================
// ✅ 修改：data_valid 只在 S_DATA 状态按速率输出
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_valid <= 1'b0;
    end else if (state == S_DATA && (rate_cnt == 4'd0) && (pixel_cnt < TOTAL_PIXELS)) begin
        data_valid <= 1'b1;  // 每RATE_DIV个时钟周期产生一个data_valid脉冲
    end else begin
        data_valid <= 1'b0;
    end
end

// ============================================================================
// 像素计数器和位置计数器 - 当data_valid=1时更新
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pixel_cnt <= 19'd0;
        x_pos <= 10'd0;
    end else if (data_valid) begin
        if (pixel_cnt == TOTAL_PIXELS - 1) begin
            pixel_cnt <= 19'd0;
            x_pos <= 10'd0;
        end else begin
            pixel_cnt <= pixel_cnt + 1'b1;
            if (x_pos == H_ACTIVE - 1)
                x_pos <= 10'd0;
            else
                x_pos <= x_pos + 1'b1;
        end
    end else if (state == S_IDLE) begin
        // ✅ 修改：空闲时清零计数器
        pixel_cnt <= 19'd0;
        x_pos <= 10'd0;
    end
end

// ============================================================================
// ✅ 修改：彩条颜色生成（只在 S_DATA 状态工作）
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rgb565_data <= BLACK;
    end else if (state == S_DATA) begin
        case (x_pos / BAR_WIDTH)  // 除以80得到彩条索引(0~7)
            3'd0: rgb565_data <= WHITE;
            3'd1: rgb565_data <= YELLOW;
            3'd2: rgb565_data <= CYAN;
            3'd3: rgb565_data <= GREEN;
            3'd4: rgb565_data <= MAGENTA;
            3'd5: rgb565_data <= RED;
            3'd6: rgb565_data <= BLUE;
            3'd7: rgb565_data <= BLACK;
            default: rgb565_data <= BLACK;
        endcase
    end else begin
        rgb565_data <= BLACK;
    end
end

endmodule
