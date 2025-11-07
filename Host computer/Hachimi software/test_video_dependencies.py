#!/usr/bin/env python3
"""
测试视频功能依赖库
"""

import sys

def test_imports():
    """测试所有必需的导入"""
    print("="*60)
    print("视频功能依赖库测试")
    print("="*60)
    print()

    errors = []

    # 测试numpy
    try:
        import numpy as np
        print("✓ NumPy: 已安装")
        print(f"  版本: {np.__version__}")
    except ImportError as e:
        print("✗ NumPy: 未安装")
        errors.append("numpy")

    # 测试PIL
    try:
        from PIL import Image, ImageTk
        print("✓ Pillow (PIL): 已安装")
        print(f"  版本: {Image.__version__ if hasattr(Image, '__version__') else 'Unknown'}")
    except ImportError as e:
        print("✗ Pillow (PIL): 未安装")
        errors.append("pillow")

    # 测试collections.deque
    try:
        from collections import deque
        print("✓ collections.deque: 已安装 (Python内置)")
    except ImportError as e:
        print("✗ collections.deque: 未找到")
        errors.append("collections")

    # 测试tkinter
    try:
        import tkinter as tk
        from tkinter import filedialog
        print("✓ Tkinter: 已安装 (Python内置)")
    except ImportError as e:
        print("✗ Tkinter: 未安装")
        errors.append("tkinter")

    # 测试socket
    try:
        import socket
        print("✓ socket: 已安装 (Python内置)")
    except ImportError as e:
        print("✗ socket: 未找到")
        errors.append("socket")

    # 测试threading
    try:
        import threading
        print("✓ threading: 已安装 (Python内置)")
    except ImportError as e:
        print("✗ threading: 未找到")
        errors.append("threading")

    print()
    print("="*60)

    if errors:
        print(f"❌ 发现 {len(errors)} 个缺失的库")
        print()
        print("安装命令:")
        if "numpy" in errors:
            print("  pip install numpy")
        if "pillow" in errors:
            print("  pip install pillow")
        print()
        return False
    else:
        print("✓ 所有依赖库已安装！")
        print()
        print("视频功能可用:")
        print("  • UDP视频流接收")
        print("  • 实时图像显示")
        print("  • FPS统计")
        print("  • 帧保存功能")
        print()
        return True


def test_basic_functionality():
    """测试基本功能"""
    print("="*60)
    print("基本功能测试")
    print("="*60)
    print()

    try:
        import numpy as np
        from PIL import Image

        # 创建测试图像
        print("测试1: 创建640x480 RGB图像...")
        img_array = np.random.randint(0, 256, (480, 640, 3), dtype=np.uint8)
        print(f"  数组形状: {img_array.shape}")
        print(f"  数组类型: {img_array.dtype}")
        print(f"  数据大小: {img_array.nbytes} 字节")
        print("  ✓ 测试通过")
        print()

        # 测试PIL转换
        print("测试2: NumPy数组转PIL Image...")
        pil_img = Image.fromarray(img_array)
        print(f"  图像大小: {pil_img.size}")
        print(f"  图像模式: {pil_img.mode}")
        print("  ✓ 测试通过")
        print()

        # 测试调整大小
        print("测试3: 调整图像大小...")
        resized = pil_img.resize((320, 240), Image.LANCZOS)
        print(f"  新大小: {resized.size}")
        print("  ✓ 测试通过")
        print()

        print("="*60)
        print("✓ 所有功能测试通过！")
        print("="*60)

    except Exception as e:
        print(f"❌ 测试失败: {e}")
        return False

    return True


if __name__ == "__main__":
    # 测试导入
    imports_ok = test_imports()

    if imports_ok:
        print()
        # 测试功能
        test_basic_functionality()
        print()
        print("准备就绪！可以使用视频接收功能。")
    else:
        print("请先安装缺失的库，然后重新运行此脚本。")
        sys.exit(1)
