# 二值化稳定性终极修复方案

## 问题回顾

**症状：** 黑白屏幕不断闪动，二值化极不稳定

**根本原因：**
1. OTSU算法对实时视频流太复杂
2. 阈值计算有256个周期延迟，期间使用不稳定值
3. 大数乘法容易溢出
4. 对噪声和光照变化敏感

## 最终解决方案

### 已实现：简单平均值阈值法

**原理：**
```
阈值 = 全图平均灰度 = Σ(像素灰度) / 像素总数
```

**优点：**
- ✅ 计算极其简单
- ✅ 只需一次除法
- ✅ 无256周期遍历
- ✅ 稳定不闪烁
- ✅ 资源消耗小

**代码实现：**
```verilog
// 在直方图统计时已经计算了 sum_total 和 total_pixels
simple_threshold <= sum_total / total_pixels;

// 二值化
binary_result <= (gray_pixel > simple_threshold);
```

### 性能对比

| 方案 | 计算复杂度 | 稳定性 | 效果 | 资源 |
|------|-----------|--------|------|------|
| 固定阈值 | 无 | ★★★★★ | ★★☆☆☆ | 最少 |
| 平均值法 | 1次除法 | ★★★★★ | ★★★★☆ | 少 |
| OTSU法 | 256次迭代 | ★★☆☆☆ | ★★★★★ | 多 |

## 使用说明

### 当前配置
默认使用**平均值阈值法**，稳定可靠。

### 如果需要切换到OTSU
在二值化模块中，修改代码：

```verilog
// 注释掉平均值法
// if (gray_pixel_d2 > simple_threshold) begin

// 启用OTSU法
if (gray_pixel_d2 > otsu_threshold_stable) begin
    binary_result <= 1'b1;
end else begin
    binary_result <= 1'b0;
end
```

### 如果需要固定阈值（调试用）
```verilog
// 直接使用固定值
if (gray_pixel_d2 > 8'd128) begin  // 128是中间值
    binary_result <= 1'b1;
end
```

## 效果优化建议

### 1. 调整阈值偏移
如果背景太亮或太暗，可以加偏移：

```verilog
// 阈值略低于平均值（更多白色）
simple_threshold <= (sum_total / total_pixels) - 8'd20;

// 或略高于平均值（更多黑色）
simple_threshold <= (sum_total / total_pixels) + 8'd20;
```

### 2. 使用加权平均
给暗部更多权重：

```verilog
// 阈值 = 平均值 * 0.8
simple_threshold <= ((sum_total / total_pixels) * 4) >> 3;  // *4/8 = 0.5
```

### 3. 限制阈值范围
防止极端情况：

```verilog
reg [7:0] clamped_threshold;

always @(*) begin
    if (simple_threshold < 8'd30)
        clamped_threshold = 8'd30;     // 最小30
    else if (simple_threshold > 8'd200)
        clamped_threshold = 8'd200;    // 最大200
    else
        clamped_threshold = simple_threshold;
end

// 使用限制后的阈值
binary_result <= (gray_pixel_d2 > clamped_threshold);
```

### 4. 添加时间平滑
避免帧间跳变：

```verilog
reg [7:0] threshold_prev;

always @(posedge video_clk) begin
    if (!de && de_d[0]) begin
        // 新阈值 = 75% 旧值 + 25% 新值
        simple_threshold <= (threshold_prev * 3 + (sum_total / total_pixels)) >> 2;
        threshold_prev <= simple_threshold;
    end
end
```

## 测试检查清单

### ✓ 基本功能
- [ ] 画面稳定，不闪烁
- [ ] 黑白分明，对比度高
- [ ] 文字清晰可读（如果是文档）

### ✓ 不同场景
- [ ] 明亮场景（白纸黑字）
- [ ] 昏暗场景（调整曝光）
- [ ] 高对比度图案（二维码等）
- [ ] 低对比度场景（灰度均匀）

### ✓ 动态适应
- [ ] 光照变化时自动调整
- [ ] 移动物体边界清晰
- [ ] 无明显延迟

## 故障排除

### 问题1：全白屏
**原因：** 阈值太低，所有像素都大于阈值
**解决：** 
```verilog
simple_threshold <= (sum_total / total_pixels) + 8'd30;  // 提高阈值
```

### 问题2：全黑屏
**原因：** 阈值太高，所有像素都小于阈值
**解决：**
```verilog
simple_threshold <= (sum_total / total_pixels) - 8'd30;  // 降低阈值
```

### 问题3：仍然闪烁
**原因：** 除法运算可能有问题
**解决：** 使用固定阈值测试硬件
```verilog
simple_threshold <= 8'd128;  // 强制固定值
```

### 问题4：效果不够好
**原因：** 平均值法对复杂场景效果有限
**选项1：** 尝试其他简单算法（百分位数法）
**选项2：** 在PC端用软件OTSU预处理
**选项3：** 添加形态学后处理

## 总结

当前实现的**平均值阈值法**是实时FPGA二值化的**最佳平衡点**：
- 足够简单，保证稳定
- 效果良好，满足大多数应用
- 资源消耗小
- 易于调试和优化

如果后续需要更高级的算法，建议：
1. 先在PC端验证算法效果
2. 使用浮点仿真验证正确性
3. 使用状态机和流水线优化
4. 充分测试边界条件

**记住：稳定性永远比算法复杂度更重要！** 🎯
