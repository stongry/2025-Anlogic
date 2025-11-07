# 1. 创建主输入时钟
create_clock -name {clk_in} -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]

# 2. 创建网口时钟
create_clock -name {phy1_rgmii_rx_clk} -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]

# 3. 派生PLL时钟
derive_clocks

# 4. 重命名PLL输出时钟（sys_pll、video_pll、udp/pll_gen）
rename_clock -name {sys_pll_125M}   [get_clocks {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {sys_pll_125M_180} [get_clocks {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_pll_66M}  [get_clocks {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {video_pll_333M} [get_clocks {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {udp_pll_125M_0} [get_clocks {UDP_TOP_u0/udp_clk_gen/pll_inst.clkc[0]}]
rename_clock -name {udp_pll_125M_1} [get_clocks {UDP_TOP_u0/udp_clk_gen/pll_inst.clkc[1]}]
rename_clock -name {udp_pll_25M}    [get_clocks {UDP_TOP_u0/udp_clk_gen/pll_inst.clkc[3]}]

# 5. 创建生成时钟（如 UDP 专用时钟）
create_generated_clock -name {udp_clk_125m} \
    -source [get_pins {UDP_TOP_u0/udp_clk_gen/pll_inst.clkc[1]}] \
    -master_clock {udp_pll_125M_1} \
    -divide_by 1.000 \
    -phase 0.000 \
    -add [get_nets {UDP_TOP_u0/udp_clk}]

# 6. 设置时钟分组，避免异步时钟域分析
set_clock_groups -exclusive \
    -group [get_clocks {clk_in}] \
    -group [get_clocks {phy1_rgmii_rx_clk}] \
    -group [get_clocks {sys_pll_125M}] \
    -group [get_clocks {video_pll_66M}] \
    -group [get_clocks {udp_clk_125m}]

# 7. 可选：输入输出延迟约束（根据实际板级设计调整）
#set_input_delay -clock {clk_in} 5.0 [get_ports *]
#set_output_delay -clock {clk_in} 5.0 [get_ports *]