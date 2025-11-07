# 视频处理流水线 - 延迟链说明（优化版）

## 延迟链定义（5级）

```verilog
reg [4:0] hs_d;  // 水平同步延迟链
reg [4:0] vs_d;  // 垂直同步延迟链
reg [4:0] de_d;  // 数据有效延迟链
```

## 处理流水线时序图

```
时钟周期:  T0    T1    T2    T3    T4    T5
         ----  ----  ----  ----  ----  ----
输入:     RGB
         |
灰度转换:  Gray
         |
延迟1:         Gray_d1
         |     |
延迟2:         |     Gray_d2
         |     |     |
3x1滤波:        |     |     Filtered
         |     |     |     |
延迟1:               |     |     Filtered_d1
         |     |     |     |     |
延迟2:               |     |     |     Filtered_d2
         |     |     |     |     |     |
二值化:                    |     |     |     Binary
         |     |     |     |     |     |     |
延迟1:                          |     |     |     Binary_d1
         |     |     |     |     |     |     |     |
延迟2:                          |     |     |     |     Binary_d2
         |     |     |     |     |     |     |     |     |
中值滤波:                             |     |     |     |     Denoised
         |     |     |     |     |     |     |     |     |     |
输出:                                            |     |     |     |     Output

同步信号:
de:      1     1     1     1     1     1
de_d[0]:       1     1     1     1     1
de_d[1]:             1     1     1     1
de_d[2]:                   1     1     1
de_d[3]:                         1     1
de_d[4]:                               1  <-- 输出同步
```

## 延迟链索引使用说明

### de_d[0] - 1拍延迟
**使用场景:**
```verilog
// 帧结束检测（de下降沿）
if (!de && de_d[0] && total_pixels > 32'd1000 && !histogram_done)
```
**含义:** 检测数据有效信号的下降沿（行/帧结束）

---

### de_d[2] - 3拍延迟
**使用场景:**
```verilog
// 二值化模块
if (de_d[2]) begin
    if (filtered_d2 > simple_threshold) begin
        binary_result <= 1'b1;
    end
end
```
**含义:** 
- 灰度像素经过3拍延迟 (gray_pixel → gray_pixel_d1 → gray_pixel_d2)
- 滤波值经过3拍延迟 (filtered → filtered_d1 → filtered_d2)
- 在此时刻进行二值化判断

---

### de_d[3] - 4拍延迟
**使用场景:**
```verilog
// 3x1中值滤波（第一级延迟）
if (de_d[3]) begin
    noise_window[2] <= noise_window[1];
    noise_window[1] <= noise_window[0];
    noise_window[0] <= binary_result;
end

// 读使能信号
assign read_en = de_d[3];
```
**含义:**
- 二值化结果 binary_result 已经生成
- 开始填充中值滤波窗口
- 提前读取下一个数据

---

### de_d[4] - 5拍延迟 (输出级)
**使用场景:**
```verilog
// 输出数据赋值
if (de_d[4]) begin
    if (denoised_result) begin
        vout_data_r <= {8'hFF, 8'hFF, 8'hFF};  // 白色
    end else begin
        vout_data_r <= {DATA_WIDTH{1'b0}};     // 黑色
    end
end

// 输出同步信号
assign hs_r = hs_d[4];
assign vs_r = vs_d[4];
assign de_r = de_d[4];
```
**含义:**
- 降噪完成，输出最终结果
- 同步信号与数据对齐

---

## 完整数据流延迟表

| 阶段 | 时钟周期 | 数据 | de_d索引 |
|-----|---------|------|---------|
| **输入** | T0 | RGB | de |
| **灰度转换** | T0 | gray_pixel | de |
| **灰度延迟1** | T1 | gray_pixel_d1 | de_d[0] |
| **灰度延迟2** | T2 | gray_pixel_d2 | de_d[1] |
| **3x1滤波** | T2 | filtered | de_d[1] |
| **滤波延迟1** | T3 | filtered_d1 | de_d[2] |
| **滤波延迟2** | T4 | filtered_d2 | de_d[2] |
| **二值化** | T4 | binary_result | de_d[2] |
| **二值化延迟1** | T5 | binary_result_d1 | de_d[3] |
| **二值化延迟2** | T6 | binary_result_d2 | de_d[4] |
| **3x1中值滤波** | T6 | denoised_result | de_d[4] |
| **输出** | T6 | vout_data_r | de_d[4] |

**总延迟:** 6个时钟周期（从RGB输入到最终输出）

---

## 与优化前的对比

### 优化前（9级延迟链）
```
总延迟: 9-12个时钟周期
原因:
  - 3x3高斯滤波需要行缓存 (3-4拍)
  - OTSU计算需要额外延迟 (1-2拍)
  - 3x3中值滤波 (2拍)
```

### 优化后（5级延迟链）
```
总延迟: 5-6个时钟周期
原因:
  - 3x1移动平均无需行缓存 (1拍)
  - 简单阈值计算无额外延迟 (0拍)
  - 3x1中值滤波 (1拍)
```

**延迟减少:** ~40-50%

---

## 时序约束建议

### 关键路径
```verilog
// 最长组合逻辑路径
filter_sum = gray_pixel + gray_pixel_d1 + gray_pixel_d2;  // 加法器
filtered = filter_sum / 3;                                 // 除法器

// 建议插入寄存器切分路径
```

### 时序约束
```tcl
# 假设视频时钟为74.25MHz (1080p60)
create_clock -period 13.468 [get_ports video_clk]

# 输入延迟约束
set_input_delay -clock video_clk -max 2.0 [get_ports {read_data[*] hs vs de}]

# 输出延迟约束  
set_output_delay -clock video_clk -max 2.0 [get_ports {vout_data[*] hs_r vs_r de_r}]
```

---

## 常见问题

### Q1: 为什么二值化使用 de_d[2] 而不是 de_d[3]?
**A:** 因为 `filtered_d2` 在 T4 时刻准备好，此时对应 `de_d[2]`。如果等到 `de_d[3]`，会增加1拍不必要的延迟。

### Q2: 为什么输出使用 de_d[4] 而不是 de_d[3]?
**A:** 因为中值滤波需要1拍来收集窗口数据，`denoised_result` 在 `de_d[4]` 时刻才稳定。

### Q3: 如果我想进一步减少延迟怎么办?
**A:** 可以考虑：
1. 移除中值滤波（减少1拍）
2. 移除3x1移动平均（减少1拍）
3. 使用组合逻辑二值化（减少1拍，但可能时序收敛困难）

最小延迟可以到3拍（仅灰度转换+二值化+输出缓冲）

### Q4: 为什么不能使用 de_d[5] 或更高?
**A:** 延迟链只定义了5位 `[4:0]`，最大索引是4。如果需要更多延迟，需要修改定义为 `reg [N:0] de_d`。

---

## 调试建议

### 使用ILA查看时序
```verilog
// 添加ILA探测点
ila_0 your_ila (
    .clk(video_clk),
    .probe0(de),
    .probe1(de_d[0]),
    .probe2(de_d[2]),
    .probe3(de_d[4]),
    .probe4(gray_pixel),
    .probe5(filtered),
    .probe6(binary_result),
    .probe7(denoised_result)
);
```

### 仿真测试
```verilog
// Testbench中检查延迟
initial begin
    repeat(10) @(posedge video_clk);
    de = 1;
    @(posedge video_clk);
    assert(de_d[0] == 1) else $error("de_d[0] timing error");
    @(posedge video_clk);
    assert(de_d[1] == 1) else $error("de_d[1] timing error");
    // ...
end
```

---

**作者:** GitHub Copilot  
**日期:** 2025-10-02  
**版本:** v1.0 (5级延迟链优化版)
