`include "video_define.v"
module color_bar(
    input                 clk,           //pixel clock
    input                 rst,           //reset signal high active
    
    // 写请求握手信号
    output reg            write_req,     //start writing request
    input                 write_req_ack, //write request response
    
    output                hs,            //horizontal synchronization
    output                vs,            //vertical synchronization
    output                de,            //video valid
    output[7:0]           rgb_r,         //video red data
    output[7:0]           rgb_g,         //video green data
    output[7:0]           rgb_b,         //video blue data
    output[15:0]          rgb565_data,   //RGB565 format data (5-R, 6-G, 5-B)
    output                data_valid     //data valid signal
);

//video timing parameter definition
`ifdef  VIDEO_1280_720
parameter H_ACTIVE = 16'd1280;
parameter H_FP = 16'd110;
parameter H_SYNC = 16'd40;
parameter H_BP = 16'd220;
parameter V_ACTIVE = 16'd720;
parameter V_FP  = 16'd5;
parameter V_SYNC  = 16'd5;
parameter V_BP  = 16'd20;
parameter HS_POL = 1'b1;
parameter VS_POL = 1'b1;
`endif

`ifdef  VIDEO_480_272
parameter H_ACTIVE = 16'd480; 
parameter H_FP = 16'd2;       
parameter H_SYNC = 16'd41;    
parameter H_BP = 16'd2;       
parameter V_ACTIVE = 16'd272; 
parameter V_FP  = 16'd2;     
parameter V_SYNC  = 16'd10;   
parameter V_BP  = 16'd2;     
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

`ifdef  VIDEO_640_480
parameter H_ACTIVE = 16'd640; 
parameter H_FP = 16'd16;      
parameter H_SYNC = 16'd96;    
parameter H_BP = 16'd48;      
parameter V_ACTIVE = 16'd480; 
parameter V_FP  = 16'd10;    
parameter V_SYNC  = 16'd2;    
parameter V_BP  = 16'd33;    
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

`ifdef  VIDEO_800_480
parameter H_ACTIVE = 16'd800; 
parameter H_FP = 16'd40;      
parameter H_SYNC = 16'd128;   
parameter H_BP = 16'd88;      
parameter V_ACTIVE = 16'd480; 
parameter V_FP  = 16'd1;     
parameter V_SYNC  = 16'd3;    
parameter V_BP  = 16'd21;    
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

`ifdef  VIDEO_800_600
parameter H_ACTIVE = 16'd800; 
parameter H_FP = 16'd40;      
parameter H_SYNC = 16'd128;   
parameter H_BP = 16'd88;      
parameter V_ACTIVE = 16'd600; 
parameter V_FP  = 16'd1;     
parameter V_SYNC  = 16'd4;    
parameter V_BP  = 16'd23;    
parameter HS_POL = 1'b1;
parameter VS_POL = 1'b1;
`endif

`ifdef  VIDEO_1024_768
parameter H_ACTIVE = 16'd1024;
parameter H_FP = 16'd24;      
parameter H_SYNC = 16'd136;   
parameter H_BP = 16'd160;     
parameter V_ACTIVE = 16'd768; 
parameter V_FP  = 16'd3;      
parameter V_SYNC  = 16'd6;    
parameter V_BP  = 16'd29;     
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

`ifdef  VIDEO_1920_1080
parameter H_ACTIVE = 16'd1920;
parameter H_FP = 16'd88;
parameter H_SYNC = 16'd44;
parameter H_BP = 16'd148; 
parameter V_ACTIVE = 16'd1080;
parameter V_FP  = 16'd4;
parameter V_SYNC  = 16'd5;
parameter V_BP  = 16'd36;
parameter HS_POL = 1'b1;
parameter VS_POL = 1'b1;
`endif

parameter H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
parameter V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

//define the RGB values for 8 colors
parameter WHITE_R       = 8'hff;
parameter WHITE_G       = 8'hff;
parameter WHITE_B       = 8'hff;
parameter YELLOW_R      = 8'hff;
parameter YELLOW_G      = 8'hff;
parameter YELLOW_B      = 8'h00;
parameter CYAN_R        = 8'h00;
parameter CYAN_G        = 8'hff;
parameter CYAN_B        = 8'hff;
parameter GREEN_R       = 8'h00;
parameter GREEN_G       = 8'hff;
parameter GREEN_B       = 8'h00;
parameter MAGENTA_R     = 8'hff;
parameter MAGENTA_G     = 8'h00;
parameter MAGENTA_B     = 8'hff;
parameter RED_R         = 8'hff;
parameter RED_G         = 8'h00;
parameter RED_B         = 8'h00;
parameter BLUE_R        = 8'h00;
parameter BLUE_G        = 8'h00;
parameter BLUE_B        = 8'hff;
parameter BLACK_R       = 8'h00;
parameter BLACK_G       = 8'h00;
parameter BLACK_B       = 8'h00;

reg hs_reg;
reg vs_reg;
reg hs_reg_d0;
reg vs_reg_d0;
reg[11:0] h_cnt;
reg[11:0] v_cnt;
reg[11:0] active_x;
reg[7:0] rgb_r_reg;
reg[7:0] rgb_g_reg;
reg[7:0] rgb_b_reg;
reg h_active;
reg v_active;
wire video_active;
reg video_active_d0;

// ========== 简化的握手逻辑（无状态机）==========
reg frame_start;           // 帧开始标志
reg frame_start_d0;        // 延迟一拍
reg write_req_ack_d0;      // ack 延迟一拍
reg frame_writing;         // 正在写入标志

// 检测帧开始 (在帧的起始位置触发)
always @(posedge clk or posedge rst) begin
    if (rst) begin
        frame_start <= 1'b0;
        frame_start_d0 <= 1'b0;
    end
    else begin
        // 在垂直和水平计数器归零时触发
        frame_start <= ((v_cnt == 12'd0) && (h_cnt == 12'd0));
        frame_start_d0 <= frame_start;
    end
end

wire frame_start_pulse = frame_start && !frame_start_d0;

// 检测 ack 上升沿
always @(posedge clk or posedge rst) begin
    if (rst)
        write_req_ack_d0 <= 1'b0;
    else
        write_req_ack_d0 <= write_req_ack;
end

wire write_req_ack_pulse = write_req_ack && !write_req_ack_d0;

// 写请求逻辑：在帧开始时发起请求
always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_req <= 1'b0;
    end
    else begin
        if ( frame_start_pulse && !write_req) begin
            write_req <= 1'b1;  // 发起写请求
        end
        else if (write_req_ack_pulse) begin
            write_req <= 1'b0;  // 收到响应后撤销请求
        end
    end
end

// 写入标志：从收到 ack 到帧结束
always @(posedge clk or posedge rst) begin
    if (rst) begin
        frame_writing <= 1'b0;
    end
    else begin
        if (write_req_ack_pulse) begin
            frame_writing <= 1'b1;  // 开始写入
        end
        else if ((v_cnt == V_TOTAL - 1) && (h_cnt == H_TOTAL - 1)) begin
            frame_writing <= 1'b0;  // 帧结束
        end
    end
end

// ========== 输出赋值 ==========
assign hs = hs_reg_d0;
assign vs = vs_reg_d0;
assign video_active = h_active & v_active;
assign de = video_active_d0;
assign rgb_r = rgb_r_reg;
assign rgb_g = rgb_g_reg;
assign rgb_b = rgb_b_reg;

// RGB565 转换
assign rgb565_data = {rgb_r_reg[7:3], rgb_g_reg[7:2], rgb_b_reg[7:3]};

// data_valid: 只有在收到 ack 后且视频有效时才输出数据
assign data_valid = frame_writing && video_active_d0;

// ========== VGA/HDMI 时序生成逻辑 ==========
always @(posedge clk or posedge rst) begin
    if (rst) begin
        hs_reg_d0 <= 1'b0;
        vs_reg_d0 <= 1'b0;
        video_active_d0 <= 1'b0;
    end
    else begin
        hs_reg_d0 <= hs_reg;
        vs_reg_d0 <= vs_reg;
        video_active_d0 <= video_active;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        h_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 1)
        h_cnt <= 12'd0;
    else
        h_cnt <= h_cnt + 12'd1;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        active_x <= 12'd0;
    else if (h_cnt >= H_FP + H_SYNC + H_BP - 1)
        active_x <= h_cnt - (H_FP[11:0] + H_SYNC[11:0] + H_BP[11:0] - 12'd1);
    else
        active_x <= active_x;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        v_cnt <= 12'd0;
    else if (h_cnt == H_FP - 1)
        if (v_cnt == V_TOTAL - 1)
            v_cnt <= 12'd0;
        else
            v_cnt <= v_cnt + 12'd1;
    else
        v_cnt <= v_cnt;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        hs_reg <= 1'b0;
    else if (h_cnt == H_FP - 1)
        hs_reg <= HS_POL;
    else if (h_cnt == H_FP + H_SYNC - 1)
        hs_reg <= ~hs_reg;
    else
        hs_reg <= hs_reg;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        h_active <= 1'b0;
    else if (h_cnt == H_FP + H_SYNC + H_BP - 1)
        h_active <= 1'b1;
    else if (h_cnt == H_TOTAL - 1)
        h_active <= 1'b0;
    else
        h_active <= h_active;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        vs_reg <= 1'd0;
    else if ((v_cnt == V_FP - 1) && (h_cnt == H_FP - 1))
        vs_reg <= VS_POL;
    else if ((v_cnt == V_FP + V_SYNC - 1) && (h_cnt == H_FP - 1))
        vs_reg <= ~vs_reg;
    else
        vs_reg <= vs_reg;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        v_active <= 1'd0;
    else if ((v_cnt == V_FP + V_SYNC + V_BP - 1) && (h_cnt == H_FP - 1))
        v_active <= 1'b1;
    else if ((v_cnt == V_TOTAL - 1) && (h_cnt == H_FP - 1))
        v_active <= 1'b0;
    else
        v_active <= v_active;
end

// ========== RGB 彩条生成逻辑 ==========
always @(posedge clk or posedge rst) begin
    if (rst) begin
        rgb_r_reg <= 8'h00;
        rgb_g_reg <= 8'h00;
        rgb_b_reg <= 8'h00;
    end
    else if (video_active) begin
        if (active_x == 12'd0) begin
            rgb_r_reg <= WHITE_R;
            rgb_g_reg <= WHITE_G;
            rgb_b_reg <= WHITE_B;
        end
        else if (active_x == (H_ACTIVE/8) * 1) begin
            rgb_r_reg <= YELLOW_R;
            rgb_g_reg <= YELLOW_G;
            rgb_b_reg <= YELLOW_B;
        end
        else if (active_x == (H_ACTIVE/8) * 2) begin
            rgb_r_reg <= CYAN_R;
            rgb_g_reg <= CYAN_G;
            rgb_b_reg <= CYAN_B;
        end
        else if (active_x == (H_ACTIVE/8) * 3) begin
            rgb_r_reg <= GREEN_R;
            rgb_g_reg <= GREEN_G;
            rgb_b_reg <= GREEN_B;
        end
        else if (active_x == (H_ACTIVE/8) * 4) begin
            rgb_r_reg <= MAGENTA_R;
            rgb_g_reg <= MAGENTA_G;
            rgb_b_reg <= MAGENTA_B;
        end
        else if (active_x == (H_ACTIVE/8) * 5) begin
            rgb_r_reg <= RED_R;
            rgb_g_reg <= RED_G;
            rgb_b_reg <= RED_B;
        end
        else if (active_x == (H_ACTIVE/8) * 6) begin
            rgb_r_reg <= BLUE_R;
            rgb_g_reg <= BLUE_G;
            rgb_b_reg <= BLUE_B;
        end
        else if (active_x == (H_ACTIVE/8) * 7) begin
            rgb_r_reg <= BLACK_R;
            rgb_g_reg <= BLACK_G;
            rgb_b_reg <= BLACK_B;
        end
        else begin
            rgb_r_reg <= rgb_r_reg;
            rgb_g_reg <= rgb_g_reg;
            rgb_b_reg <= rgb_b_reg;
        end
    end
    else begin
        rgb_r_reg <= 8'h00;
        rgb_g_reg <= 8'h00;
        rgb_b_reg <= 8'h00;
    end
end

endmodule