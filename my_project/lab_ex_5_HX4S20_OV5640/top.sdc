# ===================================================================
# SDC (Synopsys Design Constraints) File - Corrected Version
# ===================================================================

#**************************************************************
# 1. 定义主时钟 (Define Primary Clocks)
#**************************************************************

# 50 MHz 主系统时钟
create_clock -name {clk} -period 20.000 [get_ports {clk}]

# 125 MHz RGMII 接收时钟 (来自外部PHY芯片)
create_clock -name {phy1_rgmii_rx_clk} -period 8.000 [get_ports {phy1_rgmii_rx_clk}]

#**************************************************************
# 2. 自动派生并重命名衍生时钟 (Auto-derive and Rename Generated Clocks)
#**************************************************************

# 使用新的、正确的命令自动派生所有由PLL/MMCM生成的时钟
derive_clocks

# (关键!) 使用正确的语法重命名自动生成的时钟，以方便阅读报告
# 正确语法: rename_clock -to {新名字} [get_clocks -of_objects [get_pins {PLL输出引脚的真实路径}]]
# 注意：下面的层级路径需要你根据我们上次讨论的方法，用网表浏览器去确认最终的真实路径。

# --- 来自 PLL "sys_pll_m0" ---
rename_clock -to {ext_mem_clk} [get_clocks -of_objects [get_pins {sys_pll_m0/pll_inst.clkc[0]}]]
rename_clock -to {ext_mem_clk_sft} [get_clocks -of_objects [get_pins {sys_pll_m0/pll_inst.clkc[1]}]]

# --- 来自 PLL "video_pll_m0" ---
rename_clock -to {video_clk} [get_clocks -of_objects [get_pins {video_pll_m0/pll_inst.clkc[0]}]]
rename_clock -to {hdmi_5x_clk} [get_clocks -of_objects [get_pins {video_pll_m0/pll_inst.clkc[1]}]]

# --- 来自 Led_TOP 模块内部的 PLL "u_clk_gen/u_pll_0" ---
# 注意：这里的路径需要包含 Led_TOP 的实例名，例如 "Led_TOP_u0/"
rename_clock -to {temac_clk} [get_clocks -of_objects [get_pins {Led_TOP_u0/u_clk_gen/u_pll_0/pll_inst.clkc[0]}]]
rename_clock -to {clk_125_out} [get_clocks -of_objects [get_pins {Led_TOP_u0/u_clk_gen/u_pll_0/pll_inst.clkc[1]}]]
# ... 其他需要重命名的时钟 ...

#**************************************************************
# 3. 设置时钟分组 (Set Clock Groups) - 简化版
#**************************************************************

# 将所有源自同一个主时钟 `clk` 的衍生时钟视为一个同步组
# 将外部异步时钟 `phy1_rgmii_rx_clk` 视为另一个独立的组
# -exclusive 选项告诉工具，这两个组之间是异步关系，无需分析它们之间的路径

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks {clk}] \
    -group [get_clocks -include_generated_clocks {phy1_rgmii_rx_clk}]

#**************************************************************
# 4. 设置IO延迟和时序例外 (Set I/O Delays and Timing Exceptions)
#**************************************************************

# ... 在这里添加你的 set_input_delay, set_output_delay, set_false_path 等约束 ...