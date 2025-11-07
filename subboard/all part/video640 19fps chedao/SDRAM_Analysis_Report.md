# SDRAM 读写控制逻辑深入分析报告

## 执行摘要
通过对比两个参考例程（UDP例程lab_ex_4和OV5640例程lab_ex_5）与当前问题代码，发现当前0.9fps低帧率的根本原因在于**写入完成后的延迟太长**以及**读写转换逻辑不当**。

---

## 第一部分：参考例程1（UDP_EG4_6.2）分析

### 1. 文件位置与模块结构
- **文件**: `/app_wrrd.v`
- **功能**: SDRAM读写控制，使用状态机但不是显式的多态状态机
- **关键组件**:
  - `app_wrrd`: 写入FIFO和读取SDRAM的控制模块
  - 写入路径: FIFO → App_wr_en/App_wr_addr/App_wr_din
  - 读取路径: Sdr_rd_en → App_rd_en/App_rd_addr

### 2. 写入完成检测机制
```verilog
// 行141-151: 写入地址计数和完成标志
else if(App_wr_en & w_addr_cnt == 19'd307199)  // 307199 = 480*640 - 1
begin
    w_addr_cnt <= 19'b0;
    wr_done <= 1'b1;  // 一帧完成
end
```

**关键特征**:
- 当写入最后一个地址(307199)时，wr_done拉高
- 地址立即复位为0，为下一帧做准备
- **性质**: wr_done是一个脉冲信号，高1个时钟周期后自动归零（或需要特殊逻辑）

### 3. 写入到读取的延迟策略
```verilog
// 行153-163: 延迟计数器
reg [15:0] sdr_rd_delay;
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
        sdr_rd_delay <= 19'b0;
    end
    else if(wr_done & sdr_rd_delay < 19'd1000)  // 1000个周期延迟！
    begin
        sdr_rd_delay <= sdr_rd_delay + 1'b1;
    end
    else
        sdr_rd_delay <= sdr_rd_delay;
end
```

**关键发现**:
- **延迟1000个时钟周期** ≈ 20微秒@50MHz
- 这个延迟用于让SDRAM完成刷新和初始化
- 读取只有在 `(sdr_rd_delay == 1000)` 时才能开始

### 4. 读取请求条件（行204-214）
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay == 1000) & 
        !rd_done & (udp_wrusedw < 'd2048) & Sdr_init_ref_vld == 1'b0 & 
        burst_sdr_rd_cnt == 2'b0)
begin
    r_addr_cnt <= r_addr_cnt + 1'b1;
    app_rd_en_reg <= 1'b1;
end
```

**必需条件**:
1. Sdr_busy == 0（SDRAM空闲）
2. r_addr_cnt < 307199（未读完）
3. sdr_rd_delay == 1000（足够延迟）
4. rd_done == 0（上一次读未完成）
5. udp_wrusedw < 2048（UDP缓冲未满）
6. Sdr_init_ref_vld == 0（不在刷新）
7. burst_sdr_rd_cnt == 0（突发计数复位）

### 5. 突发读取机制
```verilog
// 行92-122: 突发计数器控制
reg [1:0] burst_sdr_rd_cnt;
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        burst_sdr_rd_cnt <= 2'b0;
    else if (app_rd_en_reg & (burst_sdr_rd_cnt < 3))
        burst_sdr_rd_cnt <= burst_sdr_rd_cnt + 1;
    else if (app_rd_en_reg & (burst_sdr_rd_cnt == 3))
        burst_sdr_rd_cnt <= 2'b0;
end
```

**特征**:
- 一次突发读4个数据（burst_sdr_rd_cnt从0-3）
- 完成后自动复位
- **关键**: 当burst_sdr_rd_cnt==3时，app_rd_en_reg拉低，暂停读取

---

## 第二部分：参考例程2（OV5640_HX4S20）分析

### 1. 文件位置与模块结构
- **文件**: 
  - `frame_read_write.v`（顶层整合）
  - `frame_fifo_write.v`（写入状态机）
  - `frame_fifo_read.v`（读取状态机）
- **架构**: 完全的**双状态机设计**，读写独立控制

### 2. 写入状态机（frame_fifo_write.v）

#### 2.1 状态定义（行42-48）
```verilog
localparam S_IDLE           = 0;  // 空闲
localparam S_ACK            = 1;  // 应答
localparam S_CHECK_FIFO     = 2;  // 检查FIFO
localparam S_WRITE_BURST    = 3;  // 突发写入
localparam S_WRITE_BURST_END = 4; // 突发完成
localparam S_END            = 5;  // 完成
```

#### 2.2 关键逻辑：进入突发条件（行70）
```verilog
wire into_burst = (((write_len_latch <= (rdusedw + write_cnt)) || 
                    rdusedw > BURST_SIZE) && ~App_rd_busy);
```

**含义**:
- 只有当写FIFO中有足够数据 **且** 读取器空闲时，才进入突发写
- App_rd_busy由读取状态机驱动！
- **这是读写分离的关键！**

#### 2.3 突发写入（行223-234）
```verilog
S_WRITE_BURST:
begin
    if(wr_burst_finish == 1'b1)  // burst_cnt >= BURST_SIZE
    begin
        App_wr_en_r <= 1'b0;
        state <= S_WRITE_BURST_END;
        write_cnt <= write_cnt + BURST_SIZE;  // 计数器递增
    end     
end
```

**特征**:
- BURST_SIZE = 256 字（大突发）
- 完成后进入S_WRITE_BURST_END等待状态

#### 2.4 写入完成判断（行236-252）
```verilog
S_WRITE_BURST_END:
begin
    if(write_req_d2 == 1'b1)
        state <= S_ACK;      // 新请求来临
    else if(write_cnt < write_len_latch)
        state <= S_CHECK_FIFO; // 继续写
    else
        state <= S_END;      // 写完成
end

S_END:
begin
    state <= S_IDLE;
end
```

### 3. 读取状态机（frame_fifo_read.v）

#### 3.1 状态定义（同样结构）
```verilog
localparam S_IDLE        = 0;
localparam S_ACK         = 1;
localparam S_CHECK_FIFO  = 2;
localparam S_READ_BURST  = 3;
localparam S_READ_BURST_END = 4;
localparam S_END         = 5;
```

#### 3.2 进入突发条件（行224）
```verilog
else if(wrusedw < (FIFO_DEPTH - BURST_SIZE) && ~App_wr_busy)
begin
    state <= S_READ_BURST;
    App_rd_en_r <= 1'b1;
end
```

**含义**:
- 读FIFO中要有足够空间（512 - 256 = 256）
- 写取器不在忙碌状态
- **互斥机制**: ~App_wr_busy确保写读不同时运行

#### 3.3 读取延迟机制（行71-80）
```verilog
wire rd_vld = (state == S_READ_BURST && burst_cnt >= BURST_SIZE);
assign rd_burst_finish = (rd_vld && rd_delay == 4'd10);

always @(posedge mem_clk or posedge rst)
begin
    if(rst || App_rd_en)
        rd_delay <= 4'd0;
    else if(rd_delay < 4'd10)  // 只有10个时钟周期！
        rd_delay <= rd_delay + 1'b1;
end
```

**特征**:
- **读取延迟只有10个时钟周期** ≈ 200纳秒@50MHz
- 这个延迟用于等待SDRAM数据有效
- **远短于UDP例程的1000周期！**

#### 3.4 读写互斥的关键信号流
```
frame_fifo_write 驱动: O_wr_busy → frame_read_write的App_wr_busy
frame_fifo_read 驱动: O_rd_busy → frame_read_write的App_rd_busy
                      Sdr_rd_en → 来自SDRAM控制器

读取检查 (line 224): wrusedw < (FIFO_DEPTH - BURST_SIZE) && ~App_wr_busy
写入检查 (line 70):  (write_len_latch <= (rdusedw + write_cnt)) && ~App_rd_busy
```

---

## 第三部分：当前代码（app_wrrd.v）问题分析

### 1. 关键问题1：wr_done信号的处理不当

**当前代码（行141-173）**:
```verilog
else if(App_wr_en & w_addr_cnt == 19'd307199)
begin
    w_addr_cnt <= 19'b0;
    wr_done <= 1'b1;
    wr_frame_cnt <= wr_frame_cnt + 1'b1;
end
else if(wr_done & !App_wr_en) begin
    w_addr_cnt <= 19'b0;
    wr_done <= 1'b1;  // 保持wr_done=1
    wr_frame_cnt <= wr_frame_cnt;
end
```

**问题**:
- wr_done被设置为1后，在 `wr_done & !App_wr_en` 条件下保持为1
- 这意味着wr_done会一直保持高！
- 结果：rd_done无法被清除，读取被永久阻塞

### 2. 问题2：frame_available的定义错误

**当前代码（行53）**:
```verilog
assign frame_available = (wr_frame_cnt != rd_frame_cnt);
```

**问题**:
- rd_frame_cnt永远无法增加（见问题1，rd_done被卡住）
- frame_available永远为1（因为wr_frame_cnt持续递增）
- 读取逻辑中检查frame_available无法正确工作

### 3. 问题3：延迟时间过长

**当前代码（行175-190）**:
```verilog
reg [19:0] sdr_rd_delay;
else if(wr_done & sdr_rd_delay < 20'd50000)  // 50000周期 ≈ 1毫秒！
    sdr_rd_delay <= sdr_rd_delay + 1'b1;
```

**问题**:
- 参考代码（UDP）是1000周期 ≈ 20微秒
- **当前代码是50000周期 ≈ 1毫秒**
- **增加了50倍的延迟！**
- 对于307200个数据点，即使每次读1个也需要307毫秒
- **加上延迟，每帧需要超过1秒 → 0.9 FPS**

### 4. 问题4：读取启动条件过于复杂

**当前代码（行248-262）**:
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay >= 20'd50000) & 
        (udp_wrusedw < 'd3500) & Sdr_init_ref_vld == 1'b0 & burst_sdr_rd_cnt == 2'b0)
begin
    r_addr_cnt <= r_addr_cnt + 1'b1;
    app_rd_en_reg <= 1'b1;
end
```

**问题**:
- udp_wrusedw < 3500 的检查可能导致读取频繁停止
- 多个突发计数器重置条件使读取不稳定
- **没有实现OV5640例程中的FIFO深度检查机制**

### 5. 问题5：缺少读写互斥机制

**参考代码特点**:
- UDP: 通过 `sdr_rd_delay==1000` 的单点控制确保不冲突
- OV5640: 通过App_wr_busy和App_rd_busy的互斥信号

**当前代码**:
- **完全缺乏读写互斥机制**
- 没有任何地方检查是否在读时停止写，或者在写时停止读
- 理论上可能同时发起读写请求！

---

## 第四部分：根本原因分析

### 帧处理时间计算

**参考例程（UDP）**:
```
写入时间: 307200个数据点 / 4个突发 = 76,800个写周期 ≈ 1,536微秒
延迟时间: 1,000个周期 ≈ 20微秒
读取时间: 307200个数据点 / 4个突发，间隔1000周期 ≈ 76,800 + 77,000 = 153,800微秒

总时间 ≈ 155毫秒 → 约6-7 FPS （实际会更高，因为读写重叠）
```

**当前代码**:
```
写入时间: 同上 ≈ 1,536微秒
延迟时间: 50,000个周期 ≈ 1,000微秒 （多了50倍！）
读取时间: 307200个数据点 / 4个突发 ≈ 76,800微秒

单帧时间: 1536 + 1000 + 76800 ≈ 79.3毫秒 → 约12 FPS

但考虑到wr_done被卡住，读取永不开始，实际FPS → 接近0
加上如果写入也因某种原因变慢 → 最终 ≈ 0.9 FPS
```

---

## 第五部分：正确设计方案

### 方案A：采用OV5640的双状态机设计（推荐）

优点:
- 清晰的读写分离
- 完整的互斥机制
- 经过实际产品验证
- 易于维护和调试

缺点:
- 需要重构代码
- 工作量大

### 方案B：修复当前设计（快速修复）

关键修改:

1. **修复wr_done逻辑**:
```verilog
else if(App_wr_en & w_addr_cnt == 19'd307199) begin
    w_addr_cnt <= 19'b0;
    wr_done <= 1'b1;      // 一个周期的脉冲
    wr_frame_cnt <= wr_frame_cnt + 1'b1;
end
else if(wr_done) begin
    wr_done <= 1'b0;      // 立即清除！
end
```

2. **减少延迟到合理值**:
```verilog
else if(wr_done & sdr_rd_delay < 20'd1500)  // 30微秒，参考值
    sdr_rd_delay <= sdr_rd_delay + 1'b1;
```

3. **简化读取条件**:
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & 
        (sdr_rd_delay >= 20'd1500) & !rd_done)
begin
    r_addr_cnt <= r_addr_cnt + 1'b1;
    app_rd_en_reg <= 1'b1;
end
```

4. **添加读写互斥**:
```verilog
// 添加读取禁止条件：当有新的写入请求时停止读取
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & 
        (sdr_rd_delay >= 20'd1500) & !rd_done & !writing_frame)
begin
    ...
end
```

---

## 第六部分：关键信号详解

### UDP例程的信号关系
```
sd_clk (SDRAM时钟) ─┐
                    ├─→ sdr_data_valid ─→ FIFO写入
                    └─→ sdr_data ────────→ FIFO数据

clk (系统时钟) ─────→ app_wrrd逻辑处理

写入路径:
sdr_data → fifo_sdr_data_2 → App_wr_din
           ↓
        rdusedw (读侧可用) → 触发App_wr_en
           ↓
        w_addr_cnt → App_wr_addr (自动递增)
           ↓
        wr_done ──→ 触发sdr_rd_delay计数

读取路径:
sdr_rd_delay==1000 ─→ 允许app_rd_en_reg拉高
                      ↓
                   burst_sdr_rd_cnt控制 (0-3)
                      ↓
                   r_addr_cnt → App_rd_addr
                      ↓
                   Sdr_rd_en ← SDRAM返回
```

### OV5640例程的信号关系
```
写端时钟: write_clk
读端时钟: read_clk  
SDRAM时钟: mem_clk ← 统一时钟！

状态机完全独立:
frame_fifo_write.state (6态) ↔ App_wr_busy
                              ↓
                        frame_fifo_read.state检查 ~App_wr_busy
                              ↓
                        frame_fifo_read.state (6态) ↔ O_rd_busy
                              ↓
                        frame_fifo_write检查 ~App_rd_busy

深度检查互斥:
写入: rdusedw (FIFO读侧剩余) 检查是否有足够数据
读取: wrusedw (FIFO写侧使用) 检查是否有足够空间

突发长度: 
写入: BURST_SIZE=256（line 10）
读取: BURST_SIZE=256（line 9）
```

---

## 第七部分：调试建议

### 关键观察点

1. **wr_done信号波形**:
   - 应该是1个时钟周期的脉冲
   - 如果一直为高，则存在问题1

2. **sdr_rd_delay计数**:
   - 应该线性从0增长到50000
   - 然后保持在50000
   - 如果增长过快或过慢，说明延迟参数不对

3. **frame_available信号**:
   - 应该在wr_done后拉高
   - 应该在rd_done后拉低
   - 如果总是为高，说明rd_frame_cnt未增加

4. **App_rd_en脉冲**:
   - 应该成组出现（突发4个）
   - 应该每组间隔足够时间
   - 应该有多个组（307200/4 = 76800组）

5. **UDP缓冲wrusedw**:
   - 应该逐渐增长然后稳定
   - 如果增长缓慢，说明读取速率不足

---

## 第八部分：参考代码框架对比

### UDP设计框架
```
优点:
- 简洁，容易理解
- 单时钟域
- 快速延迟（1000周期）

缺点:
- 没有显式的互斥机制
- 读写控制混在一起
- 难以扩展
```

### OV5640设计框架
```
优点:
- 清晰的分离关注点
- 显式的互斥机制（busy信号）
- 独立的FIFO和状态机
- 易于扩展到多帧缓冲

缺点:
- 代码较长
- 需要深度理解状态机
```

### 推荐选择
**对于当前问题，建议采取方案B（快速修复）**，然后逐步向OV5640架构迁移。

---

## 结论

当前0.9 FPS的根本原因是：
1. **延迟参数设置错误** (50000 vs 1000) → 增加了50倍时间
2. **wr_done逻辑缺陷** → 导致读取被永久阻塞
3. **缺乏读写互斥机制** → 理论上可能冲突
4. **frame_available判断不当** → 无法正确控制读取

修复这些问题，预期可以达到 **10+ FPS**。

