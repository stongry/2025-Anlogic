#!/usr/bin/env python3
"""
测试DPI缩放效果
"""

import tkinter as tk

def test_dpi_scaling():
    """测试DPI缩放"""
    root = tk.Tk()
    root.withdraw()  # 隐藏主窗口

    # 获取DPI信息
    dpi = root.winfo_fpixels('1i')
    scale_factor = dpi / 96.0

    print("=" * 60)
    print("DPI缩放测试")
    print("=" * 60)
    print(f"检测到DPI: {dpi:.2f}")
    print(f"缩放因子: {scale_factor:.2f}")
    print()

    # 测试各个尺寸
    test_sizes = [10, 20, 30, 40, 100, 200, 400, 800]

    print("原始尺寸 -> 缩放后尺寸")
    print("-" * 40)
    for size in test_sizes:
        scaled = int(size * scale_factor)
        print(f"{size:4d}px  -> {scaled:4d}px")

    print()
    print("=" * 60)
    print("窗口尺寸计算")
    print("=" * 60)

    base_width = 1100
    base_height = 820
    final_width = int(base_width * scale_factor)
    final_height = int(base_height * scale_factor)

    print(f"基准窗口: {base_width} x {base_height}")
    print(f"实际窗口: {final_width} x {final_height}")
    print()

    # 组件尺寸测试
    print("=" * 60)
    print("关键组件尺寸")
    print("=" * 60)

    components = {
        "主容器padding": 30,
        "网络配置卡片高度": 170,
        "连接按钮宽度": 120,
        "连接按钮高度": 44,
        "标题字体大小": 28,
        "副标题字体大小": 13,
        "占位符卡片高度": 450,
    }

    for name, size in components.items():
        scaled = int(size * scale_factor)
        print(f"{name:20s}: {size:4d}px -> {scaled:4d}px")

    print()
    print("=" * 60)
    print("✓ 缩放测试完成")
    print("=" * 60)

    root.destroy()

if __name__ == "__main__":
    test_dpi_scaling()
