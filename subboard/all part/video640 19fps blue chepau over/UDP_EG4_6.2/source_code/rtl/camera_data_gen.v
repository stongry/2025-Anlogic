`timescale 1ns / 1ps
//***********************************************************************
// 模拟摄像头数据生成模块
// 功能：生成640x480分辨率的RGB图像数据流
// 输出：24位RGB数据 (每像素3字节)
// 作者：Claude Code
// 日期：2025-10-08
//***********************************************************************

module camera_data_gen(
    input               clk,            // 系统时钟 50MHz
    input               rst_n,          // 复位信号，低有效
    input               cam_enable,     // 摄像头使能信号

    // 输出到SDRAM写入接口
    output reg          cam_data_valid, // 数据有效信号
    output reg [23:0]   cam_data,       // RGB数据 {R[7:0], G[7:0], B[7:0]}
    output reg          frame_start,    // 帧起始信号
    output reg          frame_end       // 帧结束信号
);

// 参数定义
parameter H_TOTAL   = 640;  // 水平总像素
parameter V_TOTAL   = 480;  // 垂直总行数
parameter FRAME_SIZE = H_TOTAL * V_TOTAL; // 307200 pixels

// 内部信号
reg [9:0]  h_cnt;           // 水平计数器 0-639
reg [8:0]  v_cnt;           // 垂直计数器 0-479
reg [18:0] pixel_cnt;       // 像素计数器 0-307199
// 帧生成状态机
reg [2:0] state;
localparam IDLE       = 3'd0;
localparam FRAME_HEAD = 3'd1;
localparam DATA_OUT   = 3'd2;
localparam FRAME_TAIL = 3'd3;
localparam WAIT       = 3'd4;

reg [15:0] wait_cnt;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state          <= IDLE;
        h_cnt          <= 10'd0;
        v_cnt          <= 9'd0;
        pixel_cnt      <= 19'd0;
        cam_data_valid <= 1'b0;
        cam_data       <= 24'd0;
        frame_start    <= 1'b0;
        frame_end      <= 1'b0;
        wait_cnt       <= 16'd0;
    end
    else begin
        case(state)
            IDLE: begin
                frame_start    <= 1'b0;
                frame_end      <= 1'b0;
                cam_data_valid <= 1'b0;
                if(cam_enable) begin  // 改为电平触发，只要cam_enable为高就开始
                    state <= FRAME_HEAD;
                    h_cnt <= 10'd0;
                    v_cnt <= 9'd0;
                    pixel_cnt <= 19'd0;
                end
            end

            FRAME_HEAD: begin
                frame_start <= 1'b1;
                state       <= DATA_OUT;
            end

            DATA_OUT: begin
                frame_start    <= 1'b0;
                cam_data_valid <= 1'b1;

                // 输出彩条渐变，用于仿真/联调时的基本可视化
                if (v_cnt < 160) begin
                    cam_data <= {h_cnt[7:0], 8'h00, 8'h00}; // 蓝色分量渐变
                end
                else if (v_cnt < 320) begin
                    cam_data <= {8'h00, h_cnt[7:0], 8'h00}; // 绿色分量渐变
                end
                else begin
                    cam_data <= {8'h00, 8'h00, h_cnt[7:0]}; // 红色分量渐变
                end

                // 像素计数器更新
                if(h_cnt == H_TOTAL - 1) begin
                    h_cnt <= 10'd0;
                    if(v_cnt == V_TOTAL - 1) begin
                        v_cnt <= 9'd0;
                        state <= FRAME_TAIL;
                    end
                    else begin
                        v_cnt <= v_cnt + 1'b1;
                    end
                end
                else begin
                    h_cnt <= h_cnt + 1'b1;
                end

                pixel_cnt <= pixel_cnt + 1'b1;

                // 检查是否到达帧尾
                if(pixel_cnt == FRAME_SIZE - 1) begin
                    pixel_cnt <= 19'd0;
                    state     <= FRAME_TAIL;
                end
            end

            FRAME_TAIL: begin
                cam_data_valid <= 1'b0;
                frame_end      <= 1'b1;
                wait_cnt       <= 16'd0;
                state          <= WAIT;
            end

            WAIT: begin
                frame_end <= 1'b0;
                // 帧间间隔：等待约1ms（50000个时钟周期）
                if(wait_cnt < 16'd50000) begin
                    wait_cnt <= wait_cnt + 1'b1;
                end
                else begin
                    wait_cnt <= 16'd0;
                    if(cam_enable)
                        state <= FRAME_HEAD;  // 继续下一帧
                    else
                        state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
