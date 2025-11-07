module udp_display_parser(
    input wire clk,
    input wire reset,
    
    // UDP接收接口
    input wire app_rx_data_valid,
    input wire [7:0] app_rx_data,
    input wire [15:0] app_rx_data_length,
    
    // 数码管显示输出
    output reg signed [8:0] digit_value,  // 修改为9位有符号数：-100到+100
    output reg digit_value_valid,
    
    // LED控制输出
    output reg [3:0] led_control_value,
    output reg led_control_valid
);

// 数据包解析状态机
parameter IDLE = 3'b000;
parameter WAIT_HEADER0_H = 3'b001;
parameter WAIT_HEADER0_L = 3'b010;
parameter WAIT_HEADER1_H = 3'b011;
parameter WAIT_HEADER1_L = 3'b100;
parameter WAIT_TYPE_H = 3'b101;
parameter WAIT_TYPE_L = 3'b110;
parameter WAIT_DATA = 3'b111;

reg [2:0] state;
reg [7:0] timeout_cnt;
reg [3:0] byte_cnt;
reg packet_type; // 0=数码管控制(0x1234), 1=LED控制(0x5678)
reg [7:0] data_byte_high;  // 保存数据高字节

always @(posedge clk or posedge reset) begin
    if(reset) begin
        state <= IDLE;
        digit_value <= 9'd0;  // 修改为9位有符号数，初始值0
        digit_value_valid <= 1'b0;
        led_control_value <= 4'h0;
        led_control_valid <= 1'b0;
        timeout_cnt <= 8'h00;
        byte_cnt <= 4'h0;
        packet_type <= 1'b0;
        data_byte_high <= 8'h00;
    end
    else begin
        // 超时重置机制 - 如果在非IDLE状态下超过255个时钟周期没有收到数据则重置
        if(state != IDLE) begin
            if(app_rx_data_valid) begin
                timeout_cnt <= 8'h00;
            end
            else begin
                timeout_cnt <= timeout_cnt + 8'h01;
                if(timeout_cnt == 8'hFF) begin
                    state <= IDLE;
                    digit_value_valid <= 1'b0;
                    led_control_valid <= 1'b0;
                end
            end
        end
        
        case(state)
            IDLE: begin
                digit_value_valid <= 1'b0;
                led_control_valid <= 1'b0;
                timeout_cnt <= 8'h00;
                if(app_rx_data_valid && app_rx_data == 8'hF0) begin
                    state <= WAIT_HEADER0_L;
                end
            end
            
            WAIT_HEADER0_L: begin
                if(app_rx_data_valid) begin
                    if(app_rx_data == 8'hAA) begin
                        state <= WAIT_HEADER1_H;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
            
            WAIT_HEADER1_H: begin
                if(app_rx_data_valid) begin
                    if(app_rx_data == 8'h55) begin
                        state <= WAIT_HEADER1_L;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
            
            WAIT_HEADER1_L: begin
                if(app_rx_data_valid) begin
                    if(app_rx_data == 8'h55) begin
                        state <= WAIT_TYPE_H;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
            
            WAIT_TYPE_H: begin
                if(app_rx_data_valid) begin
                    if(app_rx_data == 8'h12) begin
                        packet_type <= 1'b0; // 数码管控制包
                        state <= WAIT_TYPE_L;
                    end
                    else if(app_rx_data == 8'h56) begin
                        packet_type <= 1'b1; // LED控制包
                        state <= WAIT_TYPE_L;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
            
            WAIT_TYPE_L: begin
                if(app_rx_data_valid) begin
                    if((packet_type == 1'b0 && app_rx_data == 8'h34) || 
                       (packet_type == 1'b1 && app_rx_data == 8'h78)) begin
                        state <= WAIT_DATA;
                        byte_cnt <= 4'h0; // 重置计数器
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
            
            WAIT_DATA: begin
                if(app_rx_data_valid) begin
                    if(byte_cnt == 4'h0) begin
                        // 跳过长度字段高字节
                        byte_cnt <= 4'h1;
                    end
                    else if(byte_cnt == 4'h1) begin
                        // 跳过长度字段低字节  
                        byte_cnt <= 4'h2;
                    end
                    else if(byte_cnt == 4'h2) begin
                        // 接收数据高字节
                        if(packet_type == 1'b0) begin
                            // 数码管控制包 - 保存高字节（符号扩展）
                            data_byte_high <= app_rx_data;
                        end
                        else begin
                            // LED控制包 - 直接使用
                            led_control_value <= app_rx_data[3:0];
                            led_control_valid <= 1'b1;
                            state <= IDLE;
                        end
                        byte_cnt <= 4'h3;
                    end
                    else if(byte_cnt == 4'h3) begin
                        // 接收数据低字节
                        if(packet_type == 1'b0) begin
                            // 数码管控制包 - 直接使用8位补码表示
                            // 将8位补码扩展为9位有符号数
                            digit_value <= $signed(app_rx_data);  // Verilog自动符号扩展
                            digit_value_valid <= 1'b1;
                        end
                        state <= IDLE;
                        byte_cnt <= 4'h0;
                    end
                end
            end
            
            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule