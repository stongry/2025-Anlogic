#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP SDRAM Debug Data Receiver (Enhanced Version)
用于接收FPGA通过UDP发送的SDRAM调试信息 - 增强版，包含Frame模块内部状态

数据包格式（64字节）：
  [0-3]   : 帧头 0xA5A5DEAD (4字节)
  [4-7]   : 帧计数器 (4字节)
  [8-11]  : SDRAM写地址 (4字节)
  [12-15] : SDRAM读地址 (4字节)
  [16-19] : SDRAM写数据 (4字节)
  [20-23] : SDRAM读数据 (4字节)
  [24-27] : SDRAM状态标志 (4字节)
  [28-31] : 时间戳 (4字节)

  ===== 新增：Frame模块内部调试信息 =====
  [32-35] : 写FIFO状态 (4字节)
  [36-39] : 写控制状态 (4字节)
  [40-43] : 写突发控制 (4字节)
  [44-47] : 读FIFO状态 (4字节)
  [48-51] : 读控制状态 (4字节)
  [52-55] : 读突发控制 (4字节)
  [56-59] : 扩展状态标志 (4字节)
  [60-63] : 包尾标识 0xDEADBEEF (4字节)

SDRAM状态标志位定义（字节24-27）：
  [0]    : Sdr_init_done
  [1]    : Sdr_busy
  [2]    : App_wr_en
  [3]    : App_rd_en
  [4]    : video_read_req
  [5]    : video_read_req_ack
  [6]    : udp_write_req
  [7]    : udp_write_req_ack
  [11:8] : 写字节掩码 App_wr_dm
  [12]   : Sdr_rd_en
  [13]   : write_finish
  [14]   : read_finish
  [15]   : Sdr_init_ref_vld
"""

import socket
import struct
import sys
import os
from datetime import datetime
from typing import Tuple

# Windows控制台UTF-8支持
if sys.platform == 'win32':
    # 尝试设置控制台为UTF-8
    try:
        os.system('chcp 65001 > nul 2>&1')
    except:
        pass

# 配置参数
UDP_IP = "192.168.240.2"      # PC的IP地址（与DST_IP_ADDRESS匹配）
UDP_PORT = 2                   # UDP端口号（与DST_UDP_PORT_NUM匹配）
PACKET_SIZE = 64               # 数据包大小（字节）- 扩展版
HEADER_MAGIC = 0xA5A5DEAD      # 帧头魔数
TAIL_MAGIC = 0xDEADBEEF        # 包尾魔数

# 状态机状态定义
STATE_NAMES = {
    0: "IDLE",
    1: "ACK",
    2: "CHECK_FIFO",
    3: "BURST",
    4: "BURST_END",
    5: "END"
}

class SDRAMDebugReceiver:
    def __init__(self, ip=UDP_IP, port=UDP_PORT):
        self.ip = ip
        self.port = port
        self.sock = None
        self.packet_count = 0
        self.error_count = 0
        self.last_frame_id = None
        self.detailed_mode = True  # 详细模式开关

    def start(self, detailed=False):
        """启动UDP接收"""
        self.detailed_mode = detailed

        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.ip, self.port))
            print("="*80)
            print(" UDP SDRAM Debug Receiver (Enhanced - 64 bytes)")
            print(" Mode: " + ("Detailed (Frame internals)" if detailed else "Compact"))
            print("="*80)
            print(f"[Start] Listening on: {self.ip}:{self.port}")
            print(f"[Config] Packet size: {PACKET_SIZE} bytes")
            print("="*80)
            print("Waiting for FPGA data...\n")

            while True:
                self.receive_packet()

        except KeyboardInterrupt:
            print("\n\n[Stop] User interrupted")
            self.print_statistics()
        except Exception as e:
            print(f"\n[Error] {e}")
        finally:
            if self.sock:
                self.sock.close()
                print("[Close] Socket closed")

    def receive_packet(self):
        """接收并解析一个数据包"""
        try:
            data, addr = self.sock.recvfrom(1024)

            if len(data) != PACKET_SIZE:
                self.error_count += 1
                print(f"[警告] 数据包大小错误: 期望{PACKET_SIZE}字节, 收到{len(data)}字节")
                return

            # 解析基本字段（大端序）
            header = struct.unpack('>I', data[0:4])[0]

            if header != HEADER_MAGIC:
                self.error_count += 1
                print(f"[警告] 帧头错误: 期望0x{HEADER_MAGIC:08X}, 收到0x{header:08X}")
                return

            frame_id = struct.unpack('>I', data[4:8])[0]
            wr_addr = struct.unpack('>I', data[8:12])[0]
            rd_addr = struct.unpack('>I', data[12:16])[0]
            wr_data = struct.unpack('>I', data[16:20])[0]
            rd_data = struct.unpack('>I', data[20:24])[0]
            status = struct.unpack('>I', data[24:28])[0]
            timestamp = struct.unpack('>I', data[28:32])[0]

            # ===== 解析扩展字段（Frame模块） =====
            write_fifo_status = struct.unpack('>I', data[32:36])[0]
            write_ctrl_status = struct.unpack('>I', data[36:40])[0]
            write_burst_status = struct.unpack('>I', data[40:44])[0]
            read_fifo_status = struct.unpack('>I', data[44:48])[0]
            read_ctrl_status = struct.unpack('>I', data[48:52])[0]
            read_burst_status = struct.unpack('>I', data[52:56])[0]
            extended_status = struct.unpack('>I', data[56:60])[0]
            tail_magic = struct.unpack('>I', data[60:64])[0]

            # 检查包尾
            if tail_magic != TAIL_MAGIC:
                self.error_count += 1
                print(f"[警告] 包尾错误: 期望0x{TAIL_MAGIC:08X}, 收到0x{tail_magic:08X}")
                return

            # 检查丢包
            if self.last_frame_id is not None:
                expected = (self.last_frame_id + 1) & 0xFFFFFFFF
                if frame_id != expected:
                    lost = (frame_id - expected) & 0xFFFFFFFF
                    print(f"[警告] 检测到丢包! 丢失 {lost} 个数据包 (期望:{expected}, 收到:{frame_id})")
                    self.error_count += lost

            self.last_frame_id = frame_id
            self.packet_count += 1

            # 解析所有字段
            parsed_data = self.parse_all_fields(
                status, write_fifo_status, write_ctrl_status, write_burst_status,
                read_fifo_status, read_ctrl_status, read_burst_status, extended_status
            )

            # 显示数据
            self.print_packet_info(
                frame_id, wr_addr, rd_addr, wr_data, rd_data, timestamp,
                parsed_data, addr
            )

        except Exception as e:
            print(f"[错误] 解析数据包失败: {e}")
            import traceback
            traceback.print_exc()
            self.error_count += 1

    def parse_all_fields(self, status, write_fifo_status, write_ctrl_status,
                        write_burst_status, read_fifo_status, read_ctrl_status,
                        read_burst_status, extended_status) -> dict:
        """解析所有状态字段"""
        parsed = {}

        # 基本SDRAM状态
        parsed['sdr_init_done'] = bool(status & 0x01)
        parsed['sdr_busy'] = bool(status & 0x02)
        parsed['app_wr_en'] = bool(status & 0x04)
        parsed['app_rd_en'] = bool(status & 0x08)
        parsed['video_read_req'] = bool(status & 0x10)
        parsed['video_read_req_ack'] = bool(status & 0x20)
        parsed['udp_write_req'] = bool(status & 0x40)
        parsed['udp_write_req_ack'] = bool(status & 0x80)
        parsed['wr_dm'] = (status >> 8) & 0x0F
        parsed['sdr_rd_en'] = bool(status & 0x1000)
        parsed['write_finish'] = bool(status & 0x2000)
        parsed['read_finish'] = bool(status & 0x4000)
        parsed['sdr_init_ref_vld'] = bool(status & 0x8000)

        # 写FIFO状态
        parsed['write_fifo_wrusedw'] = (write_fifo_status >> 16) & 0x3FF
        parsed['write_fifo_rdusedw'] = write_fifo_status & 0x3FF

        # 写控制状态
        parsed['write_state'] = (write_ctrl_status >> 24) & 0xF
        parsed['write_cnt'] = write_ctrl_status & 0x1FFFFF

        # 写突发控制
        parsed['write_burst_cnt'] = (write_burst_status >> 18) & 0x1FF
        parsed['write_len_latch'] = write_burst_status & 0x3FFFF

        # 读FIFO状态
        parsed['read_fifo_wrusedw'] = (read_fifo_status >> 16) & 0x3FF
        parsed['read_fifo_rdusedw'] = read_fifo_status & 0x3FF

        # 读控制状态
        parsed['read_state'] = (read_ctrl_status >> 24) & 0xF
        parsed['read_cnt'] = read_ctrl_status & 0x1FFFFF

        # 读突发控制
        parsed['read_burst_cnt'] = (read_burst_status >> 18) & 0x1FF
        parsed['read_len_latch'] = read_burst_status & 0x3FFFF

        # 扩展状态标志
        parsed['colorbar_data_valid'] = bool(extended_status & 0x20000)  # bit 17
        parsed['colorbar_enable'] = bool(extended_status & 0x10000)      # bit 16
        parsed['o_rd_busy'] = bool(extended_status & 0x800)
        parsed['o_wr_busy'] = bool(extended_status & 0x400)
        parsed['video_read_en'] = bool(extended_status & 0x200)
        parsed['write_data_valid'] = bool(extended_status & 0x100)
        parsed['read_req_ack_sync2'] = bool(extended_status & 0x80)
        parsed['read_req_ack_sync1'] = bool(extended_status & 0x40)
        parsed['write_req_ack_sync2'] = bool(extended_status & 0x08)
        parsed['write_req_ack_sync1'] = bool(extended_status & 0x04)

        return parsed

    def print_packet_info(self, frame_id, wr_addr, rd_addr, wr_data, rd_data,
                         timestamp, parsed, addr):
        """打印数据包信息"""
        now = datetime.now().strftime("%H:%M:%S.%f")[:-3]

        # 简洁模式 - 显示更多关键信息
        if not self.detailed_mode:
            # 彩条颜色识别
            colorbar_colors = {
                0xFFFF: "White", 0xFFE0: "Yellow", 0x07FF: "Cyan", 0x07E0: "Green",
                0xF81F: "Magenta", 0xF800: "Red", 0x001F: "Blue", 0x0000: "Black"
            }
            rd_data_low16 = rd_data & 0xFFFF
            color_name = colorbar_colors.get(rd_data_low16, "")
            color_str = f" [{color_name}]" if color_name else ""

            wr_state = STATE_NAMES.get(parsed['write_state'], '?')
            rd_state = STATE_NAMES.get(parsed['read_state'], '?')

            # 单行显示但包含更多信息
            print(f"[{now}] #{frame_id:06d} | " +
                  f"W:{('Y' if parsed['app_wr_en'] else 'N'):1s} {wr_addr:06X} ({parsed['write_cnt']:6d}/{parsed['write_len_latch']:6d}) {wr_state:12s} FIFO:{parsed['write_fifo_rdusedw']:4d} | " +
                  f"R:{('Y' if parsed['app_rd_en'] else 'N'):1s} {rd_addr:06X} ({parsed['read_cnt']:6d}/{parsed['read_len_latch']:6d}) {rd_state:12s} FIFO:{parsed['read_fifo_wrusedw']:4d} | " +
                  f"RD:0x{rd_data:08X}{color_str}")
            return

        # 详细模式 - 显示完整信息
        print(f"\n{'='*80}")
        print(f"Frame #{frame_id:06d} @ {now}  (from {addr[0]}:{addr[1]})")
        print(f"{'='*80}")

        # SDRAM基本信息
        print(f"\n--- SDRAM Basic Info ---")
        print(f"  Address:  Write=0x{wr_addr:06X} ({wr_addr:7d})    Read=0x{rd_addr:06X} ({rd_addr:7d})")
        print(f"  Data:     Write=0x{wr_data:08X}            Read=0x{rd_data:08X}")

        # 检查是否是彩条颜色
        colorbar_colors = {
            0xFFFF: "White", 0xFFE0: "Yellow", 0x07FF: "Cyan", 0x07E0: "Green",
            0xF81F: "Magenta", 0xF800: "Red", 0x001F: "Blue", 0x0000: "Black"
        }
        rd_data_low16 = rd_data & 0xFFFF
        color_name = colorbar_colors.get(rd_data_low16, "")
        if color_name:
            print(f"            Read data[15:0]: 0x{rd_data_low16:04X} -> {color_name} ***")

        init_status = "OK" if parsed['sdr_init_done'] else "NO"
        busy_status = "YES" if parsed['sdr_busy'] else "NO"
        wr_en_status = "YES" if parsed['app_wr_en'] else "NO"
        rd_en_status = "YES" if parsed['app_rd_en'] else "NO"

        print(f"  Status:   Init={init_status}  Busy={busy_status}  WrEn={wr_en_status}  RdEn={rd_en_status}  Mask=0x{parsed['wr_dm']:X}")

        # Frame写模块状态
        print(f"\n--- Frame Write Module ---")
        write_state_name = STATE_NAMES.get(parsed['write_state'], f"UNKNOWN({parsed['write_state']})")
        write_state_mark = " <<<" if parsed['write_state'] == 3 else ""

        print(f"  State:    {write_state_name:12s}{write_state_mark}")
        print(f"  FIFO:     rdusedw={parsed['write_fifo_rdusedw']:4d} (data ready for SDRAM write)")
        print(f"  Count:    write_cnt={parsed['write_cnt']:6d} / {parsed['write_len_latch']:6d}  " +
              f"burst={parsed['write_burst_cnt']:3d}/256")

        busy_status = "BUSY" if parsed['o_wr_busy'] else "IDLE"
        valid_status = "YES" if parsed['write_data_valid'] else "NO"
        print(f"  Control:  o_wr_busy={busy_status:4s}  write_data_valid={valid_status}")

        # Frame读模块状态
        print(f"\n--- Frame Read Module ---")
        read_state_name = STATE_NAMES.get(parsed['read_state'], f"UNKNOWN({parsed['read_state']})")
        read_state_mark = " <<<" if parsed['read_state'] == 3 else ""

        print(f"  State:    {read_state_name:12s}{read_state_mark}")
        print(f"  FIFO:     wrusedw={parsed['read_fifo_wrusedw']:4d} (data from SDRAM for VGA)")
        print(f"  Count:    read_cnt={parsed['read_cnt']:6d} / {parsed['read_len_latch']:6d}  " +
              f"burst={parsed['read_burst_cnt']:3d}/128")

        busy_status = "BUSY" if parsed['o_rd_busy'] else "IDLE"
        en_status = "YES" if parsed['video_read_en'] else "NO"
        print(f"  Control:  o_rd_busy={busy_status:4s}  video_read_en={en_status}")

        # 握手信号
        print(f"\n--- Control Signals & Synchronizers ---")

        vga_req = "YES" if parsed['video_read_req'] else "NO"
        vga_ack = "YES" if parsed['video_read_req_ack'] else "NO"
        udp_req = "YES" if parsed['udp_write_req'] else "NO"
        udp_ack = "YES" if parsed['udp_write_req_ack'] else "NO"

        print(f"  VGA:      read_req={vga_req:3s}  req_ack={vga_ack:3s}")
        print(f"  UDP:      write_req={udp_req:3s}  req_ack={udp_ack:3s}")

        # CDC同步器状态
        w_sync1 = "1" if parsed['write_req_ack_sync1'] else "0"
        w_sync2 = "1" if parsed['write_req_ack_sync2'] else "0"
        r_sync1 = "1" if parsed['read_req_ack_sync1'] else "0"
        r_sync2 = "1" if parsed['read_req_ack_sync2'] else "0"

        print(f"  CDC:      write_ack_sync=[{w_sync1},{w_sync2}]  read_ack_sync=[{r_sync1},{r_sync2}]")

        # 其他状态
        finish_w = "YES" if parsed['write_finish'] else "NO"
        finish_r = "YES" if parsed['read_finish'] else "NO"
        ref_vld = "YES" if parsed['sdr_init_ref_vld'] else "NO"
        sdr_rd_en = "YES" if parsed['sdr_rd_en'] else "NO"

        print(f"\n--- Other Flags ---")
        print(f"  Finish:   write={finish_w:3s}  read={finish_r:3s}")
        print(f"  SDRAM:    rd_en={sdr_rd_en:3s}  init_ref_vld={ref_vld:3s}")
        print(f"  Timestamp: {timestamp:10d} FPGA clock cycles")

        # Colorbar状态（新增）
        print(f"\n--- Colorbar Status (NEW!) ---")
        colorbar_en = "YES" if parsed['colorbar_enable'] else "NO"
        colorbar_dv = "YES" if parsed['colorbar_data_valid'] else "NO"
        print(f"  Enable:     {colorbar_en:3s}  (should be YES if SDRAM init OK)")
        print(f"  DataValid:  {colorbar_dv:3s}  (should toggle if colorbar working)")

        if not parsed['colorbar_enable']:
            print(f"  ** WARNING: Colorbar NOT enabled! Check Sdr_init_done signal")
        elif not parsed['colorbar_data_valid']:
            print(f"  ** WARNING: Colorbar enabled but NO data! Check colorbar_simple module")

        print(f"{'='*80}\n")

    def print_statistics(self):
        """打印统计信息"""
        print("\n" + "=" * 80)
        print("接收统计:")
        print(f"  成功接收: {self.packet_count} 个数据包")
        print(f"  错误/丢包: {self.error_count} 个")
        if self.packet_count > 0:
            success_rate = (self.packet_count / (self.packet_count + self.error_count)) * 100
            print(f"  成功率: {success_rate:.2f}%")
        print("=" * 80)

def main():
    """主函数"""
    print("=" * 80)
    print(" UDP SDRAM调试数据接收器 (Enhanced - 64字节)")
    print(" FPGA -> PC UDP调试工具 - 包含Frame模块内部状态")
    print("=" * 80)
    print()

    # 检查命令行参数
    ip = UDP_IP
    port = UDP_PORT
    detailed = False

    if "--help" in sys.argv or "-h" in sys.argv:
        print("用法:")
        print(f"  python {sys.argv[0]} [IP地址] [端口] [--detailed]")
        print()
        print("参数:")
        print(f"  IP地址    默认: {UDP_IP}")
        print(f"  端口      默认: {UDP_PORT}")
        print(f"  --detailed 或 -d  显示详细信息（Frame模块内部状态）")
        print()
        print("示例:")
        print(f"  python {sys.argv[0]}                      # 使用默认配置，简洁模式")
        print(f"  python {sys.argv[0]} --detailed           # 详细模式")
        print(f"  python {sys.argv[0]} 192.168.1.100 2 -d  # 自定义IP和端口，详细模式")
        return

    # 解析参数
    for arg in sys.argv[1:]:
        if arg in ["--detailed", "-d"]:
            detailed = True
        elif "." in arg:  # IP地址
            ip = arg
        elif arg.isdigit():  # 端口号
            port = int(arg)

    # 启动接收器
    receiver = SDRAMDebugReceiver(ip, port)
    receiver.start(detailed=detailed)

if __name__ == "__main__":
    main()
