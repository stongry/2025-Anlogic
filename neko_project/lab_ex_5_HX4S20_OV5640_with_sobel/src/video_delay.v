// ============================================================================
// 视频延迟与边缘检测模块
// 功能：将RGB视频信号转换为灰度图像，并使用Sobel算子进行边缘检测
// ============================================================================

module video_delay
#(
	parameter DATA_WIDTH = 24,                       // 视频数据位宽（RGB888格式）
	parameter H_SIZE = 1024                          // 水平分辨率（从top.v传递）
)
(
	// 输入信号
	input                       video_clk,          // 视频像素时钟
	input                       rst,                // 复位信号
	output                      read_en,            // 读数据使能信号
	input[DATA_WIDTH - 1:0]     read_data,          // 输入视频数据（RGB888）
	input                       hs,                 // 水平同步信号
	input                       vs,                 // 垂直同步信号
	input                       de,                 // 视频有效信号
	input                       key_weak_inc,       // 按键1：增加弱边缘阈值
	input                       key_weak_dec,       // 按键2：减少弱边缘阈值
	input                       switch_threshold_select, // 乒乓开关1：选择控制阈值类型（0=强边缘，1=弱边缘）
	input                       switch_step_size,   // 乒乓开关2：选择调整步长（0=25，1=10）

	// 输出信号
	output                      hs_r,               // 延迟后的水平同步信号
	output                      vs_r,               // 延迟后的垂直同步信号
	output                      de_r,               // 延迟后的视频有效信号
	output[DATA_WIDTH - 1:0]    vout_data           // 处理后的视频数据
);

// ============================================================================
// 灰度转换权重参数
// 注意：这里使用简化算法，实际使用的是平均值法而非标准权重法
// ============================================================================
localparam R_WEIGHT = 8'd76;   // 标准权重：0.299 * 256
localparam G_WEIGHT = 8'd150;  // 标准权重：0.587 * 256
localparam B_WEIGHT = 8'd29;   // 标准权重：0.114 * 256

// ============================================================================
// 阈值参数和按键处理
// ============================================================================
reg [10:0] strong_threshold;    // 强边缘阈值寄存器
reg [10:0] weak_threshold;      // 弱边缘阈值寄存器
reg [1:0] key_sync;             // 按键同步寄存器（2位）
wire [1:0] key_press;           // 按键按下信号（2位）
reg [10:0] step_size;           // 步长寄存器

// 初始阈值设置
initial begin
    strong_threshold = 11'd1450; // 初始强边缘阈值
    weak_threshold = 11'd1075;   // 初始弱边缘阈值
end

// ============================================================================
// 行缓存器定义
// 用于Sobel边缘检测，需要存储2行图像数据
// ============================================================================
reg [7:0] line_buffer_0 [0:H_SIZE-1];  // 行缓存器0
reg [7:0] line_buffer_1 [0:H_SIZE-1];  // 行缓存器1

// ============================================================================
// 控制信号定义
// ============================================================================
reg [10:0] pixel_counter;       // 像素计数器，记录当前行中的像素位置
reg line_buffer_valid;          // 行缓存有效标志，表示至少有一行数据可用
reg line_buffer_select;         // 行缓存选择：0-使用buffer0，1-使用buffer1
reg vs_d0, vs_d1;               // 垂直同步信号的延迟寄存器，用于边沿检测

// ============================================================================
// Sobel处理流水线寄存器
// ============================================================================
reg [7:0] gray_pixel;           // 灰度像素值
reg [7:0] window [0:8];         // 3x3滑动窗口，用于Sobel卷积计算
reg [10:0] gx, gy;              // Sobel算子的x方向和y方向梯度（11位有符号数，范围：-1020到+1020）
reg [10:0] gradient;            // 梯度幅值（11位无符号数，范围：0到2040）
reg [7:0] edge_result;          // 边缘检测结果

// ============================================================================
// 同步信号延迟链
// 用于保持视频时序信号的同步
// ============================================================================
reg [20:0] hs_d;                // 水平同步延迟链
reg [20:0] vs_d;                // 垂直同步延迟链
reg [20:0] de_d;                // 数据有效延迟链
reg [DATA_WIDTH - 1:0] vout_data_r;  // 输出数据寄存器

// ============================================================================
// 椒盐噪声消除相关定义
// ============================================================================
reg [7:0] prev_edge_result;           // 前一个边缘检测结果
reg noise_removed_result;             // 噪声消除后的结果

// 循环计数器
integer i;

// ============================================================================
// RGB到灰度转换模块
// 功能：将24位RGB数据转换为8位灰度数据
// 算法：使用标准亮度公式 Gray = 0.299R + 0.587G + 0.114B
// ============================================================================
wire [15:0] weighted_sum;  // 加权和中间变量
assign weighted_sum = (R_WEIGHT * read_data[23:16]) +
                     (G_WEIGHT * read_data[15:8]) +
                     (B_WEIGHT * read_data[7:0]);

always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位时清零灰度像素值
		gray_pixel <= 8'b0;
	end else if (de) begin
		// 使用标准亮度公式，提高视觉准确性
		// Gray = (76*R + 150*G + 29*B) >> 8 (相当于除以256)
		gray_pixel <= weighted_sum[15:8];  // 取高8位，相当于除以256
	end
end

// ============================================================================
// 行缓存管理模块
// 功能：管理两个行缓存器的读写操作，实现图像数据的行缓冲
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位初始化
		pixel_counter <= 0;
		line_buffer_select <= 0;
		line_buffer_valid <= 0;
		vs_d0 <= 0;
		vs_d1 <= 0;
	end else begin
		// VS边沿检测，用于帧复位
		vs_d0 <= vs;
		vs_d1 <= vs_d0;
		
		if (vs_d0 & ~vs_d1) begin // VS下降沿（帧结束）
			// 新帧开始，重置计数器
			pixel_counter <= 0;
			line_buffer_select <= 0;
			line_buffer_valid <= 0;
		end else if (de) begin
			// 写入当前行缓存器
			if (line_buffer_select == 0) begin
				line_buffer_0[pixel_counter] <= gray_pixel;
			end else begin
				line_buffer_1[pixel_counter] <= gray_pixel;
			end
			
			// 像素计数器递增
			pixel_counter <= pixel_counter + 1;
			
			// 行结束时切换行缓存器
			if (pixel_counter == H_SIZE-1) begin
				pixel_counter <= 0;
				line_buffer_select <= ~line_buffer_select;  // 切换缓存器
				line_buffer_valid <= 1;  // 标记行缓存有效
			end
		end
	end
end

// ============================================================================
// 3x3滑动窗口形成模块
// 功能：为Sobel算子构建3x3的像素窗口
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位时清空窗口
		for (i = 0; i < 9; i = i + 1) begin
			window[i] <= 8'b0;
		end
	end else if (de && line_buffer_valid && pixel_counter >= 1 && pixel_counter < H_SIZE-1) begin
		// 为Sobel卷积构建3x3窗口（非边界像素）
		
		// 上一行像素（来自另一个缓存器）
		window[0] <= (line_buffer_select == 0) ? line_buffer_1[pixel_counter-1] : line_buffer_0[pixel_counter-1];
		window[1] <= (line_buffer_select == 0) ? line_buffer_1[pixel_counter]   : line_buffer_0[pixel_counter];
		window[2] <= (line_buffer_select == 0) ? line_buffer_1[pixel_counter+1] : line_buffer_0[pixel_counter+1];
		
		// 当前行像素
		window[3] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter-1] : line_buffer_1[pixel_counter-1];
		window[4] <= gray_pixel; // 中心像素（当前像素）
		window[5] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter+1] : line_buffer_1[pixel_counter+1];
		
		// 下一行像素（来自当前行缓存器）
		window[6] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter-1] : line_buffer_1[pixel_counter-1];
		window[7] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter]   : line_buffer_1[pixel_counter];
		window[8] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter+1] : line_buffer_1[pixel_counter+1];
	end else if (de) begin
		// 边界像素处理：使用当前灰度像素填充整个窗口
		for (i = 0; i < 9; i = i + 1) begin
			window[i] <= gray_pixel;
		end
	end
end

// ============================================================================
// Sobel卷积计算模块
// 功能：使用标准Sobel算子计算图像的梯度幅值并进行边缘检测
//
// 标准Sobel算子权重：
// Gx方向（水平边缘检测）：
//   [ -1  0  1 ]
//   [ -2  0  2 ]
//   [ -1  0  1 ]
// 对应窗口索引：window[0,1,2,3,4,5,6,7,8]
// Gx = (window[2] - window[0]) + ((window[5] - window[3]) << 1) + (window[8] - window[6])
//
// Gy方向（垂直边缘检测）：
//   [ -1 -2 -1 ]
//   [  0  0  0 ]
//   [  1  2  1 ]
// Gy = (window[0] - window[6]) + ((window[1] - window[7]) << 1) + (window[2] - window[8])
// ============================================================================

// gx：计算x方向梯度
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		gx <= 11'd0;
	end else if (de) begin
		// 标准Sobel算子Gx计算
		gx <= (window[2] - window[0]) + ((window[5] - window[3]) << 1) + (window[8] - window[6]);
	end else begin
		gx <= gx;
	end
end

// gy：计算y方向梯度
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		gy <= 11'd0;
	end else if (de) begin
		// 标准Sobel算子Gy计算
		gy <= (window[0] - window[6]) + ((window[1] - window[7]) << 1) + (window[2] - window[8]);
	end else begin
		gy <= gy;
	end
end

// gradient：梯度幅值计算
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		gradient <= 11'd0;
	end else if (de) begin
		// 根据Gx和Gy的符号计算绝对值之和
		if ((gx[10] == 1'b1) && (gy[10] == 1'b1)) begin
			// 两者都为负
			gradient <= (~gx[9:0] + 1'b1) + (~gy[9:0] + 1'b1);
		end else if ((gx[10] == 1'b1) && (gy[10] == 1'b0)) begin
			// Gx为负，Gy为正
			gradient <= (~gx[9:0] + 1'b1) + (gy[9:0]);
		end else if ((gx[10] == 1'b0) && (gy[10] == 1'b1)) begin
			// Gx为正，Gy为负
			gradient <= (gx[9:0]) + (~gy[9:0] + 1'b1);
		end else begin
			// 两者都为正
			gradient <= (gx[9:0]) + (gy[9:0]);
		end
	end else begin
		gradient <= gradient;
	end
end

// ============================================================================
// 按键同步和阈值调整模块
// ============================================================================

// 按键同步处理
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		key_sync <= 2'b0;
	end else begin
		// 按键同步，防止亚稳态
		key_sync <= {key_weak_inc, key_weak_dec};
	end
end

// 按键边沿检测
reg [1:0] key_sync_d;
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		key_sync_d <= 2'b0;
	end else begin
		key_sync_d <= key_sync;
	end
end

assign key_press = key_sync & ~key_sync_d;  // 上升沿检测

// 阈值调整逻辑
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位时恢复默认阈值
		strong_threshold <= 11'd1450;
		weak_threshold <= 11'd1075;
	end else begin
		// 根据乒乓开关2选择步长
		step_size <= switch_step_size ? 11'd10 : 11'd25;
		
		// 根据乒乓开关1选择调整的阈值类型
		if (switch_threshold_select) begin
			// 调整弱边缘阈值
			// 按键1：增加弱边缘阈值
			if (key_press[1] && (weak_threshold < strong_threshold - step_size)) begin
				weak_threshold <= weak_threshold + step_size;
			end
			// 按键2：减少弱边缘阈值
			else if (key_press[0] && (weak_threshold > step_size)) begin
				weak_threshold <= weak_threshold - step_size;
			end
		end else begin
			// 调整强边缘阈值
			// 按键1：增加强边缘阈值
			if (key_press[1] && (strong_threshold < 11'd2040 - step_size)) begin
				strong_threshold <= strong_threshold + step_size;
			end
			// 按键2：减少强边缘阈值
			else if (key_press[0] && (strong_threshold > weak_threshold + step_size)) begin
				strong_threshold <= strong_threshold - step_size;
			end
		end
	end
end

// edge_result：边缘检测结果量化
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		edge_result <= 8'd0;
	end else if (de) begin
		// 根据动态阈值进行边缘检测和结果量化
		if (gradient > strong_threshold) begin
			// 强边缘：输出最大值
			edge_result <= 8'hFF;
		end else if (gradient > weak_threshold) begin
			// 弱边缘：线性放大
			edge_result <= gradient[7:0] << 1;
		end else begin
			// 无边缘：输出0
			edge_result <= 8'h00;
		end
	end else begin
		edge_result <= edge_result;
	end
end

// ============================================================================
// 椒盐噪声消除模块
// 功能：使用简单的阈值判断消除椒盐噪声，极省资源
// 方法：如果当前像素是强边缘(255)但周围像素都是弱边缘或无边缘，则认为是噪声
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		prev_edge_result <= 8'd0;
		noise_removed_result <= 1'b0;
	end else if (de) begin
		// 保存前一个像素值
		prev_edge_result <= edge_result;
		
		// 简单的椒盐噪声消除逻辑
		// 如果当前像素是强边缘(255)但前一个像素是0，则认为是孤立噪声点
		if (edge_result == 8'hFF && prev_edge_result == 8'h00) begin
			noise_removed_result <= 1'b0;  // 消除噪声
		end else begin
			noise_removed_result <= (edge_result > 8'h00);  // 保持原有边缘
		end
	end
end

// ============================================================================
// 输出数据赋值模块（带边缘增强和简单噪声消除）
// 功能：将噪声消除后的边缘检测结果转换为RGB格式输出
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst == 1'b1) begin
		// 复位时清零输出数据
		vout_data_r <= {DATA_WIDTH{1'b0}};
	end else if (de_d[19]) begin // 匹配原始延迟时序
		// 将噪声消除后的边缘结果转换为RGB格式（灰度图像）
		// R=G=B=边缘强度值
		if (noise_removed_result) begin
			vout_data_r <= {8'hFF, 8'hFF, 8'hFF};  // 白色边缘
		end else begin
			vout_data_r <= {DATA_WIDTH{1'b0}};     // 黑色背景
		end
	end
end

// ============================================================================
// 同步信号延迟链模块
// 功能：保持视频时序信号的同步延迟
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位时清零所有延迟链
		hs_d <= 21'b0;
		vs_d <= 21'b0;
		de_d <= 21'b0;
	end else begin
		// 维持原始的20级延迟
		// 使用移位寄存器实现固定延迟
		hs_d <= {hs_d[19:0], hs};
		vs_d <= {vs_d[19:0], vs};
		de_d <= {de_d[19:0], de};
	end
end

// ============================================================================
// 输出信号赋值
// 注意：延迟级数的选择是为了匹配处理流水线的时序
// ============================================================================
assign read_en = de_d[18];  // 原始时序
assign hs_r = hs_d[20];     // 延迟20个时钟周期的HS
assign vs_r = vs_d[20];     // 延迟20个时钟周期的VS
assign de_r = de_d[20];     // 延迟20个时钟周期的DE
assign vout_data = vout_data_r;  // 输出处理后的视频数据

endmodule
