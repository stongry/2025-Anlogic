# 0.9 FPS问题快速修复指南

## 问题确认清单

- [ ] 当前测量到的FPS确实是0.9
- [ ] 使用的是`app_wrrd.v`的当前版本（包含wr_frame_cnt）
- [ ] SDRAM读写延迟参数是50000周期
- [ ] 已验证Sdr_init_done信号正常

## 快速修复步骤（预期效果：提升到10+ FPS）

### 修复1：wr_done逻辑（最关键）

**位置**: `/home/ysara/Desktop/video1/UDP_EG4_6.2/source_code/rtl/sdr/rtl/app_wrrd.v` 行141-173

**当前代码**:
```verilog
else if(wr_done & !App_wr_en) begin
    w_addr_cnt <= 19'b0;
    wr_done <= 1'b1;  // 错误！
    wr_frame_cnt <= wr_frame_cnt;
end
```

**替换为**:
```verilog
// 删除上面的else if块，改为在最后的else中处理
else begin
    w_addr_cnt <= w_addr_cnt;
    wr_done <= 1'b0;  // 关键：立即清除wr_done
    wr_frame_cnt <= wr_frame_cnt;
end
```

**验证方法**:
```bash
# 在GTKWave或类似工具中观察：
# wr_done 信号应该是 1 个时钟周期的脉冲
# 不应该保持为高
```

**预期改善**: 从永久阻塞到能够开始读取 → 性能提升50倍以上

---

### 修复2：延迟参数（重要）

**位置**: 行186-189

**当前代码**:
```verilog
else if(wr_done & sdr_rd_delay < 20'd50000)
    sdr_rd_delay <=sdr_rd_delay +1'b1;
```

**替换为**:
```verilog
else if(wr_done & sdr_rd_delay < 16'd1500)  // 改为1500（30微秒）或1000
    sdr_rd_delay <=sdr_rd_delay +1'b1;
```

**参数说明**:
- 1000周期 ≈ 20微秒（UDP参考值）
- 1500周期 ≈ 30微秒（保守值）
- 不要超过2000周期

**预期改善**: 单帧延迟从1毫秒减少到30微秒 → 性能提升33倍

---

### 修复3：读取启动条件（重要）

**位置**: 行248-252

**当前代码**:
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay >= 20'd50000) & 
        (udp_wrusedw < 'd3500) & Sdr_init_ref_vld == 1'b0 & burst_sdr_rd_cnt == 2'b0)
```

**替换为**:
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay >= 16'd1500) & 
        !rd_done & (udp_wrusedw < 'd2048) & Sdr_init_ref_vld == 1'b0 & burst_sdr_rd_cnt == 2'b0)
```

**关键改动**:
- 加入`!rd_done`检查
- 改`sdr_rd_delay >= 20'd50000` 为 `sdr_rd_delay >= 16'd1500`
- 改`udp_wrusedw < 'd3500` 为 `udp_wrusedw < 'd2048`

**预期改善**: 防止多次启动读取，避免缓冲溢出

---

### 修复4：类似读取条件（行253-257）

**当前代码**:
```verilog
else if (!Sdr_busy & r_addr_cnt < 19'd307199 &  (sdr_rd_delay >= 20'd50000) & 
        (udp_wrusedw < 'd3500) & Sdr_init_ref_vld == 1'b0 & 
        (burst_sdr_rd_cnt > 0 &  burst_sdr_rd_cnt < 3))
```

**替换为**:
```verilog
else if (!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay >= 16'd1500) & 
        !rd_done & (udp_wrusedw < 'd2048) & Sdr_init_ref_vld == 1'b0 & 
        (burst_sdr_rd_cnt > 0 &  burst_sdr_rd_cnt < 3))
```

---

## 验证修复的方法

### 方法1：使用逻辑分析仪（最好）

观察以下信号的波形:
```
wr_done          - 应该是1周期脉冲，不是保持高
sdr_rd_delay     - 应该从0线性增长到1500，然后保持
rd_done          - 应该在读取完成时拉高，然后复位
frame_available  - 应该在wr_done后拉高，rd_done后拉低
App_rd_en        - 应该成群出现（76800组，每组4个周期）
```

### 方法2：使用仿真（快速）

```bash
# 在仿真环境中运行修改后的代码
# 统计每1秒钟的帧数
# 应该看到帧数从接近0增加到10+
```

### 方法3：实时测试（最终验证）

```bash
# 编程到板子上，运行实际应用
# 使用网络工具或显示器观察帧率
# 应该看到明显的帧率提升
```

---

## 如果修复后仍不理想

### 继续排查清单

1. **检查sdr_rd_delay的初始化**
   - 确保在!wr_done时复位为0（行182-183）
   - 否则延迟计数器无法重启

2. **检查Sdr_init_ref_vld信号**
   - 这个信号是否正常？
   - SDRAM刷新会频繁打断读取吗？

3. **检查udp_wrusedw信号**
   - 这是来自网络侧的缓冲指示
   - 是否经常超过2048导致读取停止？
   - 解决方案：增大阈值到4096

4. **检查Sdr_busy信号**
   - 是否经常为1？
   - 如果是，SDRAM本身可能有问题

5. **检查sdr_rd_delay达到1500的时间**
   - 应该在写入完成后约30微秒
   - 用逻辑分析仪测量实际时间

### 性能分析工具

```bash
# 添加以下调试信号到GTKWave
//synthesis keep
wire [7:0]  wr_frame_cnt_debug = wr_frame_cnt;
wire [7:0]  rd_frame_cnt_debug = rd_frame_cnt;
wire [19:0] sdr_rd_delay_debug = sdr_rd_delay;
wire        frame_available_debug = frame_available;

// 计算帧率
// FPS = wr_frame_cnt增加的帧数 / 测量时间
```

---

## 预期结果

### 修复前
- FPS: 0.9
- wr_done: 永远为1（卡住）
- rd_frame_cnt: 从不增加
- sdr_rd_delay: 计数到50000
- 主要问题: 读取从不启动

### 修复后
- FPS: 10-15+（取决于其他因素）
- wr_done: 1周期脉冲
- rd_frame_cnt: 每读完一帧增加1
- sdr_rd_delay: 计数到1500
- 所有问题: 解决

---

## 完整修改清单

在`app_wrrd.v`中需要修改的行:

| 行号 | 当前 | 修改为 | 原因 |
|-----|------|-------|------|
| 149 | `wr_done <= 1'b1;` 在else if | 删除这个分支 | wr_done卡住 |
| 169 | `wr_done <= wr_done;` | `wr_done <= 1'b0;` | 清除wr_done脉冲 |
| 175 | `reg [19:0]sdr_rd_delay;` | `reg [15:0]sdr_rd_delay;` | 位宽足够 |
| 186 | `sdr_rd_delay < 20'd50000` | `sdr_rd_delay < 16'd1500` | 减少延迟 |
| 248 | `(sdr_rd_delay >= 20'd50000)` | `(sdr_rd_delay >= 16'd1500)` | 匹配新延迟 |
| 248 | 缺少`!rd_done` | 添加`!rd_done &` | 防止多次启动 |
| 248 | `(udp_wrusedw < 'd3500)` | `(udp_wrusedw < 'd2048)` | 参考UDP值 |
| 253 | `(sdr_rd_delay >= 20'd50000)` | `(sdr_rd_delay >= 16'd1500)` | 匹配新延迟 |
| 253 | `(udp_wrusedw < 'd3500)` | `(udp_wrusedw < 'd2048)` | 参考UDP值 |
| 258 | `(sdr_rd_delay >= 20'd50000)` | `(sdr_rd_delay >= 16'd1500)` | 匹配新延迟 |
| 258 | `(udp_wrusedw < 'd3500)` | `(udp_wrusedw < 'd2048)` | 参考UDP值 |
| 262 | `(sdr_rd_delay >= 20'd50000)` | `(sdr_rd_delay >= 16'd1500)` | 匹配新延迟 |
| 262 | `(udp_wrusedw < 'd3500)` | `(udp_wrusedw < 'd2048)` | 参考UDP值 |

---

## 测试验证流程

### Step 1: 代码修改
- [ ] 修改app_wrrd.v的上述12个位置
- [ ] 检查没有语法错误
- [ ] 保存备份：`cp app_wrrd.v app_wrrd.v.before_fix`

### Step 2: 仿真验证（如果可能）
- [ ] 在ModelSim或Vivado中仿真
- [ ] 检查波形：wr_done是否为脉冲
- [ ] 检查帧计数器是否递增

### Step 3: 综合与编程
- [ ] 重新综合FPGA设计
- [ ] 编程到开发板

### Step 4: 功能测试
- [ ] 运行网络应用
- [ ] 使用`iperf`或类似工具测量数据率
- [ ] 观察FPS提升

### Step 5: 长期稳定性测试
- [ ] 运行至少30分钟
- [ ] 检查帧率是否稳定
- [ ] 查看是否有掉帧或重复

---

## 如果仍然无法达到期望FPS

### 可能的后续优化

1. **增加突发长度**
   - 从4改为8或16
   - 需要修改`burst_sdr_rd_cnt`的位宽

2. **改进FIFO管理**
   - 检查fifo_sdr_data_2是否是瓶颈
   - 考虑增加FIFO深度

3. **优化网络侧缓冲**
   - 检查udp_wrusedw是否经常阻塞读取
   - 考虑增大缓冲深度

4. **迁移到OV5640架构**
   - 采用frame_fifo_read.v的设计
   - 获得更好的隔离和性能

---

## 风险评估

### 低风险修改
- wr_done逻辑修复 → 必须做，修复致命缺陷
- 延迟参数调整 → 安全，有参考代码

### 中等风险修改
- 读取条件添加 → 需要验证，但逻辑清晰
- UDP缓冲阈值调整 → 可能需要根据网络情况调整

### 建议方案
1. 首先应用低风险修改
2. 测试并观察结果
3. 如果FPS仍不足，再调整参数
4. 保留每个版本的备份

