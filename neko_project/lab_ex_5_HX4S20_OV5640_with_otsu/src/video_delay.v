// ============================================================================
// 视频处理模块 - OTSU自动阈值二值化
// 功能：将RGB视频信号转换为灰度图像，并使用OTSU算法进行自动阈值二值化
// 算法：大津法（OTSU）- 最大类间方差法
//       通过遍历所有可能的阈值，选择使类间方差最大的阈值进行二值化
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
// OTSU 算法相关参数定义
// ============================================================================
localparam GRAY_LEVELS = 256;   // 灰度级数（0-255）

// ============================================================================
// 控制信号定义
// ============================================================================
reg vs_d0, vs_d1;               // 垂直同步信号的延迟寄存器，用于边沿检测
reg frame_start;                // 帧开始信号
reg histogram_done;             // 直方图统计完成标志
reg otsu_calc_done;             // OTSU计算完成标志

// ============================================================================
// 灰度转换相关寄存器
// ============================================================================
reg [7:0] gray_pixel;           // 灰度像素值
reg [7:0] gray_pixel_d1;        // 灰度像素延迟1拍
reg [7:0] gray_pixel_d2;        // 灰度像素延迟2拍

// ============================================================================
// OTSU 算法处理寄存器
// ============================================================================
// 直方图统计
reg [19:0] histogram [0:255];   // 灰度直方图（每个灰度级的像素数量，20位足够1024*768）
reg [31:0] total_pixels;        // 总像素数

// OTSU 阈值计算
reg [7:0] otsu_threshold;       // OTSU计算得到的最佳阈值
reg [7:0] otsu_threshold_stable; // 稳定的阈值（用于实际二值化）
reg [7:0] simple_threshold;     // 简单平均值阈值（备用方案）
reg [8:0] calc_gray_level;      // 当前计算的灰度级（需要9位以表示256）
reg [31:0] sum_total;           // 所有像素灰度值的总和
reg [31:0] sum_background;      // 背景类灰度值的累加和
reg [31:0] weight_background;   // 背景类的权重（像素数）
reg [47:0] variance_max;        // 当前最大类间方差（48位足够）
reg [47:0] variance_current;    // 当前类间方差
reg signed [63:0] diff_temp;    // 临时差值变量

// 二值化结果
reg binary_result;              // 二值化结果（0或1）
reg binary_result_d1;           // 二值化延迟1拍
reg binary_result_d2;           // 二值化延迟2拍

// ============================================================================
// 降噪处理相关寄存器
// ============================================================================
reg [2:0] noise_window [0:2];   // 3x1降噪窗口（水平方向）
reg denoised_result;            // 降噪后的结果
reg [1:0] white_count;          // 窗口中白色像素计数

// ============================================================================
// 同步信号延迟链
// 用于保持视频时序信号的同步
// ============================================================================
reg [8:0] hs_d;                 // 水平同步延迟链（增加到9级支持降噪）
reg [8:0] vs_d;                 // 垂直同步延迟链
reg [8:0] de_d;                 // 数据有效延迟链
reg [DATA_WIDTH - 1:0] vout_data_r;  // 输出数据寄存器

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
		gray_pixel_d1 <= 8'b0;
		gray_pixel_d2 <= 8'b0;
	end else if (de) begin
		// 使用标准亮度公式，提高视觉准确性
		// Gray = (76*R + 150*G + 29*B) >> 8 (相当于除以256)
		gray_pixel <= weighted_sum[15:8];  // 取高8位，相当于除以256
		gray_pixel_d1 <= gray_pixel;
		gray_pixel_d2 <= gray_pixel_d1;
	end
end

// ============================================================================
// 帧同步检测模块
// 功能：检测新帧的开始，用于触发直方图统计和OTSU计算
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		vs_d0 <= 0;
		vs_d1 <= 0;
		frame_start <= 0;
	end else begin
		// VS边沿检测
		vs_d0 <= vs;
		vs_d1 <= vs_d0;
		
		// VS上升沿表示新帧开始
		if (vs_d0 & ~vs_d1) begin
			frame_start <= 1;
		end else begin
			frame_start <= 0;
		end
	end
end

// ============================================================================
// 灰度直方图统计模块
// 功能：统计每一帧图像中各个灰度级的像素数量
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位时清空直方图
		for (i = 0; i < 256; i = i + 1) begin
			histogram[i] <= 20'd0;
		end
		total_pixels <= 32'd0;
		sum_total <= 32'd0;
		histogram_done <= 0;
	end else if (frame_start) begin
		// 新帧开始，清空直方图准备重新统计
		for (i = 0; i < 256; i = i + 1) begin
			histogram[i] <= 20'd0;
		end
		total_pixels <= 32'd0;
		sum_total <= 32'd0;
		histogram_done <= 0;
	end else if (de) begin
		// 有效像素时，更新直方图
		histogram[gray_pixel] <= histogram[gray_pixel] + 1;
		total_pixels <= total_pixels + 1;
		sum_total <= sum_total + gray_pixel;
	end else if (!de && de_d[0] && total_pixels > 32'd1000 && !histogram_done) begin
		// de下降沿，且统计了足够像素，标记直方图统计完成
		histogram_done <= 1;
	end
end

// ============================================================================
// 简单平均值阈值计算模块（备用稳定方案）
// 功能：使用全局平均灰度作为阈值，简单稳定
// 优点：计算简单，无闪烁，资源消耗小
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		simple_threshold <= 8'd128;
	end else if (!de && de_d[0] && total_pixels > 32'd1000 && histogram_done) begin
		// 帧结束时计算平均灰度作为阈值
		// 使用右移来近似除法（更快）
		if (total_pixels[31:20] > 0) begin
			// 大图像：分子分母都右移减少位宽
			simple_threshold <= (sum_total >> 12) / (total_pixels >> 12);
		end else begin
			// 小图像：直接除法
			simple_threshold <= sum_total / total_pixels;
		end
	end
end

// ============================================================================
// OTSU 阈值计算模块（完整OTSU算法 - 如果简单阈值不够用）
// 功能：根据最大类间方差法计算最佳二值化阈值
//
// 算法说明：
// 对每个可能的阈值k (0-255):
//   w0 = sum(histogram[0:k])           背景权重
//   w1 = total_pixels - w0             前景权重  
//   m0 = sum(i*histogram[i], i=0:k)/w0 背景均值
//   m1 = sum(i*histogram[i], i=k+1:255)/w1 前景均值
//   variance = w0 * w1 * (m0 - m1)²    类间方差
//
// 简化公式避免除法：
//   variance_simplified = (sum_total*w0 - sum_back*total)² / (w0*w1)
//   比较时只需比较分子：(sum_total*w0 - sum_back*total)²
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		calc_gray_level <= 9'd0;
		otsu_threshold <= 8'd128;
		otsu_threshold_stable <= 8'd128;
		variance_max <= 48'd0;
		weight_background <= 32'd0;
		sum_background <= 32'd0;
		otsu_calc_done <= 0;
		variance_current <= 48'd0;
		diff_temp <= 64'd0;
	end else if (histogram_done && !otsu_calc_done) begin
		// 直方图统计完成后，开始遍历计算OTSU阈值
		if (calc_gray_level <= 9'd255) begin
			// 第一步：累加当前灰度级的统计信息
			if (calc_gray_level < 9'd256) begin
				weight_background <= weight_background + histogram[calc_gray_level[7:0]];
				sum_background <= sum_background + (calc_gray_level[7:0] * histogram[calc_gray_level[7:0]]);
			end
			
			// 第二步：计算类间方差（使用上一周期累加的结果）
			if (calc_gray_level > 0 && weight_background > 0 && weight_background < total_pixels) begin
				// 计算差值：sum_total*w0 - sum_back*total
				diff_temp <= $signed(sum_total * weight_background) - $signed(sum_background * total_pixels);
				
				// 计算方差（差值的平方，除以权重乘积）
				// 为简化，只比较分子部分（因为都要除以w0*w1）
				variance_current <= (diff_temp[63]) ? 
				                    ((-diff_temp) * (-diff_temp)) >> 16 :  // 负数取绝对值
				                    (diff_temp * diff_temp) >> 16;         // 右移16位防止溢出
				
				// 更新最大方差和对应阈值
				if (variance_current > variance_max) begin
					variance_max <= variance_current;
					otsu_threshold <= calc_gray_level[7:0] - 1;  // 使用前一个灰度级作为阈值
				end
			end
			
			calc_gray_level <= calc_gray_level + 1;
		end else begin
			// 遍历完成，更新稳定阈值
			otsu_calc_done <= 1;
			
			// 阈值有效性检查：确保在合理范围内
			if (otsu_threshold > 8'd10 && otsu_threshold < 8'd245) begin
				otsu_threshold_stable <= otsu_threshold;
			end
			// 如果阈值不合理，保持原值不变
		end
	end else if (frame_start) begin
		// 新帧开始，重置计算状态
		calc_gray_level <= 9'd0;
		variance_max <= 48'd0;
		weight_background <= 32'd0;
		sum_background <= 32'd0;
		otsu_calc_done <= 0;
		variance_current <= 48'd0;
		diff_temp <= 64'd0;
	end
end

// ============================================================================
// 二值化处理模块
// 功能：使用简单平均值阈值进行二值化（稳定方案）
// 如果需要更好效果，可以切换回 otsu_threshold_stable
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		binary_result <= 1'b0;
	end else if (de_d[2]) begin
		// 使用延迟2拍的灰度像素值与简单阈值比较
		// 方案1：使用简单平均值阈值（推荐，更稳定）
		if (gray_pixel_d2 > simple_threshold) begin
			binary_result <= 1'b1;  // 前景（白色）
		end else begin
			binary_result <= 1'b0;  // 背景（黑色）
		end
		
		// 方案2：如果要使用OTSU阈值，注释掉上面的代码，取消下面的注释
		// if (gray_pixel_d2 > otsu_threshold_stable) begin
		//     binary_result <= 1'b1;
		// end else begin
		//     binary_result <= 1'b0;
		// end
	end
end

// ============================================================================
// 水平方向中值滤波降噪模块
// 功能：使用3x1滑动窗口进行中值滤波，消除椒盐噪声
// 原理：如果一个像素与相邻像素不同，则认为是噪声
//       中值滤波：取3个像素中的中间值
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		binary_result_d1 <= 1'b0;
		binary_result_d2 <= 1'b0;
		for (i = 0; i < 3; i = i + 1) begin
			noise_window[i] <= 3'b0;
		end
		denoised_result <= 1'b0;
		white_count <= 2'b0;
	end else if (de_d[3]) begin
		// 构建3x1水平滑动窗口
		binary_result_d1 <= binary_result;
		binary_result_d2 <= binary_result_d1;
		
		noise_window[0] <= {noise_window[0][1:0], binary_result_d2};
		noise_window[1] <= {noise_window[1][1:0], binary_result_d1};
		noise_window[2] <= {noise_window[2][1:0], binary_result};
		
		// 方法1：中值滤波（取中间值）
		// 统计3x3窗口中的白色像素数量
		white_count <= noise_window[0][0] + noise_window[0][1] + noise_window[0][2] +
		               noise_window[1][0] + noise_window[1][1] + noise_window[1][2] +
		               noise_window[2][0] + noise_window[2][1] + noise_window[2][2];
		
		// 如果白色像素 >= 5个（过半），则输出白色，否则黑色
		denoised_result <= (white_count >= 2'd5) ? 1'b1 : 1'b0;
		
		// 方法2：简单的3点中值（只看水平方向，更快）
		// 取消下面注释可启用简单模式
		// denoised_result <= (noise_window[1][0] + noise_window[1][1] + noise_window[1][2] >= 2'd2) ? 1'b1 : 1'b0;
	end
end

// ============================================================================
// 形态学处理模块（腐蚀+膨胀，可选）
// 功能：先腐蚀去除小白点，再膨胀恢复边缘
// 注意：需要额外资源，如果资源紧张可以注释掉
// ============================================================================
reg morphology_result;

always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		morphology_result <= 1'b0;
	end else if (de_d[4]) begin
		// 简单腐蚀：如果周围有黑点，则变黑（去除孤立白点）
		if (white_count >= 2'd8) begin  // 全是白色才保持白色
			morphology_result <= 1'b1;
		end else if (white_count <= 2'd1) begin  // 几乎全黑则保持黑色
			morphology_result <= 1'b0;
		end else begin
			morphology_result <= denoised_result;  // 中间情况保持原值
		end
	end
end

// ============================================================================
// 输出数据赋值模块（降噪后的二值化结果）
// 功能：将降噪后的二值化结果转换为RGB格式输出
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst == 1'b1) begin
		// 复位时清零输出数据
		vout_data_r <= {DATA_WIDTH{1'b0}};
	end else if (de_d[8]) begin
		// 将降噪后的二值化结果转换为RGB格式
		// 方案1：使用中值滤波结果（推荐）
		if (denoised_result) begin
			vout_data_r <= {8'hFF, 8'hFF, 8'hFF};  // 白色（前景）
		end else begin
			vout_data_r <= {DATA_WIDTH{1'b0}};     // 黑色（背景）
		end
		
		// 方案2：使用形态学处理结果（更强降噪，但可能损失细节）
		// if (morphology_result) begin
		//     vout_data_r <= {8'hFF, 8'hFF, 8'hFF};
		// end else begin
		//     vout_data_r <= {DATA_WIDTH{1'b0}};
		// end
		
		// 方案3：不降噪，直接输出二值化结果
		// if (binary_result) begin
		//     vout_data_r <= {8'hFF, 8'hFF, 8'hFF};
		// end else begin
		//     vout_data_r <= {DATA_WIDTH{1'b0}};
		// end
	end
end

// ============================================================================
// 同步信号延迟链模块
// 功能：保持视频时序信号的同步延迟（增加到9级以匹配降噪处理）
// ============================================================================
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		// 复位时清零所有延迟链
		hs_d <= 9'b0;
		vs_d <= 9'b0;
		de_d <= 9'b0;
	end else begin
		// 使用移位寄存器实现固定延迟
		hs_d <= {hs_d[7:0], hs};
		vs_d <= {vs_d[7:0], vs};
		de_d <= {de_d[7:0], de};
	end
end

// ============================================================================
// 输出信号赋值
// 注意：延迟级数的选择是为了匹配处理流水线的时序
// ============================================================================
assign read_en = de_d[7];       // 提前读使能
assign hs_r = hs_d[8];          // 延迟8个时钟周期的HS
assign vs_r = vs_d[8];          // 延迟8个时钟周期的VS
assign de_r = de_d[8];          // 延迟8个时钟周期的DE
assign vout_data = vout_data_r;  // 输出处理后的视频数据

endmodule
