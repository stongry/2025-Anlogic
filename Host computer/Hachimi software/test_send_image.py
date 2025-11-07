#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SD卡图片接收测试脚本（增强版）
用于测试图片UDP发送功能，支持帧同步
"""

import socket
import numpy as np
import time
import sys

# 帧同步标识（与ethernet_host_gui.py中ImageReceiverThread保持一致）
FRAME_HEADER = b'\xAA\x55\xAA\x55'  # 帧头: 0xAA55AA55
FRAME_FOOTER = b'\x55\xAA\x55\xAA'  # 帧尾: 0x55AA55AA

def send_test_image(use_frame_sync=True):
    """发送测试图片到PC"""
    print("="*60)
    print(f"SD卡图片接收测试 - 发送端 ({'帧同步模式' if use_frame_sync else '直接模式'})")
    print("="*60)
    print()

    # 配置
    target_ip = "192.168.240.2"
    target_port = 3
    width = 640
    height = 480
    channels = 3

    print(f"目标IP:   {target_ip}")
    print(f"目标端口: {target_port}")
    print(f"图片尺寸: {width}×{height}")
    print(f"色彩格式: RGB ({channels}通道)")
    print(f"帧同步:   {'启用' if use_frame_sync else '禁用'}")
    print()

    try:
        # 创建UDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        print("✓ UDP Socket创建成功")

        # 生成测试图像（渐变色）
        print("✓ 生成测试图像（彩色渐变）...")
        img = np.zeros((height, width, channels), dtype=np.uint8)

        # 创建彩色渐变图像
        for y in range(height):
            for x in range(width):
                img[y, x, 0] = int(255 * x / width)      # R: 左到右渐变
                img[y, x, 1] = int(255 * y / height)     # G: 上到下渐变
                img[y, x, 2] = int(255 * (1 - x/width))  # B: 右到左渐变

        print(f"  图像大小: {img.nbytes} 字节")

        # 转换为字节
        image_data = img.tobytes()

        # 如果启用帧同步，添加帧头和帧尾
        if use_frame_sync:
            data = FRAME_HEADER + image_data + FRAME_FOOTER
            print(f"✓ 添加帧同步标识:")
            print(f"  帧头: {FRAME_HEADER.hex().upper()} (4字节)")
            print(f"  图像: {len(image_data)} 字节")
            print(f"  帧尾: {FRAME_FOOTER.hex().upper()} (4字节)")
            print(f"  总计: {len(data)} 字节")
        else:
            data = image_data
            print(f"  直接发送模式，无帧同步")

        # 分包发送
        chunk_size = 1400  # 每包1400字节
        total_chunks = (len(data) + chunk_size - 1) // chunk_size

        print(f"✓ 开始发送图片数据...")
        print(f"  总包数: {total_chunks}")
        print(f"  每包大小: {chunk_size} 字节")
        print()

        start_time = time.time()

        for i in range(0, len(data), chunk_size):
            chunk = data[i:i+chunk_size]
            sock.sendto(chunk, (target_ip, target_port))

            # 显示进度
            current_chunk = i // chunk_size + 1
            progress = (i + len(chunk)) / len(data) * 100

            if current_chunk % 50 == 0 or i + chunk_size >= len(data):
                print(f"  进度: {progress:.1f}% ({current_chunk}/{total_chunks} 包)")

            # 添加小延迟避免网络拥塞
            time.sleep(0.0001)

        elapsed = time.time() - start_time

        sock.close()

        print()
        print("="*60)
        print("✓ 图片发送完成")
        print(f"  总字节数: {len(data)} 字节")
        print(f"  总包数: {total_chunks} 包")
        print(f"  用时: {elapsed:.2f} 秒")
        print(f"  速率: {len(data)/elapsed/1024:.1f} KB/s ({len(data)*8/elapsed/1000:.1f} Kbps)")
        print("="*60)

        return True

    except Exception as e:
        print()
        print("="*60)
        print(f"❌ 发送失败: {e}")
        print("="*60)
        return False


def send_solid_color_image(r, g, b, use_frame_sync=True):
    """发送纯色测试图片"""
    print("="*60)
    print(f"发送纯色图片 - RGB({r}, {g}, {b}) ({'帧同步' if use_frame_sync else '直接'})")
    print("="*60)
    print()

    target_ip = "192.168.240.2"
    target_port = 3
    width = 640
    height = 480
    channels = 3

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        # 生成纯色图像
        img = np.zeros((height, width, channels), dtype=np.uint8)
        img[:, :, 0] = r
        img[:, :, 1] = g
        img[:, :, 2] = b

        image_data = img.tobytes()

        # 添加帧同步
        if use_frame_sync:
            data = FRAME_HEADER + image_data + FRAME_FOOTER
            print(f"开始发送 {width}×{height} 纯色图片（帧同步）...")
            print(f"  总大小: {len(data)} 字节 (含帧头/帧尾)")
        else:
            data = image_data
            print(f"开始发送 {width}×{height} 纯色图片（直接模式）...")

        chunk_size = 1400

        for i in range(0, len(data), chunk_size):
            chunk = data[i:i+chunk_size]
            sock.sendto(chunk, (target_ip, target_port))
            time.sleep(0.0001)

        sock.close()
        print("✓ 发送完成")
        return True

    except Exception as e:
        print(f"❌ 发送失败: {e}")
        return False


def send_test_pattern(use_frame_sync=True):
    """发送测试图案（棋盘格）"""
    print("="*60)
    print(f"发送测试图案 - 彩色棋盘格 ({'帧同步' if use_frame_sync else '直接'})")
    print("="*60)
    print()

    target_ip = "192.168.240.2"
    target_port = 3
    width = 640
    height = 480
    channels = 3

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        # 生成彩色棋盘格图像
        img = np.zeros((height, width, channels), dtype=np.uint8)
        block_size = 40

        for y in range(height):
            for x in range(width):
                block_x = (x // block_size) % 3
                block_y = (y // block_size) % 3

                if (block_x + block_y) % 2 == 0:
                    # 白色
                    img[y, x] = [255, 255, 255]
                else:
                    # 彩色
                    if block_x == 0:
                        img[y, x] = [255, 0, 0]  # 红
                    elif block_x == 1:
                        img[y, x] = [0, 255, 0]  # 绿
                    else:
                        img[y, x] = [0, 0, 255]  # 蓝

        image_data = img.tobytes()

        # 添加帧同步
        if use_frame_sync:
            data = FRAME_HEADER + image_data + FRAME_FOOTER
            print(f"开始发送 {width}×{height} 棋盘格图案（帧同步）...")
            print(f"  总大小: {len(data)} 字节 (含帧头/帧尾)")
        else:
            data = image_data
            print(f"开始发送 {width}×{height} 棋盘格图案（直接模式）...")

        chunk_size = 1400

        for i in range(0, len(data), chunk_size):
            chunk = data[i:i+chunk_size]
            sock.sendto(chunk, (target_ip, target_port))
            time.sleep(0.0001)

        sock.close()
        print("✓ 发送完成")
        return True

    except Exception as e:
        print(f"❌ 发送失败: {e}")
        return False


def main():
    """主菜单"""
    # 询问是否使用帧同步模式
    print()
    print("="*60)
    print("SD卡图片接收测试工具（增强版）")
    print("="*60)
    print()
    print("请选择发送模式:")
    print("  1. 帧同步模式（推荐，与GUI帧同步接收匹配）")
    print("  2. 直接模式（无帧同步标识）")
    print()

    mode_choice = input("请输入模式 (1-2，默认1): ").strip()
    use_frame_sync = True if mode_choice != '2' else False

    mode_name = "帧同步模式" if use_frame_sync else "直接模式"
    print(f"\n✓ 已选择: {mode_name}")
    print()
    input("按Enter键继续...")

    while True:
        print()
        print("="*60)
        print(f"SD卡图片接收测试工具 - {mode_name}")
        print("="*60)
        print()
        print("请选择测试图片:")
        print("  1. 发送彩色渐变图片（推荐）")
        print("  2. 发送纯红色图片")
        print("  3. 发送纯绿色图片")
        print("  4. 发送纯蓝色图片")
        print("  5. 发送彩色棋盘格图案")
        print("  0. 退出")
        print()

        try:
            choice = input("请输入选项 (0-5): ").strip()

            if choice == '0':
                print("退出程序")
                break
            elif choice == '1':
                send_test_image(use_frame_sync)
            elif choice == '2':
                send_solid_color_image(255, 0, 0, use_frame_sync)
            elif choice == '3':
                send_solid_color_image(0, 255, 0, use_frame_sync)
            elif choice == '4':
                send_solid_color_image(0, 0, 255, use_frame_sync)
            elif choice == '5':
                send_test_pattern(use_frame_sync)
            else:
                print("无效选项，请重新输入")

            # 询问是否继续
            print()
            cont = input("继续测试? (y/n): ").strip().lower()
            if cont != 'y':
                break

        except KeyboardInterrupt:
            print("\n\n中断退出")
            break
        except Exception as e:
            print(f"\n错误: {e}")


if __name__ == "__main__":
    print()
    print("="*60)
    print("SD卡图片接收测试工具（增强版）")
    print("="*60)
    print()
    print("功能特性:")
    print("  ✓ 支持帧同步发送（帧头/帧尾标识）")
    print("  ✓ 支持直接模式发送（无帧同步）")
    print("  ✓ 5种测试图案可选")
    print("  ✓ 实时速率显示")
    print()
    print("使用步骤:")
    print("  1. 启动 ethernet_host_gui.py")
    print("  2. 切换到 'SD卡接收' 标签页")
    print("  3. 点击 '开始接收' 按钮")
    print("  4. 运行本测试脚本发送图片")
    print()
    print("注意:")
    print("  • GUI默认使用帧同步模式")
    print("  • 建议测试脚本也选择帧同步模式")
    print("  • 帧头: AA55AA55, 帧尾: 55AA55AA")
    print()
    input("按Enter键继续...")

    main()
