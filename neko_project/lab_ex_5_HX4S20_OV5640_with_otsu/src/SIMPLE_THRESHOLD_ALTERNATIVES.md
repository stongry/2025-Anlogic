# 简化方案：替代OTSU的稳定二值化算法

如果OTSU仍然不稳定，建议使用以下更简单的方案：

## 方案1：全局平均值阈值法（最简单）

```verilog
// 使用全局平均灰度作为阈值
reg [7:0] mean_threshold;
reg [31:0] sum_gray;
reg [31:0] pixel_count;

always @(posedge video_clk) begin
    if (frame_start) begin
        sum_gray <= 0;
        pixel_count <= 0;
    end else if (de) begin
        sum_gray <= sum_gray + gray_pixel;
        pixel_count <= pixel_count + 1;
    end else if (!de && de_d[0] && pixel_count > 1000) begin
        // 计算平均值作为阈值
        mean_threshold <= sum_gray[31:8] / pixel_count[23:0];  // 简化除法
    end
end

// 二值化
always @(posedge video_clk) begin
    if (de_d[2]) begin
        binary_result <= (gray_pixel_d2 > mean_threshold);
    end
end
```

**优点：** 极其简单，资源少，无闪烁
**缺点：** 效果不如OTSU，但比不稳定的OTSU好

## 方案2：百分比阈值法

```verilog
// 使用中位数或特定百分位数作为阈值
// 统计直方图后，找到50%像素点对应的灰度值

reg [7:0] percentile_threshold;
reg [31:0] half_pixels;
reg [31:0] accumulated_pixels;

always @(posedge video_clk) begin
    if (histogram_done) begin
        half_pixels <= total_pixels >> 1;  // 50%
        accumulated_pixels <= 0;
        
        // 遍历直方图找中位数
        for (i = 0; i < 256; i = i + 1) begin
            accumulated_pixels <= accumulated_pixels + histogram[i];
            if (accumulated_pixels >= half_pixels && percentile_threshold == 0) begin
                percentile_threshold <= i;
            end
        end
    end
end
```

## 方案3：固定阈值（用于调试）

最简单的方法 - 先用固定阈值测试硬件是否正常：

```verilog
// 直接使用固定阈值128
always @(posedge video_clk) begin
    if (de_d[2]) begin
        binary_result <= (gray_pixel_d2 > 8'd128);
    end
end
```

## 方案4：增强型平均值法（推荐）

在平均值基础上加一个偏移：

```verilog
reg [7:0] adaptive_threshold;

always @(posedge video_clk) begin
    if (!de && de_d[0] && pixel_count > 1000) begin
        // 阈值 = 平均值 * 0.9（略低于平均）
        // 或者 = 平均值 + 偏移量
        adaptive_threshold <= (sum_gray / pixel_count) - 8'd20;
    end
end
```

## 推荐实现步骤

1. **先测试固定阈值** - 确认硬件工作正常
2. **使用平均值法** - 简单且稳定
3. **如果需要更好效果** - 再考虑OTSU或其他复杂算法

## 为什么OTSU不稳定？

1. **计算复杂** - 需要256个周期遍历
2. **时序敏感** - 累加和比较在同一周期容易出错
3. **除法运算** - 即使简化也容易溢出
4. **对噪声敏感** - 轻微的直方图变化导致阈值跳变

## 快速修复建议

暂时替换为简单的平均值法：

```verilog
// 在OTSU模块后添加这段代码作为备用
reg [7:0] simple_threshold;

always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        simple_threshold <= 8'd128;
    end else if (total_pixels > 1000 && histogram_done) begin
        // 使用全局平均灰度
        simple_threshold <= sum_total / total_pixels;
    end
end

// 二值化时使用simple_threshold替代otsu_threshold_stable
always @(posedge video_clk or posedge rst) begin
    if (rst) begin
        binary_result <= 1'b0;
    end else if (de_d[2]) begin
        binary_result <= (gray_pixel_d2 > simple_threshold);
    end
end
```

这样可以立即看到稳定的效果！
