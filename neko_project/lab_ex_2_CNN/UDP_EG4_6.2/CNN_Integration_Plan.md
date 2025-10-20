# UDP图像接入CNN预处理层集成方案

## 系统架构

```
UDP接收 (80x100 RGB888)
    ↓
UDP RAM (存储RGB888图像)
    ↓
udp_to_cnn_adapter (RGB888→RGB565转换)
    ↓
PRE_LAYER (CNN预处理层)
    ↓
CNN处理链 (conv1→pool1→conv2→pool2→full→output)
    ↓
HDMI显示 (显示处理结果)
```

## 已创建的模块

### 1. udp_to_cnn_adapter.v
**功能**：将UDP RAM中的80x100 RGB888图像转换为PRE_LAYER需要的RGB565格式

**接口**：
- 输入：
  - `start_process`: 开始处理信号
  - `udp_rgb_data[23:0]`: 从UDP RAM读取的RGB888数据
- 输出：
  - `udp_ram_addr[12:0]`: UDP RAM读地址
  - `pre_data_in[15:0]`: RGB565数据给PRE_LAYER
  - `pre_ren_P2`: 数据有效信号
  - `process_done`: 处理完成信号

## 集成步骤

### 步骤1：修改app.v模块

需要在app.v中添加：

1. **实例化udp_to_cnn_adapter**
```verilog
// CNN adapter signals
wire [12:0] cnn_ram_addr;
wire [23:0] cnn_rgb_data;
wire [15:0] pre_data_in;
wire pre_ren_P2;
wire process_done;
reg start_process;

// UDP to CNN adapter
udp_to_cnn_adapter u_udp_to_cnn_adapter(
    .clk            (sys_clk),
    .rst_n          (reset),
    .start_process  (start_process),
    .process_done   (process_done),
    .udp_ram_addr   (cnn_ram_addr),
    .udp_rgb_data   (cnn_rgb_data),
    .pre_data_in    (pre_data_in),
    .pre_ren_P2     (pre_ren_P2)
);
```

2. **添加第二个RAM读端口用于CNN**
```verilog
// 原有的RAM实例需要改为双读端口
ram  u_ram (
    // Write port (UDP写入)
    .dia   (ram_data_1),
    .addra (wr_addr),
    .clka  (udp_rx_clk),
    .wea   (wr_en),
    .cea   (wr_en),

    // Read port 1 (VGA显示)
    .dob   (rgb),
    .addrb (addr),
    .clkb  (sys_clk),

    // Read port 2 (CNN处理) - 需要三端口RAM或使用仲裁
    .doc   (cnn_rgb_data),
    .addrc (cnn_ram_addr),
    .clkc  (sys_clk)
);
```

3. **实例化PRE_LAYER**
```verilog
// PRE_LAYER signals
wire [7:0] pre_dob;
wire [7:0] pre_dob_vga;
wire [8:0] pre_addr_P2;
wire pre_ren_Y748;

PRE_LAYER u_pre_layer(
    .clk        (sys_clk),
    .rst_n      (reset),
    .data_in    (pre_data_in),      // RGB565 from adapter
    .addrb      (10'd0),            // CNN读地址
    .ren_P2     (pre_ren_P2),       // 从adapter来的使能
    .ceb        (1'b1),
    .dob        (pre_dob),
    .addr_P2    (pre_addr_P2),
    .ren_Y748   (pre_ren_Y748),
    .addrb_vga  (vga_addr_pre),     // VGA读预处理结果
    .dob_vga    (pre_dob_vga)
);
```

### 步骤2：添加控制逻辑

```verilog
// 自动触发CNN处理（当UDP接收完成后）
reg rd_en_d1, rd_en_d2;
always @(posedge sys_clk or negedge reset) begin
    if (!reset) begin
        rd_en_d1 <= 1'b0;
        rd_en_d2 <= 1'b0;
        start_process <= 1'b0;
    end
    else begin
        rd_en_d1 <= rd_en;
        rd_en_d2 <= rd_en_d1;
        // 检测rd_en上升沿（UDP接收完成）
        if (rd_en_d1 && !rd_en_d2) begin
            start_process <= 1'b1;
        end
        else begin
            start_process <= 1'b0;
        end
    end
end
```

### 步骤3：修改显示输出

可以选择显示：
1. **原始UDP图像**（当前实现）
2. **CNN预处理后的灰度图**
3. **CNN最终识别结果**

```verilog
// 显示模式选择
parameter DISP_MODE_UDP = 2'd0;     // 显示原始UDP图像
parameter DISP_MODE_PRE = 2'd1;     // 显示预处理灰度图
parameter DISP_MODE_CNN = 2'd2;     // 显示CNN结果

reg [1:0] disp_mode;

// 根据模式选择显示内容
wire [23:0] disp_rgb;
assign disp_rgb = (disp_mode == DISP_MODE_UDP) ? rgb :
                  (disp_mode == DISP_MODE_PRE) ? {pre_dob_vga, pre_dob_vga, pre_dob_vga} :
                  24'hFFFFFF;  // CNN结果显示
```

## RAM配置注意事项

当前RAM配置：
- 地址宽度：13位（8192深度）
- 数据宽度：24位（RGB888）
- 端口：双端口（1写2读）

**问题**：需要同时支持VGA读和CNN读

**解决方案**：
1. **方案A**：使用时分复用（VGA和CNN轮流读）
2. **方案B**：使用真双端口RAM（推荐）
3. **方案C**：复制两份RAM（浪费资源）

## 数据流时序

```
时刻T0: UDP开始接收数据
时刻T1: UDP接收完成，rd_en=1
时刻T2: 检测到rd_en上升沿，start_process=1
时刻T3: udp_to_cnn_adapter开始读取RAM并转换
时刻T4: PRE_LAYER接收RGB565数据并转换为灰度图
时刻T5: CNN处理链开始处理
时刻T6: 处理完成，结果可显示
```

## 下一步工作

1. ✅ 创建udp_to_cnn_adapter模块
2. ⏳ 修改app.v集成所有模块
3. ⏳ 配置RAM为三端口或添加仲裁逻辑
4. ⏳ 添加显示模式切换
5. ⏳ 连接完整的CNN处理链
6. ⏳ 测试验证

## 注意事项

1. **时钟域**：
   - UDP接收：udp_rx_clk
   - VGA显示：sys_clk (pixel_clk)
   - CNN处理：sys_clk
   - 需要注意跨时钟域信号同步

2. **图像尺寸**：
   - UDP输入：80x100
   - PRE_LAYER期望：18x22（需要缩放或裁剪）
   - 或者修改PRE_LAYER支持80x100

3. **数据格式**：
   - UDP RAM：RGB888 (24位)
   - PRE_LAYER输入：RGB565 (16位)
   - PRE_LAYER输出：灰度 (8位)

## 当前状态

- ✅ UDP接收80x100图像正常工作
- ✅ VGA显示80x100图像正常工作
- ✅ 创建了udp_to_cnn_adapter桥接模块
- ⏳ 需要集成到app.v
- ⏳ 需要连接CNN处理链
- ⏳ 需要修改HDMI显示输出

## 文件清单

1. `udp_to_cnn_adapter.v` - UDP到CNN适配器（已创建）
2. `app.v` - 应用层模块（需要修改）
3. `PRE_LAYER.v` - CNN预处理层（已存在）
4. `vga_disp_rtl.v` - VGA显示模块（已修改支持80x100）
5. `ram.v` - 图像存储RAM（可能需要修改为三端口）
