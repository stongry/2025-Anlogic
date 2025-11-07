module udp_key_data_tpg(
    input wire clk,
    input wire reset,
    input wire signed [8:0] digit_value,  // 修改为9位有符号数：-100到+100
    input wire digit_changed,
    input wire [3:0] led_control_value,
    input wire led_control_changed,
    input wire tpg_data_enable,
    
    output reg [7:0] tpg_data,
    output reg tpg_data_valid,
    output reg [15:0] tpg_data_udp_length,
    output reg tpg_data_done
);

// 状态机状态定义
parameter IDLE = 3'b000;
parameter SEND_HEADER = 3'b001; 
parameter SEND_DATA = 3'b010;
parameter SEND_DONE = 3'b011;
parameter IFG_WAIT = 3'b100;

reg [2:0] state;
reg [3:0] byte_cnt;
reg [7:0] ifg_cnt;
reg signed [8:0] digit_value_reg;  // 修改为9位有符号数
reg [3:0] led_control_value_reg;
reg packet_type;  // 0=数码管控制，1=LED控制

// 帧格式：
// 字节0-1: 0xF0AA (帧头标识)
// 字节2-3: 0x5555 (固定标识)  
// 字节4-5: 数据类型 (0x1234=数码管控制, 0x5678=LED控制)
// 字节6-7: 0x0008 (数据长度8字节)
// 字节8: 数值高字节 (digit_value[8:8] - 符号位扩展)
// 字节9: 数值低字节 (digit_value[7:0])
// 字节10-15: 保留字节

always @(posedge clk or posedge reset) begin
    if(reset) begin
        state <= IDLE;
        tpg_data <= 8'h00;
        tpg_data_valid <= 1'b0;
        tpg_data_udp_length <= 16'h0000;
        tpg_data_done <= 1'b0;
        byte_cnt <= 4'h0;
        ifg_cnt <= 8'h00;
        digit_value_reg <= 9'd0;  // 修改为9位有符号数，初始值0
        led_control_value_reg <= 4'h0;
        packet_type <= 1'b0;
    end
    else begin
        case(state)
            IDLE: begin
                tpg_data_valid <= 1'b0;
                tpg_data_done <= 1'b0;
                if(tpg_data_enable) begin
                    if(digit_changed) begin
                        digit_value_reg <= digit_value;
                        packet_type <= 1'b0;  // 数码管控制包
                        state <= SEND_HEADER;
                        byte_cnt <= 4'h0;
                        tpg_data_udp_length <= 16'h0010;
                    end
                    else if(led_control_changed) begin
                        led_control_value_reg <= led_control_value;
                        packet_type <= 1'b1;  // LED控制包
                        state <= SEND_HEADER;
                        byte_cnt <= 4'h0;
                        tpg_data_udp_length <= 16'h0010;
                    end
                end
            end
            
            SEND_HEADER: begin
                tpg_data_valid <= 1'b1;
                case(byte_cnt)
                    4'h0: tpg_data <= 8'hF0;
                    4'h1: tpg_data <= 8'hAA;
                    4'h2: tpg_data <= 8'h55;
                    4'h3: tpg_data <= 8'h55;
                    4'h4: tpg_data <= packet_type ? 8'h56 : 8'h12;
                    4'h5: tpg_data <= packet_type ? 8'h78 : 8'h34;
                    4'h6: tpg_data <= 8'h00;
                    4'h7: tpg_data <= 8'h08;
                    default: tpg_data <= 8'h00;
                endcase
                
                if(byte_cnt == 4'h7) begin
                    state <= SEND_DATA;
                    byte_cnt <= 4'h0;
                end
                else begin
                    byte_cnt <= byte_cnt + 4'h1;
                end
            end
            
            SEND_DATA: begin
                tpg_data_valid <= 1'b1;
                case(byte_cnt)
                    // 发送9位有符号数，分两个字节发送
                    4'h0: tpg_data <= packet_type ? {4'h0, led_control_value_reg} : 
                                      (digit_value_reg[8] ? 8'hFF : 8'h00);  // 符号扩展到高字节
                    4'h1: tpg_data <= packet_type ? 8'h00 : digit_value_reg[7:0];  // 低字节
                    default: tpg_data <= 8'h00;
                endcase
                
                if(byte_cnt == 4'h7) begin
                    state <= SEND_DONE;
                end
                else begin
                    byte_cnt <= byte_cnt + 4'h1;
                end
            end
            
            SEND_DONE: begin
                tpg_data_valid <= 1'b0;
                tpg_data_done <= 1'b1;
                state <= IFG_WAIT;
                ifg_cnt <= 8'h00;
            end
            
            IFG_WAIT: begin
                tpg_data_done <= 1'b0;
                if(ifg_cnt == 8'hFF) begin
                    state <= IDLE;
                end
                else begin
                    ifg_cnt <= ifg_cnt + 8'h1;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule