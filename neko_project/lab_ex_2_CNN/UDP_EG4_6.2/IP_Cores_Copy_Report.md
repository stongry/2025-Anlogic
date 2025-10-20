# CNN IP核复制完成报告

## 已复制的IP核列表

### RAM IP核（用于CNN数据存储）
1. **RAM03_512** - 3位数据宽度，512深度
2. **RAM04_1024** - 4位数据宽度，1024深度（预处理层使用）
3. **RAM12_128** - 12位数据宽度，128深度
4. **RAM12_512** - 12位数据宽度，512深度
5. **RAM12_1024** - 12位数据宽度，1024深度
6. **RAM14_256** - 14位数据宽度，256深度
7. **RAM20_191** - 20位数据宽度，191深度

### 其他IP核
1. **01.v / 02.v** - 自定义IP核
2. **ip_fifo** - FIFO缓冲器
3. **ip_pll** - 时钟PLL
4. **ip_ram** - 通用RAM
5. **ip_rom** - ROM存储器
6. **ip_sdram** - SDRAM控制器

### 数据文件
- **inst_data.mif.dat** - 初始化数据文件（278KB）

## 文件统计
- 总文件数：33个
- .v文件：16个
- .ipc文件：16个
- .dat文件：1个
- 总大小：约1MB

## 关键IP核说明

### RAM04_1024
- **用途**：PRE_LAYER中的RAM_Y_784
- **配置**：
  - 数据宽度：8位（灰度图）
  - 地址宽度：10位
  - 深度：1024（28x28=784，实际使用）
  - 端口：双端口（1写1读）

### 其他RAM
CNN各层使用不同配置的RAM存储中间结果：
- Conv1层：使用RAM12_xxx系列
- Pool1层：使用RAM14_256
- Conv2层：使用RAM20_191
- 全连接层：使用其他配置

## 复制位置
```
源目录：lab_ex_5_CNN/src/cnn/al_ip/
目标目录：UDP_EG4_6.2/source_code/rtl/cnn/al_ip/
```

## 下一步工作

### 1. 验证IP核兼容性
- [ ] 检查IP核版本是否与当前工具链兼容
- [ ] 验证.ipc配置文件
- [ ] 确认inst_data.mif.dat路径正确

### 2. 集成到项目
- [ ] 在项目文件中添加IP核路径
- [ ] 实例化PRE_LAYER（使用RAM04_1024）
- [ ] 连接CNN处理链

### 3. 测试验证
- [ ] 编译检查IP核是否正确加载
- [ ] 仿真验证数据流
- [ ] 硬件测试

## 注意事项

1. **路径问题**：
   - 确保项目设置中包含`source_code/rtl/cnn/al_ip`路径
   - inst_data.mif.dat的相对路径可能需要调整

2. **时钟域**：
   - 所有RAM使用sys_clk
   - 注意跨时钟域信号同步

3. **资源使用**：
   - CNN需要大量BRAM资源
   - 确保FPGA有足够的资源

## 文件清单

### RAM IP核
- RAM03_512.v / RAM03_512.ipc
- RAM04_1024.v / RAM04_1024.ipc ⭐（PRE_LAYER使用）
- RAM12_128.v / RAM12_128.ipc
- RAM12_512.v / RAM12_512.ipc
- RAM12_1024.v / RAM12_1024.ipc
- RAM14_256.v / RAM14_256.ipc
- RAM20_191.v / RAM20_191.ipc

### 通用IP核
- 01.v / 01.ipc
- 02.v / 02.ipc
- ip_fifo.v / ip_fifo.ipc / ip_fifo_sim.v
- ip_pll.v / ip_pll.ipc / ip_pll_sim.v
- ip_ram.v / ip_ram.ipc / ip_ram_sim.v
- ip_rom.v / ip_rom.ipc / ip_rom_sim.v
- ip_sdram.v / ip_sdram.ipc

### 数据文件
- inst_data.mif.dat

## 状态
✅ IP核复制完成
✅ 文件完整性验证通过
⏳ 等待集成到项目中
