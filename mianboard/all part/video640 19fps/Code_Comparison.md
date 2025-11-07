# SDRAM读写控制 - 代码行对行对比

## 1. 写入完成信号处理

### UDP例程 (lab_ex_4)
```verilog
// 行140-151
always @(posedge clk or negedge rst_n)           
begin                                        
    if(!rst_n) begin                              
        w_addr_cnt <= 19'b0;
        wr_done <=1'b0;
    end	                                   
    else if(App_wr_en & w_addr_cnt < 19'd307199)                                
        w_addr_cnt <=w_addr_cnt +1'b1;										 
    else if(App_wr_en & w_addr_cnt == 19'd307199) 
    begin
        w_addr_cnt <=19'b0;
        wr_done <=1'b1;
    end	
    else begin
        w_addr_cnt <=w_addr_cnt;
        wr_done <=wr_done;  // 保持状态
    end
end
```

**特征**:
- wr_done在最后一个地址时置1
- 在else分支中保持（hold）
- 后续逻辑负责清除这个信号

---

### 当前代码 (app_wrrd.v)
```verilog
// 行141-173
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b0;
        wr_frame_cnt <= 8'd0;
    end
    // 错误：这个条件会导致wr_done永远卡住！
    else if(wr_done & !App_wr_en) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b1;  // 再次置1，保持高
        wr_frame_cnt <= wr_frame_cnt;
    end
    else if(App_wr_en & w_addr_cnt < 19'd307199) begin
        w_addr_cnt <= w_addr_cnt + 1'b1;
        wr_done <= 1'b0;  // 正在写
        wr_frame_cnt <= wr_frame_cnt;
    end
    else if(App_wr_en & w_addr_cnt == 19'd307199) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b1;
        wr_frame_cnt <= wr_frame_cnt + 1'b1;
    end
    else begin
        w_addr_cnt <= w_addr_cnt;
        wr_done <= wr_done;
        wr_frame_cnt <= wr_frame_cnt;
    end
end
```

**问题分析**:
1. 当`wr_done=1 & App_wr_en=0`时，第一个条件匹配
2. 这会把wr_done再置为1（已经是1）
3. 这个条件会**持续匹配**，导致wr_done永远为1
4. 结果：rd_frame_cnt无法增加，读取被永久阻塞

---

### 修复方案
```verilog
// 方案1：使wr_done成为脉冲（推荐）
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b0;
        wr_frame_cnt <= 8'd0;
    end
    else if(App_wr_en & w_addr_cnt < 19'd307199) begin
        w_addr_cnt <= w_addr_cnt + 1'b1;
        wr_done <= 1'b0;
        wr_frame_cnt <= wr_frame_cnt;
    end
    else if(App_wr_en & w_addr_cnt == 19'd307199) begin
        w_addr_cnt <= 19'b0;
        wr_done <= 1'b1;      // 置1
        wr_frame_cnt <= wr_frame_cnt + 1'b1;
    end
    else begin
        w_addr_cnt <= w_addr_cnt;
        wr_done <= 1'b0;      // 下一个周期立即清除
        wr_frame_cnt <= wr_frame_cnt;
    end
end

// 或者方案2：使用第二个always块
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        wr_done <= 1'b0;
    else if(wr_done)
        wr_done <= 1'b0;  // 自动清除
    else if(App_wr_en & w_addr_cnt == 19'd307199)
        wr_done <= 1'b1;
end
```

---

## 2. 读取延迟时间对比

### UDP例程
```verilog
// 行159
else if(wr_done & sdr_rd_delay < 19'd1000)  // 注意：1000
    sdr_rd_delay <= sdr_rd_delay + 1'b1;
```
- **延迟**: 1000个周期 ≈ 20微秒@50MHz

### 当前代码
```verilog
// 行186
else if(wr_done & sdr_rd_delay < 20'd50000)  // 50000！
    sdr_rd_delay <= sdr_rd_delay + 1'b1;
```
- **延迟**: 50000个周期 ≈ 1毫秒@50MHz
- **倍数**: 增加50倍！

### 时间影响计算
```
单帧数据量: 480 * 640 = 307,200
突发大小: 4个数据

读取延迟影响:
UDP例程:   1000周期 = 20微秒
当前代码: 50000周期 = 1000微秒
增加时间: 980微秒/帧

读取时间计算（仅读取部分）:
307200 / 4 = 76,800个突发周期
UDP:       76,800 * 1000 / 4 = 19,200,000周期 = 384毫秒
当前代码: 76,800 * 50000 / 4 = 960,000,000周期 = 19.2秒

差异: 19秒 vs 384毫秒 → 约50倍！
```

### 修复建议
```verilog
// 参考UDP的参数
reg [15:0] sdr_rd_delay;  // 减少位宽
...
else if(wr_done & sdr_rd_delay < 16'd1000)  // 或1500
    sdr_rd_delay <= sdr_rd_delay + 1'b1;
```

---

## 3. 读取启动条件对比

### UDP例程 (行204-214)
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay == 1000) & 
        !rd_done & (udp_wrusedw < 'd2048) & Sdr_init_ref_vld == 1'b0 & 
        burst_sdr_rd_cnt == 2'b0)
begin
    r_addr_cnt <= r_addr_cnt + 1'b1;
    app_rd_en_reg <= 1'b1;
end
```

**条件列表**:
1. !Sdr_busy ..................... 检查SDRAM空闲
2. r_addr_cnt < 307199 ........... 检查未读完
3. sdr_rd_delay == 1000 .......... 检查延迟完成（精确值）
4. !rd_done ....................... 检查未完成
5. udp_wrusedw < 2048 ............ 检查输出缓冲
6. Sdr_init_ref_vld == 1'b0 ...... 检查不在刷新
7. burst_sdr_rd_cnt == 2'b0 ...... 检查突发计数复位

### 当前代码 (行248)
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay >= 20'd50000) & 
        (udp_wrusedw < 'd3500) & Sdr_init_ref_vld == 1'b0 & burst_sdr_rd_cnt == 2'b0)
```

**条件列表**:
1. !Sdr_busy .................... 相同
2. r_addr_cnt < 307199 ......... 相同
3. sdr_rd_delay >= 50000 ....... 检查延迟（>= 而非 ==）
4. 无 rd_done 检查 .............. 缺少！
5. udp_wrusedw < 3500 .......... 更高的阈值
6. Sdr_init_ref_vld == 1'b0 .... 相同
7. burst_sdr_rd_cnt == 2'b0 ... 相同

**问题**:
- 缺少 rd_done 检查
- 使用 >= 而非 == 会导致读取启动多次
- udp_wrusedw阈值太高，容易溢出

### 修复建议
```verilog
else if(!Sdr_busy & r_addr_cnt < 19'd307199 & (sdr_rd_delay >= 16'd1000) & 
        !rd_done & (udp_wrusedw < 'd2048) & Sdr_init_ref_vld == 1'b0 & 
        burst_sdr_rd_cnt == 2'b0)
begin
    r_addr_cnt <= r_addr_cnt + 1'b1;
    app_rd_en_reg <= 1'b1;
end
```

---

## 4. frame_available信号

### 当前代码设计
```verilog
// 行53
assign frame_available = (wr_frame_cnt != rd_frame_cnt);

// 行199-205: rd_frame_cnt只在这里更新
else if(Sdr_rd_en & sdr_rd_done_cnt == 19'd307199) begin
    sdr_rd_done_cnt <= 19'd0;
    sdr_en_done <= 1'b1;
    rd_frame_cnt <= rd_frame_cnt + 1'b1;  // 需要rd_done触发
end
```

**问题流程**:
1. wr_done卡住（问题1）
2. rd_frame_cnt无法增加
3. frame_available永远=1
4. 读取逻辑第237行的检查形同虚设

### 修复建议
```verilog
// 保持frame_available的定义
assign frame_available = (wr_frame_cnt != rd_frame_cnt);

// 但首先修复rd_frame_cnt的更新：
// 方案1：在读取完成时更新
else if(sdr_rd_done) begin
    rd_frame_cnt <= rd_frame_cnt + 1'b1;
    sdr_rd_done <= 1'b0;
end

// 方案2：基于rd_done完成
else if(rd_done) begin
    rd_frame_cnt <= rd_frame_cnt + 1'b1;
end
```

---

## 5. 读取完成判断对比

### UDP例程 (行173-183)
```verilog
else if(Sdr_rd_en & sdr_rd_done_cnt < 19'd307199)                                
begin
    sdr_rd_done_cnt <= sdr_rd_done_cnt + 1'b1;										 
end
else if(sdr_rd_done_cnt == 19'd307199) 
begin
    sdr_rd_done <= 1'b1;
end	
```

**特征**:
- 基于Sdr_rd_en（SDRAM有效读取）
- 计数到307199时置sdr_rd_done
- sdr_rd_done用于外部判断

### 当前代码 (行201-211)
```verilog
else if(Sdr_rd_en) begin
    if(sdr_rd_done_cnt == 19'd307199) begin
        sdr_rd_done_cnt <= 19'd0;
        sdr_en_done <= 1'b1;
        rd_frame_cnt <= rd_frame_cnt + 1'b1;
    end
    else begin
        sdr_rd_done_cnt <= sdr_rd_done_cnt + 1'b1;
        sdr_en_done <= 1'b0;
    end
end
```

**改进点**:
- 在307199时立即复位和标记（好）
- 在sdr_en_done为1时更新rd_frame_cnt（好）

但问题是：**rd_frame_cnt的更新依赖于wr_done信号的正确工作**，而目前wr_done有缺陷。

---

## 6. OV5640方案 vs 当前代码架构对比

### 信号流对比表

| 关键信号 | UDP例程 | OV5640例程 | 当前代码 |
|---------|--------|----------|--------|
| 读写互斥 | sdr_rd_delay==N | App_wr_busy/App_rd_busy | 无 |
| 写入FIFO | fifo_sdr_data_2 | wfifo_32_32_512 | fifo_sdr_data_2 |
| 读取FIFO | 无 | rfifo_32_32_512 | 无 |
| 突发长度 | 4 | 256 | 4 |
| 状态机 | 隐式 | 显式6态 | 隐式 |
| 延迟策略 | 单点延迟 | 读写独立 | 长延迟 |

### 架构优缺点

#### UDP例程
- 优: 简洁，清晰
- 缺: 没有显式互斥，难以扩展

#### OV5640例程
- 优: 清晰的读写分离，完整的互斥
- 缺: 代码复杂，需要理解6态机

#### 当前代码
- 优: 尝试融合两者
- 缺: 实现不完整，导致0.9 FPS

---

## 7. 修复优先级

### 第一级（关键缺陷）
1. **wr_done逻辑** - 导致永久阻塞
2. **延迟参数** - 导致50倍性能下降

### 第二级（重要问题）
3. **读取条件简化** - 移除不必要的检查
4. **frame_available用法** - 确保正确的状态转换

### 第三级（优化）
5. **读写互斥** - 添加显式互斥机制
6. **突发长度优化** - 考虑增大到256

