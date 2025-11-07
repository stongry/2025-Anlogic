#!/usr/bin/env python3
"""
测试UDP数据包格式
基于 lab_ex_1_receive 和 lab_ex_1_ethernet_led 工程
参考: /home/ysara/Desktop/backupprj/lab_ex_1_receive/UDP_EG4_6.2/source_code/rtl/udp_display_parser.v
"""

def test_digit_packet(value):
    """测试数码管数据包格式"""
    # 限制范围
    value = max(-100, min(100, value))

    # 转换为8位补码
    if value < 0:
        low_byte = (256 + value) & 0xFF
        high_byte = 0xFF
    else:
        low_byte = value & 0xFF
        high_byte = 0x00

    packet = bytearray([
        0xF0, 0xAA, 0x55, 0x55, 0x12, 0x34, 0x00, 0x08,
        high_byte, low_byte, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ])

    print(f"数码管值: {value:+4d} => 数据包: {' '.join(f'{b:02X}' for b in packet)}")
    print(f"  高字节: 0x{high_byte:02X}, 低字节: 0x{low_byte:02X}")

    # 验证：将补码转回原值
    if low_byte >= 128:  # 负数
        recovered = low_byte - 256
    else:
        recovered = low_byte
    print(f"  验证恢复值: {recovered}")
    assert recovered == value, f"恢复值 {recovered} 不等于原值 {value}"
    print()

def test_led_packet(led_value):
    """测试LED数据包格式"""
    led_byte = led_value & 0x0F

    packet = bytearray([
        0xF0, 0xAA, 0x55, 0x55, 0x56, 0x78, 0x00, 0x08,
        led_byte, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ])

    print(f"LED值: 0x{led_value:X} => 数据包: {' '.join(f'{b:02X}' for b in packet)}")
    print(f"  LED3={bool(led_byte&8)} LED2={bool(led_byte&4)} LED1={bool(led_byte&2)} LED0={bool(led_byte&1)}")
    print()

if __name__ == "__main__":
    print("=" * 70)
    print("测试UDP数据包格式 - lab_ex_1 工程")
    print("=" * 70)
    print()

    print("-" * 70)
    print("测试数码管数据包格式")
    print("-" * 70)

    # 测试各种数值
    test_values = [0, 1, 50, 100, -1, -50, -100]
    for val in test_values:
        test_digit_packet(val)

    print("-" * 70)
    print("测试LED数据包格式")
    print("-" * 70)

    # 测试LED值
    test_led_values = [0x0, 0x1, 0xF, 0x5, 0xA]
    for val in test_led_values:
        test_led_packet(val)

    print("=" * 70)
    print("✓ 所有测试通过！")
    print("=" * 70)
    print()
    print("数据包格式说明：")
    print("  数码管包: [0xF0][0xAA][0x55][0x55][0x12][0x34][0x00][0x08][high][low][...]")
    print("  LED包:    [0xF0][0xAA][0x55][0x55][0x56][0x78][0x00][0x08][led_byte][...]")
    print()

