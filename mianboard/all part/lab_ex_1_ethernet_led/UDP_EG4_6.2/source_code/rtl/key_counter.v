module key_counter(
    input wire clk,
    input wire rst_n,
    input wire key2,      // K2: 加1
    input wire key3,      // K3: LED控制（保留）
    input wire key4,      // K4: 减1（新增）
    output reg signed [8:0] digit_value,  // 扩展为9位有符号数：-100到+100
    output reg digit_changed,
    output reg [3:0] led_control_value,
    output reg led_control_changed
);

wire key2_posedge, key3_posedge, key4_posedge;
wire key2_negedge, key3_negedge, key4_negedge;
wire key2_out, key3_out, key4_out;

// K2按键防抖
ax_debounce key2_debounce(
    .clk(clk),
    .rst(~rst_n),
    .button_in(key2),
    .button_posedge(key2_posedge),
    .button_negedge(key2_negedge),
    .button_out(key2_out)
);

// K3按键防抖
ax_debounce key3_debounce(
    .clk(clk),
    .rst(~rst_n),
    .button_in(key3),
    .button_posedge(key3_posedge),
    .button_negedge(key3_negedge),
    .button_out(key3_out)
);

// K4按键防抖（新增）
ax_debounce key4_debounce(
    .clk(clk),
    .rst(~rst_n),
    .button_in(key4),
    .button_posedge(key4_posedge),
    .button_negedge(key4_negedge),
    .button_out(key4_out)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        digit_value <= 9'sd0;  // 初始值：0（使用有符号常量）
        digit_changed <= 1'b0;
        led_control_value <= 4'h0;
        led_control_changed <= 1'b0;
    end
    else begin
        // K2按键：加1（范围：-100到+100）
        if(key2_negedge) begin
            if(digit_value < 9'sd100)  // 使用有符号常量比较
                digit_value <= digit_value + 9'sd1;
            else
                digit_value <= 9'sd100;  // 保持在+100
            digit_changed <= 1'b1;
        end
        // K4按键：减1（范围：-100到+100）
        else if(key4_negedge) begin
            if(digit_value > -9'sd100)  // 使用有符号常量比较
                digit_value <= digit_value - 9'sd1;
            else
                digit_value <= -9'sd100;  // 保持在-100
            digit_changed <= 1'b1;
        end
        else begin
            digit_changed <= 1'b0;
        end
        
        // K3按键：LED控制逻辑
        if(key3_negedge) begin
            // K3切换LED状态：全灭 <-> 全亮
            if(led_control_value == 4'h0)
                led_control_value <= 4'hF;
            else
                led_control_value <= 4'h0;
            led_control_changed <= 1'b1;
        end
        else begin
            led_control_changed <= 1'b0;
        end
    end
end

endmodule