# OTSU算法稳定性修复说明

## 问题诊断

**原始问题：** 二值化效果差，大部分时间出现全白屏闪动，不稳定

**根本原因分析：**

1. **阈值计算时序问题** ⚠️
   - OTSU计算需要255个时钟周期
   - 在计算期间使用的是不稳定的中间值
   - 导致阈值剧烈跳变

2. **32位乘法溢出** ⚠️
   - 原公式：`(sum_total * weight_background - sum_background * total_pixels)²`
   - 对于1024×768图像，total_pixels ≈ 786,432
   - 乘法结果可能超过32位，导致溢出和错误阈值

3. **除法运算不稳定** ⚠️
   - 原代码中有除法：`/ (weight_background * (total_pixels - weight_background))`
   - FPGA中除法器资源消耗大且延迟高
   - 可能导致时序违例

## 修复方案

### 1. 添加稳定阈值寄存器

```verilog
reg [7:0] otsu_threshold;        // 计算中的阈值
reg [7:0] otsu_threshold_stable; // 稳定阈值（用于实际二值化）
```

**工作原理：**
- 计算过程中使用 `otsu_threshold` 
- 计算完成后，将结果复制到 `otsu_threshold_stable`
- 二值化只使用 `otsu_threshold_stable`，避免中间值干扰

### 2. 扩展位宽防止溢出

```verilog
reg [63:0] variance_max;        // 64位防止溢出
reg [63:0] variance_between;
reg [63:0] mean_diff_sq;        // 中间变量
```

**计算过程：**
- 使用64位存储类间方差
- 先计算均值差，再平方
- 处理有符号减法（取绝对值）

### 3. 消除除法运算

**原算法（有除法）：**
```verilog
variance = (a - b)² / (w0 * w1)
```

**改进算法（无除法）：**
```verilog
// 只比较分子部分
if ((a - b)² > variance_max) then
    variance_max = (a - b)²
    threshold = current_level
```

**数学依据：**
- 要找最大值，分母 `w0 * w1` 都是正数
- 分子越大，整体越大
- 直接比较分子即可，无需除法

### 4. 改进帧结束检测

**原代码（不可靠）：**
```verilog
if (de_d[0] == 0 && total_pixels > 0)
```

**改进代码：**
```verilog
if (!de && de_d[0] && total_pixels > 32'd1000)
```

- 检测 `de` 的下降沿（更准确）
- 要求至少统计1000个像素（避免误触发）

## 改进后的算法流程

```
帧N-1: 显示 ─────────────────────────────────────►
       (使用 otsu_threshold_stable = 120)

帧N:   直方图统计 → OTSU计算(255周期) → 更新stable → 显示
       统计中...      120→125→130→...→145    145      (使用145)
                      ↑不稳定中间值           ↑稳定

帧N+1: 显示 ─────────────────────────────────────►
       (使用 otsu_threshold_stable = 145)
```

**关键点：**
- 当前帧显示使用上一帧计算的稳定阈值
- 延迟一帧是可接受的（人眼感觉不到）
- 避免了阈值跳变导致的闪烁

## 调试建议

### 1. 监控阈值变化

在仿真或ChipScope中观察：
```verilog
otsu_threshold        // 应该在0-255平滑变化
otsu_threshold_stable // 应该稳定，偶尔跳变
variance_max          // 应该递增，找到峰值
```

### 2. 检查直方图统计

验证：
- `total_pixels` 是否接近图像总像素数
- `sum_total` 是否合理（应该在0到255*total_pixels之间）
- `histogram[i]` 分布是否符合预期

### 3. 测试场景

**好的测试图像：**
- ✅ 黑白文档
- ✅ 高对比度图案
- ✅ 二维码

**困难的测试图像：**
- ⚠️ 低对比度场景
- ⚠️ 灰度分布均匀的图像
- ⚠️ 噪声很多的图像

### 4. 参数调整

如果仍然不稳定，可以：

1. **增加阈值滤波：**
```verilog
// 只有变化超过阈值才更新
if (abs(otsu_threshold - otsu_threshold_stable) > 8'd10) begin
    otsu_threshold_stable <= otsu_threshold;
end
```

2. **使用移动平均：**
```verilog
// 平滑阈值变化
otsu_threshold_stable <= (otsu_threshold_stable * 3 + otsu_threshold) >> 2;
```

3. **限制阈值范围：**
```verilog
// 限制在合理范围
if (otsu_threshold < 8'd30) 
    otsu_threshold_stable <= 8'd30;
else if (otsu_threshold > 8'd200)
    otsu_threshold_stable <= 8'd200;
else
    otsu_threshold_stable <= otsu_threshold;
```

## 预期效果

修复后应该看到：
- ✅ 稳定的二值化图像
- ✅ 阈值在合理范围内（通常30-200）
- ✅ 画面不闪烁
- ✅ 自动适应光照变化

## 性能指标

- **延迟：** 一帧 + 6时钟周期
- **资源消耗：** 256×20bit RAM + 若干64位寄存器
- **更新频率：** 每帧更新一次阈值
- **稳定性：** 高（使用稳定阈值寄存器）

## 进一步优化（可选）

如果需要更快的阈值计算：
1. 使用流水线并行计算多个灰度级
2. 使用近似算法（如只计算0,4,8...等间隔灰度级）
3. 使用查找表预存部分计算结果

如果需要更好的二值化效果：
1. 添加形态学处理（腐蚀/膨胀）
2. 添加自适应局部阈值
3. 结合边缘检测信息
