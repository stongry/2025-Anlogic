# ============================================================================
# SDC Timing Constraints for eth_ov5640 FPGA Project - 完整版
# ============================================================================

# 1. 创建主输入时钟
create_clock -name {clk_in} -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]

# 2. 创建网口RGMII接收时钟
create_clock -name {phy_rgmii_rx_clk} -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]

# 3. 自动派生所有PLL时钟
derive_clocks

# 4. 设置时钟组 - 明确标记异步时钟域
set_clock_groups -asynchronous \
    -group {clk_in} \
    -group {phy_rgmii_rx_clk} \
    -group [get_clocks {sys_pll_m0/pll_inst.clkc[*]}] \
    -group [get_clocks {video_pll_m0/pll_inst.clkc[*]}] \
    -group [get_clocks {UDP_TOP_u0/u_clk_gen/pll_inst.clkc[*]}]

# 5. 设置虚假路径（False Paths）
# 复位和按键
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {key1}]
set_false_path -from [get_ports {key2}]

# LED和调试信号
set_false_path -to [get_ports {led_data[*]}]
set_false_path -to [get_ports {dled[*]}]
set_false_path -to [get_ports {debug_out}]

# 6. 跨时钟域约束
# 彩条数据从phy1_rgmii_rx_clk到ext_mem_clk（通过FIFO）
set_max_delay -from [get_clocks {phy_rgmii_rx_clk}] -to [get_clocks {sys_pll_m0/pll_inst.clkc[0]}] 8.0
set_min_delay -from [get_clocks {phy_rgmii_rx_clk}] -to [get_clocks {sys_pll_m0/pll_inst.clkc[0]}] 0.0

# VGA读数据从ext_mem_clk到video_clk（通过FIFO）
set_max_delay -from [get_clocks {sys_pll_m0/pll_inst.clkc[0]}] -to [get_clocks {video_pll_m0/pll_inst.clkc[0]}] 8.0
set_min_delay -from [get_clocks {sys_pll_m0/pll_inst.clkc[0]}] -to [get_clocks {video_pll_m0/pll_inst.clkc[0]}] 0.0

# 7. 输入/输出延迟约束
# RGMII接口
set_input_delay -clock {phy_rgmii_rx_clk} -max 2.0 [get_ports {phy1_rgmii_rx_data[*]}]
set_input_delay -clock {phy_rgmii_rx_clk} -max 2.0 [get_ports {phy1_rgmii_rx_ctl}]
set_input_delay -clock {phy_rgmii_rx_clk} -min 0.5 [get_ports {phy1_rgmii_rx_data[*]}]
set_input_delay -clock {phy_rgmii_rx_clk} -min 0.5 [get_ports {phy1_rgmii_rx_ctl}]

# VGA输出
set_output_delay -clock [get_clocks {video_pll_m0/pll_inst.clkc[0]}] -max 2.0 [get_ports {vga_out_hs}]
set_output_delay -clock [get_clocks {video_pll_m0/pll_inst.clkc[0]}] -max 2.0 [get_ports {vga_out_vs}]
set_output_delay -clock [get_clocks {video_pll_m0/pll_inst.clkc[0]}] -max 2.0 [get_ports {vga_data[*]}]
set_output_delay -clock [get_clocks {video_pll_m0/pll_inst.clkc[0]}] -min 0.0 [get_ports {vga_out_hs}]
set_output_delay -clock [get_clocks {video_pll_m0/pll_inst.clkc[0]}] -min 0.0 [get_ports {vga_out_vs}]
set_output_delay -clock [get_clocks {video_pll_m0/pll_inst.clkc[0]}] -min 0.0 [get_ports {vga_data[*]}]

# 8. 多周期路径（如果有）
# 例如：某些控制信号可以有2个时钟周期的建立时间
# set_multicycle_path -setup 2 -from [get_pins {...}] -to [get_pins {...}]
