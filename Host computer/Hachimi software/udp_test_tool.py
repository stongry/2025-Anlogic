#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP测试工具 - 模拟FPGA发送数据
用于测试以太网上位机的接收功能
"""

import socket
import time
import struct


def send_test_data():
    """发送测试数据到上位机"""

    # 配置
    target_ip = "192.168.240.1"  # 上位机IP
    target_port = 1              # 上位机端口
    source_port = 2              # 模拟FPGA端口

    print("UDP测试工具 - 模拟FPGA发送数据")
    print(f"目标: {target_ip}:{target_port}")
    print("-" * 50)

    try:
        # 创建UDP Socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("0.0.0.0", source_port))

        print("开始发送测试数据...\n")

        # 测试数据集
        test_cases = [
            {
                "name": "LED全灭，数码管=0",
                "led": 0x0,
                "digit": 0x0000
            },
            {
                "name": "LED全亮，数码管=100",
                "led": 0xF,
                "digit": 0x0064
            },
            {
                "name": "LED0和LED2亮，数码管=50",
                "led": 0x5,
                "digit": 0x0032
            },
            {
                "name": "LED1和LED3亮，数码管=-50",
                "led": 0xA,
                "digit": 0xFFCE  # 补码表示-50
            }
        ]

        for i, test in enumerate(test_cases, 1):
            # 构建8字节数据包（按照led.v的接收格式）
            # 字节0: led_data[63:56] - LED状态在高4位
            # 字节1-2: led_data[55:40] - 数码管数据
            # 字节3-7: 其他数据

            led_byte = (test["led"] << 4) & 0xF0  # LED状态放在高4位
            digit_high = (test["digit"] >> 8) & 0xFF
            digit_low = test["digit"] & 0xFF

            data = bytearray([
                led_byte,      # 字节0: LED状态（高4位）
                digit_high,    # 字节1: 数码管高字节
                digit_low,     # 字节2: 数码管低字节
                0x00, 0x00, 0x00, 0x00, 0x00  # 字节3-7: 保留
            ])

            # 发送数据
            sock.sendto(data, (target_ip, target_port))

            print(f"[{i}] {test['name']}")
            print(f"    LED值: 0x{test['led']:X}")
            print(f"    数码管值: 0x{test['digit']:04X}")
            print(f"    发送数据: {data.hex()}")
            print()

            # 等待2秒
            time.sleep(2)

        print("测试完成！")
        sock.close()

    except Exception as e:
        print(f"错误: {e}")


def interactive_mode():
    """交互模式 - 手动输入数据发送"""

    target_ip = "192.168.240.1"
    target_port = 1
    source_port = 2

    print("UDP测试工具 - 交互模式")
    print(f"目标: {target_ip}:{target_port}")
    print("-" * 50)

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("0.0.0.0", source_port))

        print("输入格式: LED值(0-15) 数码管值(-32768到32767)")
        print("输入 'q' 退出\n")

        while True:
            try:
                user_input = input("请输入 (LED 数码管): ").strip()

                if user_input.lower() == 'q':
                    break

                parts = user_input.split()
                if len(parts) != 2:
                    print("错误: 请输入两个数值")
                    continue

                led = int(parts[0]) & 0xF  # 限制在0-15
                digit = int(parts[1]) & 0xFFFF  # 限制在16位范围

                # 构建数据包
                led_byte = (led << 4) & 0xF0
                digit_high = (digit >> 8) & 0xFF
                digit_low = digit & 0xFF

                data = bytearray([
                    led_byte, digit_high, digit_low,
                    0x00, 0x00, 0x00, 0x00, 0x00
                ])

                # 发送
                sock.sendto(data, (target_ip, target_port))
                print(f"已发送: LED=0x{led:X}, 数码管=0x{digit:04X}, 数据={data.hex()}\n")

            except ValueError:
                print("错误: 请输入有效的数字\n")
            except KeyboardInterrupt:
                print("\n退出...")
                break

        sock.close()

    except Exception as e:
        print(f"错误: {e}")


def main():
    """主函数"""
    print("=" * 50)
    print("  UDP测试工具 - 模拟FPGA发送数据")
    print("=" * 50)
    print()
    print("请选择模式:")
    print("  1. 自动测试模式（发送预设测试数据）")
    print("  2. 交互模式（手动输入数据）")
    print()

    choice = input("请选择 (1/2): ").strip()

    if choice == "1":
        print()
        send_test_data()
    elif choice == "2":
        print()
        interactive_mode()
    else:
        print("无效选择")


if __name__ == "__main__":
    main()
