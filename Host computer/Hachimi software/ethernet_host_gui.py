#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
以太网上位机 - UDP通信GUI (Apple风格)
基于lab_ex_1_ethernet_led工程配置
作者：生成于Claude Code
日期：2025-11-03
"""

import tkinter as tk
from tkinter import ttk, scrolledtext, filedialog
import socket
import threading
import time
import os
from datetime import datetime
from collections import deque
import numpy as np
from PIL import Image, ImageTk
import serial
import serial.tools.list_ports
import cv2  # 用于视频处理


class AppleColors:
    """Apple设计系统配色方案 - iOS 16液体玻璃风格"""
    # 主色调 - 系统蓝（更柔和）
    PRIMARY = "#007AFF"       # 标准系统蓝
    PRIMARY_LIGHT = "#5AC8FA" # 浅蓝色
    PRIMARY_DARK = "#0051D5"  # 深蓝色

    # 背景 - 液体玻璃风格
    BG_PRIMARY = "#F2F2F7"    # 主背景（浅灰带紫调）
    BG_SECONDARY = "#FDFDFE"  # 次级背景（毛玻璃白）
    BG_TERTIARY = "#F9F9FB"   # 三级背景（玻璃质感）
    BG_GLASS = "#FAFAFA"      # 毛玻璃效果

    # 功能色 - Apple标准色
    SUCCESS = "#34C759"       # 系统绿
    ERROR = "#FF3B30"         # 系统红
    WARNING = "#FF9500"       # 系统橙
    INFO = "#007AFF"          # 系统蓝

    # 文字 - Apple文字系统
    TEXT_PRIMARY = "#000000"      # 主文字（黑色）
    TEXT_SECONDARY = "#6E6E73"    # 次级文字（灰色）
    TEXT_TERTIARY = "#8E8E93"     # 三级文字（浅灰）
    TEXT_QUATERNARY = "#AEAEB2"   # 占位符文字

    # 分隔线和边框 - 液体玻璃效果
    SEPARATOR = "#E5E5EA"     # 分隔线（更柔和）
    BORDER = "#E8E8ED"        # 边框（柔和边框）
    GLASS_BORDER = "#F5F5F7"  # 玻璃边框（浅灰）
    SHADOW_LIGHT = "#EBEBEF"  # 浅阴影
    SHADOW_MEDIUM = "#E0E0E5" # 中阴影


class VideoReceiverThread(threading.Thread):
    """视频UDP接收线程（优化版 - 参考udp_receiver_gui.py）"""
    def __init__(self, callback):
        super().__init__()
        self.running = False
        self.callback = callback
        self.sock = None
        self.udp_ip = "192.168.240.2"
        self.udp_port = 2
        self.width = 640
        self.height = 480
        self.channels = 3
        self.frame_size = self.width * self.height * self.channels
        self.frame_buffer = bytearray()
        self.timeout = 2.0

        # 统计信息
        self.packet_count = 0
        self.frame_count = 0
        self.total_bytes = 0
        self.last_frame_time = time.time()
        self.fps_queue = deque(maxlen=30)

        # 日志优化：超时计数器（参考udp_receiver_gui.py）
        self.timeout_count = 0

    def set_config(self, ip, port, width, height, timeout):
        """设置配置参数"""
        self.udp_ip = ip
        self.udp_port = port
        self.width = width
        self.height = height
        self.frame_size = width * height * self.channels
        self.timeout = timeout

    def run(self):
        """线程主循环"""
        self.running = True
        self.frame_buffer.clear()
        self.packet_count = 0
        self.frame_count = 0
        self.total_bytes = 0
        self.timeout_count = 0

        try:
            # 创建UDP socket
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.udp_ip, self.udp_port))
            self.sock.settimeout(self.timeout)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8*1024*1024)

            self.callback('log', f"开始接收视频流: {self.udp_ip}:{self.udp_port}")
            self.callback('log', f"图像分辨率: {self.width}x{self.height}")

            while self.running:
                try:
                    # 接收数据（不阻塞太久）
                    data, addr = self.sock.recvfrom(65535)

                    self.packet_count += 1
                    self.total_bytes += len(data)

                    # 日志优化：只打印前3个包（参考udp_receiver_gui.py）
                    if self.packet_count <= 3:
                        self.callback('log', f"收到数据包 #{self.packet_count} 来自 {addr[0]}:{addr[1]}, 大小: {len(data)} 字节")
                    elif self.packet_count == 4:
                        self.callback('log', "继续接收中... (不再打印每个包)")

                    # 添加到缓冲区
                    self.frame_buffer.extend(data)

                    # 尝试提取完整帧
                    while len(self.frame_buffer) >= self.frame_size:
                        frame_data = bytes(self.frame_buffer[:self.frame_size])
                        self.frame_buffer = self.frame_buffer[self.frame_size:]

                        try:
                            # 转换为numpy数组
                            img_array = np.frombuffer(frame_data, dtype=np.uint8)
                            img = img_array.reshape((self.height, self.width, self.channels))

                            # 计算FPS
                            current_time = time.time()
                            fps = 1.0 / (current_time - self.last_frame_time) if (current_time - self.last_frame_time) > 0 else 0
                            self.fps_queue.append(fps)
                            self.last_frame_time = current_time

                            self.frame_count += 1

                            # 回调显示帧
                            self.callback('frame', img)

                            # 日志优化：每10帧打印一次
                            if self.frame_count % 10 == 0:
                                avg_fps = np.mean(self.fps_queue) if len(self.fps_queue) > 0 else 0.0
                                self.callback('log', f"帧 #{self.frame_count}, FPS: {avg_fps:.1f}")

                            # 重置超时计数（收到帧说明正常）
                            self.timeout_count = 0

                        except Exception as e:
                            self.callback('error', f"图像转换错误: {e}")
                            self.frame_buffer.clear()
                            break

                except socket.timeout:
                    # 日志优化：只在第一次超时时打印警告（参考udp_receiver_gui.py）
                    self.timeout_count += 1
                    if self.timeout_count == 1:
                        self.callback('log', "警告: 超时未收到数据，请检查FPGA是否启动")

                except Exception as e:
                    if self.running:
                        self.callback('error', f"接收错误: {e}")

        except Exception as e:
            self.callback('error', f"Socket创建失败: {e}")

        finally:
            if self.sock:
                self.sock.close()
            self.callback('log', "视频接收已停止")

    def stop(self):
        """停止线程"""
        self.running = False
        # 关闭socket以立即中断recvfrom阻塞
        if self.sock:
            try:
                self.sock.close()
            except:
                pass

    def get_stats(self):
        """获取统计信息"""
        avg_fps = np.mean(self.fps_queue) if len(self.fps_queue) > 0 else 0.0
        return {
            'fps': avg_fps,
            'frames': self.frame_count,
            'packets': self.packet_count,
            'bytes': self.total_bytes,
            'buffer': len(self.frame_buffer)
        }


class ImageSenderThread(threading.Thread):
    """图片UDP发送线程（支持64x64像素地址模式和帧同步模式）"""
    def __init__(self, callback):
        super().__init__()
        self.running = False
        self.callback = callback
        self.sock = None
        self.target_ip = "192.168.240.1"
        self.target_port = 1  # 修改为端口1（参考send_640x480_image.py）

        # 图片数据
        self.image_pixels = None  # 像素列表 [(R,G,B), ...]
        self.image_data = None    # 原始字节数据（兼容旧格式）
        self.use_frame_sync = False  # 默认使用像素地址模式

        # 帧同步标识（3字节格式）
        self.FRAME_HEADER = b'\xAA\x55\xAA'
        self.FRAME_FOOTER = b'\x55\xAA\x55'

        # 发送配置
        self.chunk_size = 1400  # 每个UDP包最大1400字节
        self.delay = 0.001  # 包间延迟（1ms）

        # 统计信息
        self.packet_count = 0
        self.total_bytes = 0
        self.bytes_sent = 0
        self.start_time = None

    def set_config(self, ip, port, use_frame_sync=False):
        """设置配置参数"""
        self.target_ip = ip
        self.target_port = port
        self.use_frame_sync = use_frame_sync

    def set_image_pixels(self, pixels):
        """设置像素数据（新格式）"""
        self.image_pixels = pixels

    def set_image_data(self, image_data):
        """设置原始图片数据（旧格式兼容）"""
        self.image_data = image_data

    def convert_pixels_to_packets(self):
        """
        将像素列表转换为UDP数据包格式
        格式: f1 + 地址(3字节) + RGB(3字节)
        参考: /home/ysara/2025Anlogic/HXEG420_lab_ex/lab_ex_2_ethernet_bmp_hdmi/send_640x480_image.py
        """
        if not self.image_pixels:
            return []

        packets = []
        packet_data = bytearray()

        for idx, (r, g, b) in enumerate(self.image_pixels):
            # 构造单个像素数据包: f1 + 19位地址(3字节) + 24位RGB(3字节)
            pixel_packet = bytearray()
            pixel_packet.append(0xf1)  # 包头

            # 19位地址，分成3个字节 (高字节只用低3位)
            addr_byte2 = (idx >> 16) & 0x07  # 高3位
            addr_byte1 = (idx >> 8) & 0xff   # 中8位
            addr_byte0 = idx & 0xff          # 低8位

            pixel_packet.append(addr_byte2)
            pixel_packet.append(addr_byte1)
            pixel_packet.append(addr_byte0)
            pixel_packet.append(r)
            pixel_packet.append(g)
            pixel_packet.append(b)

            packet_data.extend(pixel_packet)

            # 每1400字节分一个UDP包 (约200个像素)
            if len(packet_data) >= self.chunk_size:
                packets.append(bytes(packet_data))
                packet_data = bytearray()

        # 添加最后一个包
        if len(packet_data) > 0:
            packets.append(bytes(packet_data))

        return packets

    def run(self):
        """线程主循环"""
        # 检查是否有数据可发送
        if self.image_pixels is None and self.image_data is None:
            self.callback('error', "没有图片数据可发送")
            return

        self.running = True
        self.packet_count = 0
        self.bytes_sent = 0
        self.start_time = time.time()

        try:
            # 创建UDP socket
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

            # 根据模式选择发送方式
            if self.use_frame_sync and self.image_data:
                # 旧格式：帧同步模式（兼容）
                self._send_frame_sync_mode()
            elif self.image_pixels:
                # 新格式：像素地址模式（64x64）
                self._send_pixel_address_mode()
            else:
                self.callback('error', "无效的图片数据格式")
                return

        except Exception as e:
            self.callback('error', f"发送错误: {e}")
            self.callback('status', 'error')

        finally:
            if self.sock:
                self.sock.close()
            self.running = False

    def _send_pixel_address_mode(self):
        """像素地址模式发送（f1+地址+RGB格式）"""
        self.callback('log', f"转换像素数据为UDP数据包...")

        # 转换像素为数据包
        packets = self.convert_pixels_to_packets()

        if not packets:
            self.callback('error', "转换数据包失败")
            return

        self.total_bytes = sum(len(p) for p in packets)
        total_pixels = len(self.image_pixels)

        self.callback('log', f"准备发送: 64×64图像 = {total_pixels} 像素")
        self.callback('log', f"数据包数量: {len(packets)}, 总字节数: {self.total_bytes}")
        self.callback('status', 'sending')

        # 分包发送
        for i, packet in enumerate(packets):
            if not self.running:
                self.callback('log', "发送已取消")
                self.callback('status', 'stopped')
                return

            self.sock.sendto(packet, (self.target_ip, self.target_port))

            self.packet_count += 1
            self.bytes_sent += len(packet)

            # 更新进度
            progress = min(100, int(self.bytes_sent / self.total_bytes * 100))
            self.callback('progress', progress)

            # 每10包更新一次统计
            if self.packet_count % 10 == 0:
                self.callback('stats_update', None)

            # 显示进度（每100包或最后一包）
            if (i + 1) % 100 == 0 or (i + 1) == len(packets):
                progress_pct = (i + 1) / len(packets) * 100
                self.callback('log', f"发送进度: {i+1}/{len(packets)} ({progress_pct:.1f}%)")

            # 添加延迟避免拥塞
            time.sleep(self.delay)

        # 发送完成
        elapsed = time.time() - self.start_time
        rate_kbps = (self.bytes_sent * 8 / elapsed / 1000) if elapsed > 0 else 0

        self.callback('status', 'complete')
        self.callback('log', f"✅ 图像发送完成!")
        self.callback('log', f"用时: {elapsed:.2f}秒, 速率: {rate_kbps:.1f} Kbps")

    def _send_frame_sync_mode(self):
        """帧同步模式发送（旧格式兼容）"""
        # 准备数据
        data = self.FRAME_HEADER + self.image_data + self.FRAME_FOOTER
        self.total_bytes = len(data)
        self.callback('log', f"使用帧同步模式发送，总大小: {self.total_bytes} 字节")

        total_chunks = (len(data) + self.chunk_size - 1) // self.chunk_size
        self.callback('log', f"开始发送: {self.target_ip}:{self.target_port}, 总包数: {total_chunks}")
        self.callback('status', 'sending')

        # 分包发送
        for i in range(0, len(data), self.chunk_size):
            if not self.running:
                self.callback('log', "发送已取消")
                break

            chunk = data[i:i+self.chunk_size]
            self.sock.sendto(chunk, (self.target_ip, self.target_port))

            self.packet_count += 1
            self.bytes_sent += len(chunk)

            # 更新进度
            progress = min(100, int(self.bytes_sent / len(data) * 100))
            self.callback('progress', progress)

            # 每10包更新一次统计
            if self.packet_count % 10 == 0:
                self.callback('stats_update', None)

            # 添加延迟避免拥塞
            time.sleep(self.delay)

        elapsed = time.time() - self.start_time
        rate_kbps = (self.bytes_sent * 8 / elapsed / 1000) if elapsed > 0 else 0

        if self.running:  # 正常完成
            self.callback('status', 'complete')
            self.callback('log', f"发送完成: {self.bytes_sent} 字节, 用时: {elapsed:.2f}秒, 速率: {rate_kbps:.1f} Kbps")
        else:  # 被取消
            self.callback('status', 'stopped')

    def stop(self):
        """停止发送"""
        self.running = False

    def get_stats(self):
        """获取统计信息"""
        elapsed = 0
        rate_kbps = 0
        if self.start_time:
            elapsed = time.time() - self.start_time
            if elapsed > 0:
                rate_kbps = self.bytes_sent * 8 / elapsed / 1000

        return {
            'packets': self.packet_count,
            'bytes_sent': self.bytes_sent,
            'total_bytes': self.total_bytes,
            'progress': min(100, int(self.bytes_sent / self.total_bytes * 100)) if self.total_bytes > 0 else 0,
            'elapsed': elapsed,
            'rate_kbps': rate_kbps,
            'complete': self.bytes_sent >= self.total_bytes if self.total_bytes > 0 else False
        }


class ImageReceiverThread(threading.Thread):
    """单图UDP接收线程 - 增强版（支持帧同步、丢包检测）"""
    def __init__(self, callback):
        super().__init__()
        self.running = False
        self.callback = callback
        self.sock = None
        self.udp_ip = "192.168.240.2"
        self.udp_port = 3
        self.width = 640
        self.height = 480
        self.channels = 3
        self.image_size = self.width * self.height * self.channels
        self.image_buffer = bytearray()
        self.timeout = 5.0

        # 帧同步标识（参考udp_debug_tool.py，3字节）
        self.FRAME_HEADER = b'\xAA\x55\xAA'  # 帧头: 0xAA55AA
        self.FRAME_FOOTER = b'\x55\xAA\x55'  # 帧尾: 0x55AA55
        self.use_frame_sync = True  # 是否使用帧同步

        # 统计信息（增强）
        self.packet_count = 0
        self.total_bytes = 0
        self.error_count = 0  # 错误计数
        self.lost_packets = 0  # 丢包数
        self.receiving = False
        self.image_complete = False

        # 时间统计
        self.start_time = None
        self.last_packet_time = None

        # 序列号（丢包检测）
        self.last_seq_num = None
        self.expected_packets = 0

    def set_config(self, ip, port, width, height, timeout):
        """设置配置参数"""
        self.udp_ip = ip
        self.udp_port = port
        self.width = width
        self.height = height
        self.image_size = width * height * self.channels
        self.timeout = timeout

    def run(self):
        """线程主循环"""
        self.running = True
        self.image_buffer.clear()
        self.packet_count = 0
        self.total_bytes = 0
        self.error_count = 0
        self.lost_packets = 0
        self.receiving = False
        self.image_complete = False
        self.start_time = time.time()
        self.last_packet_time = None
        self.last_seq_num = None

        # 计算预期包数（假设每包1400字节）
        if self.use_frame_sync:
            total_size = self.image_size + len(self.FRAME_HEADER) + len(self.FRAME_FOOTER)
        else:
            total_size = self.image_size
        self.expected_packets = (total_size + 1399) // 1400

        try:
            # 创建UDP socket
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.udp_ip, self.udp_port))
            self.sock.settimeout(self.timeout)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8*1024*1024)

            mode_str = "帧同步模式" if self.use_frame_sync else "直接模式"
            self.callback('log', f"开始接收图片: {self.udp_ip}:{self.udp_port} ({mode_str})")
            self.callback('log', f"图像分辨率: {self.width}x{self.height}, 预期包数: ~{self.expected_packets}")
            self.callback('status', 'waiting')

            while self.running and not self.image_complete:
                try:
                    # 接收数据
                    data, addr = self.sock.recvfrom(65535)
                    self.last_packet_time = time.time()

                    if not self.receiving:
                        self.receiving = True
                        self.callback('status', 'receiving')
                        self.callback('log', f"开始接收数据，来源: {addr[0]}")

                    self.packet_count += 1
                    self.total_bytes += len(data)

                    # 添加到缓冲区
                    self.image_buffer.extend(data)

                    # 更新统计信息
                    self.callback('stats_update', None)

                    # 更新进度
                    target_size = self.image_size + (8 if self.use_frame_sync else 0)
                    progress = min(100, int(len(self.image_buffer) / target_size * 100))
                    self.callback('progress', progress)

                    # 检查是否接收完整图片
                    if self.use_frame_sync:
                        # 使用帧同步模式
                        if len(self.image_buffer) >= self.image_size + 8:
                            self._process_frame_with_sync()
                    else:
                        # 直接模式
                        if len(self.image_buffer) >= self.image_size:
                            self._process_frame_direct()

                except socket.timeout:
                    if self.receiving and not self.image_complete:
                        self.callback('timeout', None)
                        self.callback('status', 'timeout')
                        self.callback('log', "接收超时")
                    else:
                        self.callback('status', 'waiting')

                except Exception as e:
                    if self.running:
                        self.error_count += 1
                        self.callback('error', f"接收错误: {e}")
                        self.callback('status', 'error')

        except Exception as e:
            self.callback('error', f"Socket创建失败: {e}")
            self.callback('status', 'error')

        finally:
            if self.sock:
                self.sock.close()
            self.callback('log', "图片接收已停止")
            if not self.image_complete:
                self.callback('status', 'stopped')

    def _process_frame_with_sync(self):
        """处理带帧同步的图片数据"""
        try:
            # 查找帧头
            header_pos = self.image_buffer.find(self.FRAME_HEADER)
            if header_pos == -1:
                # 没找到帧头，继续接收
                # 如果缓冲区太大，清理开头部分
                if len(self.image_buffer) > self.image_size + 1000:
                    self.image_buffer = self.image_buffer[-(self.image_size + 100):]
                    self.error_count += 1
                    self.callback('log', "警告: 未找到帧头，清理缓冲区")
                return

            # 检查是否有完整帧（帧头+图片+帧尾）
            required_size = header_pos + 4 + self.image_size + 4
            if len(self.image_buffer) < required_size:
                return  # 数据不够，继续接收

            # 检查帧尾
            footer_pos = header_pos + 4 + self.image_size
            footer = self.image_buffer[footer_pos:footer_pos+4]

            if footer != self.FRAME_FOOTER:
                self.error_count += 1
                self.callback('log', f"警告: 帧尾错误，期望{self.FRAME_FOOTER.hex()}，收到{footer.hex()}")
                # 跳过这个帧头，继续查找
                self.image_buffer = self.image_buffer[header_pos+1:]
                return

            # 提取图片数据
            image_data = bytes(self.image_buffer[header_pos+4:header_pos+4+self.image_size])

            # 转换并显示
            img_array = np.frombuffer(image_data, dtype=np.uint8)
            img = img_array.reshape((self.height, self.width, self.channels))

            self.callback('image', img)
            self.callback('status', 'complete')

            elapsed = time.time() - self.start_time
            rate_kbps = (self.total_bytes * 8 / elapsed / 1000) if elapsed > 0 else 0
            self.callback('log', f"图片接收完成: {self.total_bytes} 字节, 用时: {elapsed:.2f}秒, 速率: {rate_kbps:.1f} Kbps")

            self.image_complete = True

        except Exception as e:
            self.error_count += 1
            self.callback('error', f"图像处理错误: {e}")
            self.callback('status', 'error')
            self.image_buffer.clear()

    def _process_frame_direct(self):
        """处理无帧同步的图片数据"""
        try:
            image_data = bytes(self.image_buffer[:self.image_size])

            # 转换并显示
            img_array = np.frombuffer(image_data, dtype=np.uint8)
            img = img_array.reshape((self.height, self.width, self.channels))

            self.callback('image', img)
            self.callback('status', 'complete')

            elapsed = time.time() - self.start_time
            rate_kbps = (self.total_bytes * 8 / elapsed / 1000) if elapsed > 0 else 0
            self.callback('log', f"图片接收完成: {self.total_bytes} 字节, 用时: {elapsed:.2f}秒, 速率: {rate_kbps:.1f} Kbps")

            self.image_complete = True

        except Exception as e:
            self.error_count += 1
            self.callback('error', f"图像转换错误: {e}")
            self.callback('status', 'error')
            self.image_buffer.clear()

    def stop(self):
        """停止线程"""
        self.running = False

    def reset(self):
        """重置状态（用于接收新图片）"""
        self.image_buffer.clear()
        self.packet_count = 0
        self.total_bytes = 0
        self.error_count = 0
        self.lost_packets = 0
        self.receiving = False
        self.image_complete = False
        self.start_time = None
        self.last_packet_time = None
        self.last_seq_num = None

    def get_stats(self):
        """获取统计信息（增强版）"""
        # 计算速率
        elapsed = 0
        rate_kbps = 0
        if self.start_time:
            elapsed = time.time() - self.start_time
            if elapsed > 0:
                rate_kbps = self.total_bytes * 8 / elapsed / 1000

        return {
            'packets': self.packet_count,
            'bytes': self.total_bytes,
            'buffer': len(self.image_buffer),
            'progress': min(100, int(len(self.image_buffer) / self.image_size * 100)) if self.image_size > 0 else 0,
            'complete': self.image_complete,
            'errors': self.error_count,
            'lost': self.lost_packets,
            'elapsed': elapsed,
            'rate_kbps': rate_kbps,
            'expected_packets': self.expected_packets
        }


class AppleButton(tk.Canvas):
    """Apple风格按钮"""
    def __init__(self, parent, text, command, width=120, height=36,
                 bg_color=None, text_color=None, style="primary"):
        super().__init__(parent, width=width, height=height,
                        bg=AppleColors.BG_SECONDARY, highlightthickness=0, cursor="hand2")

        self.command = command

        # 根据样式设置颜色
        if style == "primary":
            self.bg_color = bg_color or AppleColors.PRIMARY
            self.text_color = text_color or "#FFFFFF"
        elif style == "secondary":
            self.bg_color = bg_color or AppleColors.BG_TERTIARY
            self.text_color = text_color or AppleColors.TEXT_PRIMARY
        elif style == "success":
            self.bg_color = bg_color or AppleColors.SUCCESS
            self.text_color = text_color or "#FFFFFF"
        elif style == "danger":
            self.bg_color = bg_color or AppleColors.ERROR
            self.text_color = text_color or "#FFFFFF"
        else:
            self.bg_color = bg_color or AppleColors.PRIMARY
            self.text_color = text_color or "#FFFFFF"

        self.hover_color = self.adjust_brightness(self.bg_color, -0.1)
        self.active_color = self.adjust_brightness(self.bg_color, -0.2)
        self.pressed = False

        # 根据按钮大小计算圆角半径和字体大小
        radius = int(height / 3)  # 圆角半径约为高度的1/3
        font_size = max(8, int(height / 3.5))  # 字体大小约为高度的1/3.5，最小8

        # 创建圆角矩形按钮
        self.btn_rect = self.create_rounded_rect(0, 0, width, height, radius,
                                                 fill=self.bg_color, outline="")

        # 文字
        self.text_id = self.create_text(width//2, height//2, text=text,
                                        fill=self.text_color,
                                        font=("SF Pro Display", font_size, "normal"))

        # 绑定事件
        self.bind("<Button-1>", self.on_click)
        self.bind("<ButtonRelease-1>", self.on_release)
        self.bind("<Enter>", self.on_enter)
        self.bind("<Leave>", self.on_leave)

    def create_rounded_rect(self, x1, y1, x2, y2, radius, **kwargs):
        """创建圆角矩形"""
        points = [
            x1+radius, y1,
            x2-radius, y1,
            x2, y1,
            x2, y1+radius,
            x2, y2-radius,
            x2, y2,
            x2-radius, y2,
            x1+radius, y2,
            x1, y2,
            x1, y2-radius,
            x1, y1+radius,
            x1, y1
        ]
        return self.create_polygon(points, smooth=True, **kwargs)

    def adjust_brightness(self, color, amount):
        """调整颜色亮度"""
        r = int(color[1:3], 16)
        g = int(color[3:5], 16)
        b = int(color[5:7], 16)

        if amount < 0:  # 变暗
            r = int(r * (1 + amount))
            g = int(g * (1 + amount))
            b = int(b * (1 + amount))
        else:  # 变亮
            r = min(255, int(r + (255-r)*amount))
            g = min(255, int(g + (255-g)*amount))
            b = min(255, int(b + (255-b)*amount))

        return f"#{r:02x}{g:02x}{b:02x}"

    def on_click(self, e):
        self.pressed = True
        self.itemconfig(self.btn_rect, fill=self.active_color)

    def on_release(self, e):
        if self.pressed:
            self.itemconfig(self.btn_rect, fill=self.bg_color)
            self.command()
        self.pressed = False

    def on_enter(self, e):
        if not self.pressed:
            self.itemconfig(self.btn_rect, fill=self.hover_color)

    def on_leave(self, e):
        if not self.pressed:
            self.itemconfig(self.btn_rect, fill=self.bg_color)
        self.pressed = False


class RoundedCard(tk.Canvas):
    """圆角卡片容器"""
    def __init__(self, parent, width, height, radius=16, bg_color=AppleColors.BG_SECONDARY):
        super().__init__(parent, width=width, height=height,
                        bg=AppleColors.BG_PRIMARY, highlightthickness=0)

        self.radius = radius
        self.bg_color = bg_color

        # 创建圆角矩形背景
        self.card_rect = self.create_rounded_rect(0, 0, width, height, radius,
                                                  fill=bg_color, outline="")

        # 创建内部容器
        self.inner_frame = tk.Frame(self, bg=bg_color)
        self.create_window(width//2, height//2, window=self.inner_frame,
                          width=width-radius*2, height=height-radius*2)

    def create_rounded_rect(self, x1, y1, x2, y2, radius, **kwargs):
        """创建圆角矩形"""
        points = [
            x1+radius, y1,
            x2-radius, y1,
            x2, y1,
            x2, y1+radius,
            x2, y2-radius,
            x2, y2,
            x2-radius, y2,
            x1+radius, y2,
            x1, y2,
            x1, y2-radius,
            x1, y1+radius,
            x1, y1
        ]
        return self.create_polygon(points, smooth=True, **kwargs)


class EthernetHostGUI:
    """以太网上位机GUI主类（Apple风格）"""

    def __init__(self, root):
        self.root = root
        self.root.title("以太网UDP控制中心")

        # 初始化缩放因子
        self.scale_factor = 1.0

        # DPI感知和缩放设置
        self.setup_dpi_awareness()

        # 根据DPI设置窗口大小（优化高度）
        base_width = 1100
        base_height = 820
        self.root.geometry(f"{int(base_width * self.scale_factor)}x{int(base_height * self.scale_factor)}")
        self.root.configure(bg=AppleColors.BG_PRIMARY)

        # 配置 (PC作为发送端)
        self.local_ip = "192.168.240.2"    # PC本地IP
        self.local_port = 2                # PC本地端口
        self.target_ip = "192.168.240.1"   # FPGA目标IP
        self.target_port = 1               # FPGA目标端口

        # UDP Socket
        self.udp_socket = None
        self.is_connected = False
        self.receive_thread = None
        self.running = False

        # 串口配置
        self.serial_port = None
        self.serial_connected = False

        # 数据缓存
        self.digit_value = 0
        self.led_value = 0x0

        # 创建界面
        self.create_widgets()

    def setup_dpi_awareness(self):
        """设置DPI感知和缩放比例"""
        try:
            # 对于Windows，启用DPI感知（需要在获取DPI之前）
            try:
                from ctypes import windll
                windll.shcore.SetProcessDpiAwareness(1)
            except:
                pass

            # 尝试获取屏幕DPI
            dpi = self.root.winfo_fpixels('1i')

            # 计算缩放因子（基准96 DPI）
            self.scale_factor = dpi / 96.0

            # 限制缩放范围在0.75到2.0之间
            self.scale_factor = max(0.75, min(2.0, self.scale_factor))

            print(f"检测到DPI: {dpi}, 缩放因子: {self.scale_factor}")

        except Exception as e:
            # 如果检测失败，使用默认缩放
            print(f"DPI检测失败: {e}, 使用默认缩放1.0")
            self.scale_factor = 1.0

        # 不再使用tk scaling，因为它会影响所有组件
        # 我们通过手动缩放每个元素来实现更精确的控制

    def scale(self, value):
        """根据DPI缩放像素值"""
        return int(value * self.scale_factor)

    def create_widgets(self):
        """创建Apple风格界面"""
        # 主容器
        main = tk.Frame(self.root, bg=AppleColors.BG_PRIMARY)
        main.pack(fill='both', expand=True, padx=self.scale(30), pady=self.scale(20))

        # 顶部标题
        self.create_header(main)

        # 串口控制区域（在标签页之前）
        self.create_serial_control(main)

        # 创建标签页容器
        self.create_tab_container(main)

        # 初始日志
        self.log("系统已启动", "info")
        self.log(f"配置: {self.local_ip}:{self.local_port} → {self.target_ip}:{self.target_port}", "info")

    def create_tab_container(self, parent):
        """创建标签页容器"""
        # 标签页样式配置
        style = ttk.Style()
        style.theme_use('default')

        # 配置标签页样式 - Apple风格
        style.configure('TNotebook',
                       background=AppleColors.BG_PRIMARY,
                       borderwidth=0,
                       tabmargins=[0, 0, 0, 0])

        style.configure('TNotebook.Tab',
                       background=AppleColors.BG_TERTIARY,
                       foreground=AppleColors.TEXT_SECONDARY,
                       padding=[self.scale(20), self.scale(12)],
                       font=('SF Pro Display', self.scale(13)),
                       borderwidth=0)

        style.map('TNotebook.Tab',
                 background=[('selected', AppleColors.BG_SECONDARY)],
                 foreground=[('selected', AppleColors.PRIMARY)],
                 expand=[('selected', [1, 1, 1, 0])])

        # 创建标签页控件
        self.notebook = ttk.Notebook(parent, style='TNotebook')
        self.notebook.pack(fill='both', expand=True, pady=(self.scale(16), 0))

        # 创建各个标签页
        self.create_led_control_tab()
        self.create_image_send_tab()
        self.create_image_send_advanced_tab()  # 新增：图片发送升级版
        self.create_video_send_tab()  # 新增：视频发送
        self.create_sd_receive_tab()
        self.create_camera_video_tab()
        self.create_extended_receive_tab()  # 拓展2
        self.create_extended3_receive_tab()  # 新增：拓展3

    def create_led_control_tab(self):
        """创建LED控制标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='LED控制')

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 网络配置卡片（移到LED控制标签页）
        self.create_network_card(content)

        # 控制区域（两列）
        controls = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        controls.pack(fill='both', expand=True, pady=self.scale(10))

        left = tk.Frame(controls, bg=AppleColors.BG_PRIMARY)
        left.pack(side='left', fill='both', expand=True, padx=(0, self.scale(10)))

        right = tk.Frame(controls, bg=AppleColors.BG_PRIMARY)
        right.pack(side='right', fill='both', expand=True, padx=(self.scale(10), 0))

        # 数码管和LED卡片
        self.create_digit_card(left)
        self.create_led_card(right)

        # 接收数据和日志
        self.create_receive_card(content)
        self.create_log_card(content)

    def create_image_send_tab(self):
        """创建图片发送标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='图片发送')

        # 初始化图片发送线程
        self.send_thread = None
        self.send_image_data = None
        self.send_image_pil = None

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 图片预览（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_send_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：图片预览区域
        preview_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        preview_frame.pack(side='right', fill='both', expand=True)

        self.create_send_preview(preview_frame)

        # 下部：发送统计
        self.create_send_stats(content)

    def create_send_control_panel(self, parent):
        """创建图片发送控制面板"""
        # 固定宽度的控制面板
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(280))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="图片发送",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 文件选择
        file_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        file_frame.pack(fill='x', pady=(0, self.scale(8)))

        tk.Label(file_frame, text="图片文件",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.send_file_label = tk.Label(file_frame, text="未选择文件",
                font=("SF Mono", self.scale(8)),
                bg=AppleColors.BG_TERTIARY,
                fg=AppleColors.TEXT_TERTIARY,
                anchor='w',
                padx=self.scale(8),
                pady=self.scale(5))
        self.send_file_label.pack(fill='x', pady=(0, self.scale(4)))

        AppleButton(file_frame, "选择图片", self.select_image_file,
                   width=self.scale(240), height=self.scale(28), style="secondary").pack()

        # 配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(self.scale(8), self.scale(8)))

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # 目标IP
        tk.Label(config_frame, text="目标IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.send_ip_entry = tk.Entry(config_frame, **entry_style)
        self.send_ip_entry.insert(0, "192.168.240.1")
        self.send_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.send_port_entry = tk.Entry(config_frame, **entry_style)
        self.send_port_entry.insert(0, "4")
        self.send_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 帧同步选项
        sync_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        sync_frame.pack(fill='x', pady=(self.scale(4), 0))

        self.send_frame_sync_var = tk.IntVar(value=1)
        cb = tk.Checkbutton(sync_frame, text="启用帧同步 (推荐)",
                           variable=self.send_frame_sync_var,
                           bg=AppleColors.BG_SECONDARY,
                           fg=AppleColors.TEXT_PRIMARY,
                           selectcolor=AppleColors.BG_TERTIARY,
                           font=("SF Pro Display", self.scale(9)),
                           activebackground=AppleColors.BG_SECONDARY)
        cb.pack(anchor='w')

        # 控制按钮
        btn_container = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        btn_container.pack(fill='x', pady=(self.scale(8), 0))

        self.send_start_btn = AppleButton(btn_container, "开始发送", self.start_image_send,
                                          width=self.scale(240), height=self.scale(32), style="success")
        self.send_start_btn.pack(pady=(0, self.scale(5)))

        self.send_stop_btn = AppleButton(btn_container, "停止发送", self.stop_image_send,
                                         width=self.scale(240), height=self.scale(32), style="danger")
        self.send_stop_btn.pack()

        return panel_frame

    def create_send_preview(self, parent):
        """创建图片预览区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="图片预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 图片显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.send_canvas = tk.Canvas(display_frame,
                                      width=self.scale(640),
                                      height=self.scale(480),
                                      bg=AppleColors.BG_TERTIARY,
                                      highlightthickness=1,
                                      highlightbackground=AppleColors.BORDER)
        self.send_canvas.pack()

        # 默认提示文字
        self.send_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待选择图片...\\n点击\"选择图片\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_send_stats(self, parent):
        """创建发送统计信息卡片"""
        card = self.create_card(parent, height=self.scale(100))

        # 标题
        tk.Label(card, text="发送统计",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建两行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(5)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(5)
        }

        # 第一行：状态、进度、包数
        self.send_status_label = tk.Label(row1, text="状态: 等待中", **label_style)
        self.send_status_label.pack(side='left', padx=(0, self.scale(5)))

        self.send_progress_label = tk.Label(row1, text="进度: 0%", **label_style)
        self.send_progress_label.pack(side='left', padx=(0, self.scale(5)))

        self.send_packets_label = tk.Label(row1, text="包数: 0", **label_style)
        self.send_packets_label.pack(side='left')

        # 第二行：数据量、速率、用时
        self.send_bytes_label = tk.Label(row2, text="已发送: 0 KB", **label_style)
        self.send_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.send_rate_label = tk.Label(row2, text="速率: 0 Kbps", **label_style)
        self.send_rate_label.pack(side='left', padx=(0, self.scale(5)))

        self.send_elapsed_label = tk.Label(row2, text="用时: 0.0 秒", **label_style)
        self.send_elapsed_label.pack(side='left')

    def select_image_file(self):
        """选择图片文件"""
        filename = filedialog.askopenfilename(
            title="选择图片文件",
            filetypes=[
                ("图片文件", "*.png *.jpg *.jpeg *.bmp *.gif"),
                ("PNG图片", "*.png"),
                ("JPEG图片", "*.jpg *.jpeg"),
                ("BMP图片", "*.bmp"),
                ("所有文件", "*.*")
            ]
        )

        if not filename:
            return

        try:
            # 加载图片
            img = Image.open(filename)

            # 转换为RGB（如果需要）
            if img.mode != 'RGB':
                img = img.convert('RGB')

            # 显示原始尺寸信息
            orig_width, orig_height = img.size
            self.log(f"已加载图片: {filename.split('/')[-1]}, 尺寸: {orig_width}×{orig_height}", "info")

            # 调整到64x64（直接缩放，不保持纵横比）
            img = img.resize((64, 64), Image.LANCZOS)
            self.log(f"图片已缩放到: 64×64", "info")

            self.send_image_pil = img

            # 转换为像素列表（用于按像素发送）
            pixels = list(img.getdata())

            # 存储图片数据供发送线程使用
            self.send_image_pixels = pixels  # [(R,G,B), ...]
            self.send_image_data = np.array(img).tobytes()  # 保留原始数据格式（兼容性）

            # 显示预览（放大显示）
            preview_img = img.resize((self.scale(640), self.scale(640)), Image.NEAREST)  # 使用NEAREST保持像素感
            self.send_photo = ImageTk.PhotoImage(preview_img)

            self.send_canvas.delete("all")
            self.send_canvas.create_image(
                self.scale(320), self.scale(320),
                image=self.send_photo,
                anchor='center'
            )

            # 更新文件标签
            short_name = filename.split('/')[-1]
            if len(short_name) > 30:
                short_name = short_name[:27] + "..."
            self.send_file_label.config(
                text=short_name,
                fg=AppleColors.TEXT_PRIMARY
            )

            self.log(f"图片已准备，最终尺寸: 64×64, 像素数: {len(pixels)}, 大小: {len(self.send_image_data)} 字节", "success")

        except Exception as e:
            self.log(f"加载图片失败: {e}", "error")

    def start_image_send(self):
        """开始发送图片"""
        if not hasattr(self, 'send_image_pixels') or self.send_image_pixels is None:
            self.log("请先选择图片", "warning")
            return

        if self.send_thread and self.send_thread.running:
            self.log("已有发送任务正在进行", "warning")
            return

        try:
            ip = self.send_ip_entry.get()
            port = int(self.send_port_entry.get())
            use_frame_sync = bool(self.send_frame_sync_var.get())

            # 发送控制命令0x01到192.168.240.1:2222
            self.send_control_command(0x01, "图片发送开始")

            # 创建并启动线程
            self.send_thread = ImageSenderThread(self.send_callback)
            self.send_thread.set_config(ip, port, use_frame_sync)
            # 传递像素列表而不是原始字节数据
            self.send_thread.set_image_pixels(self.send_image_pixels)
            self.send_thread.start()

            # 禁用配置控件
            self.send_ip_entry.config(state='disabled')
            self.send_port_entry.config(state='disabled')

            # 开始更新统计信息
            self.update_send_stats_display()

            mode_str = "帧同步" if use_frame_sync else "像素地址"
            self.log(f"开始发送图片 ({mode_str}模式) 到 {ip}:{port}", "info")

        except Exception as e:
            self.log(f"启动失败: {e}", "error")

    def stop_image_send(self):
        """停止发送"""
        if self.send_thread and self.send_thread.running:
            self.send_thread.stop()
            self.send_thread.join(timeout=2.0)

            # 恢复控件
            self.send_ip_entry.config(state='normal')
            self.send_port_entry.config(state='normal')

            self.log("发送已停止", "warning")

    def send_callback(self, event_type, data):
        """发送回调（在线程中调用）"""
        if event_type == 'log':
            self.root.after(0, self.log, data, "info")
        elif event_type == 'error':
            self.root.after(0, self.log, data, "error")
        elif event_type == 'status':
            self.root.after(0, self.update_send_status, data)
        elif event_type == 'progress':
            self.root.after(0, self.update_send_progress, data)
        elif event_type == 'stats_update':
            if self.send_thread and self.send_thread.packet_count % 10 == 0:
                self.root.after(0, self.update_send_stats_display)

    def update_send_status(self, status):
        """更新发送状态"""
        status_text = {
            'waiting': '等待中',
            'sending': '发送中',
            'complete': '完成',
            'error': '错误',
            'stopped': '已停止'
        }
        text = status_text.get(status, status)
        self.send_status_label.config(text=f"状态: {text}")

        # 如果完成或错误，恢复控件
        if status in ['complete', 'error', 'stopped']:
            self.send_ip_entry.config(state='normal')
            self.send_port_entry.config(state='normal')

    def update_send_progress(self, progress):
        """更新发送进度"""
        self.send_progress_label.config(text=f"进度: {progress}%")

    def update_send_stats_display(self):
        """更新发送统计信息显示"""
        if self.send_thread and self.send_thread.running:
            stats = self.send_thread.get_stats()

            self.send_packets_label.config(text=f"包数: {stats['packets']}")
            self.send_bytes_label.config(text=f"已发送: {stats['bytes_sent']/1024:.1f} KB")
            self.send_rate_label.config(text=f"速率: {stats['rate_kbps']:.1f} Kbps")
            self.send_elapsed_label.config(text=f"用时: {stats['elapsed']:.1f} 秒")

            # 继续更新
            if not stats['complete']:
                self.root.after(100, self.update_send_stats_display)

    def create_sd_receive_tab(self):
        """创建SD卡接收标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='SD卡接收')

        # 初始化图片接收线程
        self.image_thread = None
        self.current_image = None

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 图片显示（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_image_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：图片显示区域
        image_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        image_frame.pack(side='right', fill='both', expand=True)

        self.create_image_display(image_frame)

        # 下部：统计信息 - 已禁用（简化UI）
        # self.create_image_stats(content)

    def create_image_control_panel(self, parent):
        """创建图片接收控制面板"""
        # 固定宽度的控制面板
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(280))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="图片接收",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(0, self.scale(8)))

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # IP地址
        tk.Label(config_frame, text="接收IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.image_ip_entry = tk.Entry(config_frame, **entry_style)
        self.image_ip_entry.insert(0, "192.168.240.2")
        self.image_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.image_port_entry = tk.Entry(config_frame, **entry_style)
        self.image_port_entry.insert(0, "3")
        self.image_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 分辨率
        tk.Label(config_frame, text="分辨率",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        res_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        res_frame.pack(fill='x', pady=(0, self.scale(6)))

        width_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        width_frame.pack(side='left', fill='x', expand=True, padx=(0, self.scale(3)))

        self.image_width_entry = tk.Entry(width_frame, **entry_style)
        self.image_width_entry.insert(0, "640")
        self.image_width_entry.pack(fill='x', ipady=self.scale(5))

        tk.Label(res_frame, text="×",
                font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(side='left', padx=self.scale(2))

        height_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        height_frame.pack(side='left', fill='x', expand=True, padx=(self.scale(3), 0))

        self.image_height_entry = tk.Entry(height_frame, **entry_style)
        self.image_height_entry.insert(0, "480")
        self.image_height_entry.pack(fill='x', ipady=self.scale(5))

        # 超时设置
        tk.Label(config_frame, text="超时(秒)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.image_timeout_entry = tk.Entry(config_frame, **entry_style)
        self.image_timeout_entry.insert(0, "5")
        self.image_timeout_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(8)))

        # 控制按钮
        self.image_start_btn = AppleButton(content_frame, "开始接收", self.start_image_receive,
                                          width=self.scale(240), height=self.scale(32), style="success")
        self.image_start_btn.pack(pady=(0, self.scale(5)))

        self.image_stop_btn = AppleButton(content_frame, "停止接收", self.stop_image_receive,
                                         width=self.scale(240), height=self.scale(32), style="danger")
        self.image_stop_btn.pack(pady=(0, self.scale(5)))

        self.image_save_btn = AppleButton(content_frame, "保存图片", self.save_image,
                                         width=self.scale(240), height=self.scale(32), style="secondary")
        self.image_save_btn.pack(pady=(0, self.scale(5)))

        self.image_clear_btn = AppleButton(content_frame, "清空重置", self.clear_image,
                                          width=self.scale(240), height=self.scale(32), style="secondary")
        self.image_clear_btn.pack()

        return panel_frame

    def create_image_display(self, parent):
        """创建图片显示区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="图片预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 图片显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.image_canvas = tk.Canvas(display_frame,
                                      width=self.scale(640),
                                      height=self.scale(480),
                                      bg=AppleColors.BG_TERTIARY,
                                      highlightthickness=1,
                                      highlightbackground=AppleColors.BORDER)
        self.image_canvas.pack()

        # 默认提示文字
        self.image_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待图片接收...\\n点击\\\"开始接收\\\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_image_stats(self, parent):
        """创建图片统计信息卡片（增强版）"""
        card = self.create_card(parent, height=self.scale(130))

        # 标题
        tk.Label(card, text="接收统计（增强）",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建三行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(4)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x', pady=(0, self.scale(4)))

        row3 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row3.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(4)
        }

        # 第一行：状态、进度、包数
        self.image_status_label = tk.Label(row1, text="状态: 等待中", **label_style)
        self.image_status_label.pack(side='left', padx=(0, self.scale(5)))

        self.image_progress_label = tk.Label(row1, text="进度: 0%", **label_style)
        self.image_progress_label.pack(side='left', padx=(0, self.scale(5)))

        self.image_packets_label = tk.Label(row1, text="包数: 0/~0", **label_style)
        self.image_packets_label.pack(side='left')

        # 第二行：数据量、速率、缓冲
        self.image_bytes_label = tk.Label(row2, text="数据量: 0 KB", **label_style)
        self.image_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.image_rate_label = tk.Label(row2, text="速率: 0 Kbps", **label_style)
        self.image_rate_label.pack(side='left', padx=(0, self.scale(5)))

        self.image_buffer_label = tk.Label(row2, text="缓冲: 0 KB", **label_style)
        self.image_buffer_label.pack(side='left')

        # 第三行：用时、错误、模式
        self.image_elapsed_label = tk.Label(row3, text="用时: 0.0 秒", **label_style)
        self.image_elapsed_label.pack(side='left', padx=(0, self.scale(5)))

        self.image_errors_label = tk.Label(row3, text="错误: 0", **label_style)
        self.image_errors_label.pack(side='left', padx=(0, self.scale(5)))

        self.image_mode_label = tk.Label(row3, text="模式: 帧同步", **label_style)
        self.image_mode_label.pack(side='left')

    def image_callback(self, event_type, data):
        """图片接收回调（在线程中调用）"""
        if event_type == 'image':
            self.root.after(0, self.update_image_display, data)
        elif event_type == 'log':
            self.root.after(0, self.log, data, "info")
        elif event_type == 'error':
            self.root.after(0, self.log, data, "error")
        elif event_type == 'timeout':
            self.root.after(0, self.log, "警告: 接收超时", "warning")
        elif event_type == 'status':
            self.root.after(0, self.update_image_status, data)
        elif event_type == 'progress':
            self.root.after(0, self.update_image_progress, data)
        elif event_type == 'stats_update':
            # 新增：实时更新统计信息
            if self.image_thread and self.image_thread.packet_count % 10 == 0:  # 每10包更新一次
                self.root.after(0, self.update_image_stats_display)

    def update_image_display(self, img):
        """更新图片显示"""
        try:
            # 保存当前图片
            self.current_image = img

            # 转换numpy数组到PIL Image
            pil_img = Image.fromarray(img)

            # 调整大小以适应Canvas
            canvas_width = self.scale(640)
            canvas_height = self.scale(480)
            pil_img = pil_img.resize((canvas_width, canvas_height), Image.LANCZOS)

            # 转换为PhotoImage
            self.image_photo = ImageTk.PhotoImage(pil_img)

            # 清除Canvas并显示图像
            self.image_canvas.delete("all")
            self.image_canvas.create_image(
                canvas_width//2, canvas_height//2,
                image=self.image_photo,
                anchor='center'
            )

        except Exception as e:
            self.log(f"显示错误: {e}", "error")

    def update_image_status(self, status):
        """更新接收状态"""
        if not hasattr(self, 'image_status_label'):
            return  # 统计功能已禁用
        status_text = {
            'waiting': '等待中',
            'receiving': '接收中',
            'complete': '完成',
            'error': '错误',
            'timeout': '超时',
            'stopped': '已停止'
        }
        text = status_text.get(status, status)
        self.image_status_label.config(text=f"状态: {text}")

    def update_image_progress(self, progress):
        """更新接收进度"""
        if not hasattr(self, 'image_progress_label'):
            return  # 统计功能已禁用
        self.image_progress_label.config(text=f"进度: {progress}%")

    def update_image_stats_display(self):
        """更新统计信息显示（定时调用） - 增强版"""
        if not hasattr(self, 'image_packets_label'):
            return  # 统计功能已禁用
        if self.image_thread and self.image_thread.running:
            stats = self.image_thread.get_stats()

            # 更新所有统计标签
            self.image_packets_label.config(
                text=f"包数: {stats['packets']}/~{stats['expected_packets']}")
            self.image_bytes_label.config(
                text=f"数据量: {stats['bytes']/1024:.1f} KB")
            self.image_buffer_label.config(
                text=f"缓冲: {stats['buffer']/1024:.1f} KB")
            self.image_rate_label.config(
                text=f"速率: {stats['rate_kbps']:.1f} Kbps")
            self.image_elapsed_label.config(
                text=f"用时: {stats['elapsed']:.1f} 秒")
            self.image_errors_label.config(
                text=f"错误: {stats['errors']}")

            # 继续更新
            if not stats['complete']:
                self.root.after(100, self.update_image_stats_display)

    def start_image_receive(self):
        """开始图片接收（UDP接收单帧图片）"""
        try:
            # 发送控制命令0x01到192.168.240.1:2222
            self.send_control_command(0x01, "图片接收开始")

            # 获取配置
            ip = self.image_ip_entry.get()
            port = int(self.image_port_entry.get())
            width = int(self.image_width_entry.get())
            height = int(self.image_height_entry.get())
            timeout = float(self.image_timeout_entry.get())

            # 创建并启动接收线程
            self.image_thread = ImageReceiverThread(self.image_callback)
            self.image_thread.set_config(ip, port, width, height, timeout)
            self.image_thread.start()

            # 更新按钮状态
            self.image_ip_entry.config(state='disabled')
            self.image_port_entry.config(state='disabled')
            self.image_width_entry.config(state='disabled')
            self.image_height_entry.config(state='disabled')
            self.image_timeout_entry.config(state='disabled')

            self.log(f"图片接收已启动: {ip}:{port}", "success")
            self.log(f"等待接收 {width}×{height} 图片...", "info")

        except Exception as e:
            self.log(f"启动失败: {e}", "error")

    def stop_image_receive(self):
        """停止图片接收"""
        if self.image_thread and self.image_thread.running:
            self.image_thread.stop()
            self.image_thread.join(timeout=2.0)

        # 恢复按钮状态
        self.image_ip_entry.config(state='normal')
        self.image_port_entry.config(state='normal')
        self.image_width_entry.config(state='normal')
        self.image_height_entry.config(state='normal')
        self.image_timeout_entry.config(state='normal')

        self.log("图片接收已停止", "warning")

    def save_image(self):
        """保存接收到的图片"""
        if self.current_image is None:
            self.log("没有可保存的图片", "warning")
            return

        try:
            # 使用文件对话框选择保存位置
            filename = filedialog.asksaveasfilename(
                defaultextension=".png",
                filetypes=[("PNG图片", "*.png"), ("JPEG图片", "*.jpg"), ("所有文件", "*.*")],
                initialfile=f"image_{int(time.time())}.png"
            )

            if filename:
                pil_img = Image.fromarray(self.current_image)
                pil_img.save(filename)
                self.log(f"已保存: {filename}", "success")

        except Exception as e:
            self.log(f"保存失败: {e}", "error")

    def clear_image(self):
        """清空图片和重置状态（UDP接收模式）"""
        # 第1步：停止接收线程（如果正在运行）
        if self.image_thread and self.image_thread.running:
            self.image_thread.stop()
            self.image_thread.join(timeout=1.0)
            self.log("已停止接收线程", "info")

        # 第2步：清除线程对象
        self.image_thread = None

        # 第3步：清空显示
        self.image_canvas.delete("all")
        self.image_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待图片接收...\n点击\"开始接收\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

        # 第4步：恢复配置控件状态
        self.image_ip_entry.config(state='normal')
        self.image_port_entry.config(state='normal')
        self.image_width_entry.config(state='normal')
        self.image_height_entry.config(state='normal')
        self.image_timeout_entry.config(state='normal')

        # 第5步：重置变量
        self.current_image = None

        self.log("已清空图片显示并重置接收状态", "info")

    def create_camera_video_tab(self):
        """创建摄像头视频标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='摄像头视频')

        # 初始化视频接收线程
        self.video_thread = None
        self.video_start_time = None
        self.current_frame = None

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 视频显示（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_video_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：视频显示区域
        video_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        video_frame.pack(side='right', fill='both', expand=True)

        self.create_video_display(video_frame)

        # 下部：统计信息
        self.create_video_stats(content)

    def create_video_control_panel(self, parent):
        """创建视频控制面板"""
        # 固定宽度的控制面板
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(280))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="视频控制",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 视频配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(0, self.scale(8)))

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # IP地址
        tk.Label(config_frame, text="接收IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_ip_entry = tk.Entry(config_frame, **entry_style)
        self.video_ip_entry.insert(0, "192.168.240.2")
        self.video_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_port_entry = tk.Entry(config_frame, **entry_style)
        self.video_port_entry.insert(0, "2")
        self.video_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 分辨率
        tk.Label(config_frame, text="分辨率",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        res_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        res_frame.pack(fill='x', pady=(0, self.scale(6)))

        width_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        width_frame.pack(side='left', fill='x', expand=True, padx=(0, self.scale(3)))

        self.video_width_entry = tk.Entry(width_frame, **entry_style)
        self.video_width_entry.insert(0, "640")
        self.video_width_entry.pack(fill='x', ipady=self.scale(5))

        tk.Label(res_frame, text="×",
                font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(side='left', padx=self.scale(2))

        height_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        height_frame.pack(side='left', fill='x', expand=True, padx=(self.scale(3), 0))

        self.video_height_entry = tk.Entry(height_frame, **entry_style)
        self.video_height_entry.insert(0, "480")
        self.video_height_entry.pack(fill='x', ipady=self.scale(5))

        # 超时设置
        tk.Label(config_frame, text="超时(秒)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_timeout_entry = tk.Entry(config_frame, **entry_style)
        self.video_timeout_entry.insert(0, "2")
        self.video_timeout_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(8)))

        # 控制按钮
        self.video_start_btn = AppleButton(content_frame, "开始接收", self.start_video,
                                          width=self.scale(240), height=self.scale(32), style="success")
        self.video_start_btn.pack(pady=(0, self.scale(5)))

        self.video_stop_btn = AppleButton(content_frame, "停止接收", self.stop_video,
                                         width=self.scale(240), height=self.scale(32), style="danger")
        self.video_stop_btn.pack(pady=(0, self.scale(5)))

        # 快速重置按钮（新增）
        self.video_reset_btn = AppleButton(content_frame, "快速重置", self.quick_reset_video,
                                         width=self.scale(240), height=self.scale(32), style="warning")
        self.video_reset_btn.pack(pady=(0, self.scale(5)))

        self.video_save_btn = AppleButton(content_frame, "保存当前帧", self.save_video_frame,
                                         width=self.scale(240), height=self.scale(32), style="secondary")
        self.video_save_btn.pack(pady=(0, self.scale(5)))

        self.video_clear_btn = AppleButton(content_frame, "清空统计", self.clear_video_stats,
                                          width=self.scale(240), height=self.scale(32), style="secondary")
        self.video_clear_btn.pack(pady=(0, self.scale(5)))

        # 模式切换按钮
        tk.Label(content_frame, text="模式控制", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(self.scale(8), self.scale(4)))

        self.video_low_latency_btn = AppleButton(content_frame, "低延迟模式", self.enable_video_low_latency,
                                                 width=self.scale(240), height=self.scale(32), style="primary")
        self.video_low_latency_btn.pack(pady=(0, self.scale(5)))

        self.video_compressed_btn = AppleButton(content_frame, "压缩模式", self.enable_video_compressed,
                                                width=self.scale(240), height=self.scale(32), style="primary")
        self.video_compressed_btn.pack()

        return panel_frame

    def create_video_display(self, parent):
        """创建视频显示区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="视频预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 视频显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.video_canvas = tk.Canvas(display_frame,
                                      width=self.scale(640),
                                      height=self.scale(480),
                                      bg=AppleColors.BG_TERTIARY,
                                      highlightthickness=1,
                                      highlightbackground=AppleColors.BORDER)
        self.video_canvas.pack()

        # 默认提示文字
        self.video_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待视频流...\n点击\"开始接收\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_video_stats(self, parent):
        """创建视频统计信息卡片"""
        card = self.create_card(parent, height=self.scale(100))

        # 标题
        tk.Label(card, text="实时统计",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建两行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(5)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(5)
        }

        # 第一行
        self.video_fps_label = tk.Label(row1, text="FPS: 0.0", **label_style)
        self.video_fps_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_frames_label = tk.Label(row1, text="帧数: 0", **label_style)
        self.video_frames_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_packets_label = tk.Label(row1, text="包数: 0", **label_style)
        self.video_packets_label.pack(side='left')

        # 第二行
        self.video_bytes_label = tk.Label(row2, text="数据量: 0 KB", **label_style)
        self.video_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_rate_label = tk.Label(row2, text="速率: 0 KB/s", **label_style)
        self.video_rate_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_buffer_label = tk.Label(row2, text="缓冲: 0 KB", **label_style)
        self.video_buffer_label.pack(side='left')

    def video_callback(self, event_type, data):
        """视频接收回调（在线程中调用）"""
        if event_type == 'frame':
            # 使用after在主线程中更新UI
            self.root.after(0, self.update_video_frame, data)
        elif event_type == 'log':
            self.root.after(0, self.log, data, "info")
        elif event_type == 'error':
            self.root.after(0, self.log, data, "error")
        elif event_type == 'timeout':
            self.root.after(0, self.log, "警告: 接收超时", "warning")

    def update_video_frame(self, img):
        """更新视频帧显示"""
        try:
            # 保存当前帧
            self.current_frame = img

            # 转换numpy数组到PIL Image
            pil_img = Image.fromarray(img)

            # 调整大小以适应Canvas
            canvas_width = self.scale(640)
            canvas_height = self.scale(480)
            pil_img = pil_img.resize((canvas_width, canvas_height), Image.LANCZOS)

            # 转换为PhotoImage
            self.video_photo = ImageTk.PhotoImage(pil_img)

            # 清除Canvas并显示图像
            self.video_canvas.delete("all")
            self.video_canvas.create_image(
                canvas_width//2, canvas_height//2,
                image=self.video_photo,
                anchor='center'
            )

        except Exception as e:
            self.log(f"显示错误: {e}", "error")

    def update_video_stats_display(self):
        """更新统计信息显示"""
        if self.video_thread and self.video_thread.running:
            stats = self.video_thread.get_stats()

            self.video_fps_label.config(text=f"FPS: {stats['fps']:.1f}")
            self.video_frames_label.config(text=f"帧数: {stats['frames']}")
            self.video_packets_label.config(text=f"包数: {stats['packets']}")
            self.video_bytes_label.config(text=f"数据量: {stats['bytes']/1024:.1f} KB")

            if self.video_start_time:
                elapsed = time.time() - self.video_start_time
                if elapsed > 0:
                    rate = stats['bytes'] / elapsed / 1024
                    self.video_rate_label.config(text=f"速率: {rate:.1f} KB/s")

            self.video_buffer_label.config(text=f"缓冲: {stats['buffer']/1024:.1f} KB")

            # 继续更新
            self.root.after(100, self.update_video_stats_display)

    def start_video(self):
        """开始视频接收"""
        try:
            ip = self.video_ip_entry.get()
            port = int(self.video_port_entry.get())
            width = int(self.video_width_entry.get())
            height = int(self.video_height_entry.get())
            timeout = float(self.video_timeout_entry.get())

            # 创建并启动线程
            self.video_thread = VideoReceiverThread(self.video_callback)
            self.video_thread.set_config(ip, port, width, height, timeout)
            self.video_thread.start()

            self.video_start_time = time.time()

            # 更新按钮状态
            self.video_ip_entry.config(state='disabled')
            self.video_port_entry.config(state='disabled')
            self.video_width_entry.config(state='disabled')
            self.video_height_entry.config(state='disabled')
            self.video_timeout_entry.config(state='disabled')

            # 开始更新统计信息
            self.update_video_stats_display()

            self.log("视频接收已启动", "success")

        except Exception as e:
            self.log(f"启动失败: {e}", "error")

    def stop_video(self):
        """停止视频接收"""
        if self.video_thread and self.video_thread.running:
            self.video_thread.stop()
            self.video_thread.join(timeout=2.0)

            # 恢复按钮状态
            self.video_ip_entry.config(state='normal')
            self.video_port_entry.config(state='normal')
            self.video_width_entry.config(state='normal')
            self.video_height_entry.config(state='normal')
            self.video_timeout_entry.config(state='normal')

            self.log("视频接收已停止", "warning")

    def save_video_frame(self):
        """保存当前视频帧"""
        if self.current_frame is None:
            self.log("没有可保存的视频帧", "warning")
            return

        try:
            # 使用文件对话框选择保存位置
            filename = filedialog.asksaveasfilename(
                defaultextension=".png",
                filetypes=[("PNG图片", "*.png"), ("JPEG图片", "*.jpg"), ("所有文件", "*.*")],
                initialfile=f"frame_{int(time.time())}.png"
            )

            if filename:
                pil_img = Image.fromarray(self.current_frame)
                pil_img.save(filename)
                self.log(f"已保存: {filename}", "success")

        except Exception as e:
            self.log(f"保存失败: {e}", "error")

    def clear_video_stats(self):
        """清空视频统计信息"""
        if self.video_thread:
            self.video_thread.packet_count = 0
            self.video_thread.frame_count = 0
            self.video_thread.total_bytes = 0
            self.video_thread.fps_queue.clear()
            self.video_thread.frame_buffer.clear()

            self.video_start_time = time.time()

            self.log("统计信息已清空", "info")

    def enable_video_low_latency(self):
        """启用低延迟模式 - 发送0x40命令"""
        # 发送控制命令0x40到192.168.240.1:2222
        self.send_control_command(0x40, "低延迟模式")
        self.log("已启用低延迟模式 (命令: 0x40)", "success")

        # 更新按钮状态
        self.video_low_latency_btn.itemconfig(self.video_low_latency_btn.btn_rect, fill=AppleColors.SUCCESS)
        self.video_compressed_btn.itemconfig(self.video_compressed_btn.btn_rect, fill=AppleColors.PRIMARY)

    def enable_video_compressed(self):
        """启用压缩模式 - 发送0x41命令"""
        # 发送控制命令0x41到192.168.240.1:2222
        self.send_control_command(0x41, "压缩模式")
        self.log("已启用压缩模式 (命令: 0x41)", "info")

        # 更新按钮状态
        self.video_low_latency_btn.itemconfig(self.video_low_latency_btn.btn_rect, fill=AppleColors.PRIMARY)
        self.video_compressed_btn.itemconfig(self.video_compressed_btn.btn_rect, fill=AppleColors.SUCCESS)

    def quick_reset_video(self):
        """摄像头视频快速重置：停止→清除缓冲→重新开始接收"""
        self.log("执行快速重置...", "info")

        # 第1步：停止接收线程
        if self.video_thread and self.video_thread.running:
            self.video_thread.stop()
            self.video_thread.join(timeout=1.0)  # 等待线程结束
            self.log("已停止接收", "info")

        # 第2步：清除线程对象（重要：防止复用已关闭socket的线程）
        self.video_thread = None

        # 第3步：清除当前帧显示
        self.current_frame = None
        self.video_canvas.delete("all")
        self.video_canvas.create_text(
            self.scale(320), self.scale(240),
            text="正在重启接收...",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

        # 第4步：恢复按钮状态（允许修改配置）
        self.video_ip_entry.config(state='normal')
        self.video_port_entry.config(state='normal')
        self.video_width_entry.config(state='normal')
        self.video_height_entry.config(state='normal')
        self.video_timeout_entry.config(state='normal')

        # 第5步：立即重新开始接收（减少延迟到50ms）
        self.root.after(50, self.start_video)

    def create_card(self, parent, height=None):
        """创建液体玻璃风格卡片"""
        # 外层阴影容器
        shadow_container = tk.Frame(parent, bg=AppleColors.BG_PRIMARY)
        scaled_padding = self.scale(16)
        if height:
            shadow_container.pack(fill='x', pady=(0, scaled_padding))
            shadow_container.pack_propagate(False)
            # height参数已经是缩放后的值，只需加上阴影高度
            shadow_container.config(height=height+self.scale(8))
        else:
            shadow_container.pack(fill='both', expand=True, pady=(0, scaled_padding))

        # 阴影层（多层模拟柔和阴影）
        shadow3 = tk.Frame(shadow_container, bg=AppleColors.SHADOW_LIGHT)
        shadow3.place(x=self.scale(4), y=self.scale(4), relwidth=1, relheight=1,
                     width=-self.scale(8), height=-self.scale(8))

        shadow2 = tk.Frame(shadow_container, bg=AppleColors.SHADOW_LIGHT)
        shadow2.place(x=self.scale(2), y=self.scale(2), relwidth=1, relheight=1,
                     width=-self.scale(4), height=-self.scale(4))

        # 玻璃边框（模拟高光）
        glass_border = tk.Frame(shadow_container, bg=AppleColors.GLASS_BORDER,
                               highlightthickness=1, highlightbackground=AppleColors.BORDER)
        glass_border.place(x=0, y=0, relwidth=1, relheight=1)

        # 卡片主体（毛玻璃白）
        card = tk.Frame(glass_border, bg=AppleColors.BG_SECONDARY, relief='flat', bd=0)
        card.pack(fill='both', expand=True, padx=1, pady=1)

        return card

    def create_scrollable_card(self, parent, height, inner_height):
        """创建带滚动条的卡片"""
        # 外层卡片容器（固定高度）
        card = self.create_card(parent, height=height)

        # 创建Canvas和滚动条
        canvas_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        canvas_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 滚动条
        scrollbar = tk.Scrollbar(canvas_frame, orient='vertical',
                                bg=AppleColors.BG_TERTIARY,
                                troughcolor=AppleColors.BG_TERTIARY,
                                activebackground=AppleColors.PRIMARY)
        scrollbar.pack(side='right', fill='y')

        # Canvas
        canvas = tk.Canvas(canvas_frame,
                          bg=AppleColors.BG_SECONDARY,
                          yscrollcommand=scrollbar.set,
                          highlightthickness=0)
        canvas.pack(side='left', fill='both', expand=True)

        scrollbar.config(command=canvas.yview)

        # 内部Frame（实际内容容器）
        inner_frame = tk.Frame(canvas, bg=AppleColors.BG_SECONDARY)
        canvas_window = canvas.create_window((0, 0), window=inner_frame, anchor='nw')

        # 更新滚动区域
        def configure_scroll_region(event=None):
            canvas.configure(scrollregion=canvas.bbox('all'))
            # 更新Canvas窗口宽度以匹配Canvas宽度
            canvas.itemconfig(canvas_window, width=canvas.winfo_width())

        inner_frame.bind('<Configure>', configure_scroll_region)
        canvas.bind('<Configure>', lambda e: canvas.itemconfig(canvas_window, width=e.width))

        # 鼠标滚轮支持
        def on_mousewheel(event):
            canvas.yview_scroll(int(-1*(event.delta/120)), "units")

        def on_mousewheel_linux_up(event):
            canvas.yview_scroll(-1, "units")

        def on_mousewheel_linux_down(event):
            canvas.yview_scroll(1, "units")

        # 绑定滚轮事件（只在鼠标进入时生效）
        def bind_mousewheel(event):
            canvas.bind_all("<MouseWheel>", on_mousewheel)
            canvas.bind_all("<Button-4>", on_mousewheel_linux_up)
            canvas.bind_all("<Button-5>", on_mousewheel_linux_down)

        def unbind_mousewheel(event):
            canvas.unbind_all("<MouseWheel>")
            canvas.unbind_all("<Button-4>")
            canvas.unbind_all("<Button-5>")

        canvas.bind('<Enter>', bind_mousewheel)
        canvas.bind('<Leave>', unbind_mousewheel)

        return inner_frame

    def create_header(self, parent):
        """创建简洁顶部栏"""
        header = tk.Frame(parent, bg=AppleColors.BG_PRIMARY)
        header.pack(fill='x', pady=(0, self.scale(24)))

        # 左侧：标题和副标题
        left_frame = tk.Frame(header, bg=AppleColors.BG_PRIMARY)
        left_frame.pack(side='left')

        # 标题
        title = tk.Label(left_frame, text="以太网UDP控制中心",
                        font=("SF Pro Display", self.scale(28), "bold"),
                        bg=AppleColors.BG_PRIMARY, fg=AppleColors.TEXT_PRIMARY)
        title.pack(side='left')

        # 副标题
        subtitle = tk.Label(left_frame, text="LED & 数码管智能控制",
                          font=("SF Pro Display", self.scale(13)),
                          bg=AppleColors.BG_PRIMARY, fg=AppleColors.TEXT_SECONDARY)
        subtitle.pack(side='left', padx=(self.scale(12), 0), pady=(self.scale(8), 0))

        # 右侧：Anlogic Logo
        try:
            logo_img = Image.open("anlu logo.png")
            # 调整logo大小（保持宽高比）
            logo_height = self.scale(50)
            aspect_ratio = logo_img.width / logo_img.height
            logo_width = int(logo_height * aspect_ratio)
            logo_img = logo_img.resize((logo_width, logo_height), Image.LANCZOS)

            self.logo_photo = ImageTk.PhotoImage(logo_img)

            logo_label = tk.Label(header, image=self.logo_photo, bg=AppleColors.BG_PRIMARY)
            logo_label.pack(side='right', padx=(0, self.scale(10)))
        except Exception as e:
            # 如果logo加载失败，静默处理
            print(f"Logo加载提示: {e}")

    def create_serial_control(self, parent):
        """创建串口控制区域（主页面，带滚动条）"""
        # 创建带滚动条的卡片，固定高度160px，内容高度250px
        card = self.create_scrollable_card(parent, height=self.scale(160), inner_height=self.scale(250))

        # 标题
        tk.Label(card, text="串口控制", font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(10), pady=(self.scale(8), self.scale(4)))

        content = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(10)))

        # 左侧：串口配置
        config_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY, width=self.scale(220))
        config_frame.pack(side='left', fill='y', padx=(0, self.scale(16)))
        config_frame.pack_propagate(False)

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'insertbackground': AppleColors.PRIMARY,
            'highlightthickness': 1,
            'highlightcolor': AppleColors.PRIMARY,
            'highlightbackground': AppleColors.BORDER,
            'bd': 1,
            'borderwidth': 1
        }

        # 串口选择
        port_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        port_frame.pack(fill='x', pady=(0, self.scale(6)))

        tk.Label(port_frame, text="串口", font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(3)))

        self.serial_port_combo = ttk.Combobox(port_frame, state='readonly',
                                              font=('SF Pro Display', self.scale(8)),
                                              width=self.scale(18))
        self.serial_port_combo.pack(fill='x')
        self.refresh_serial_ports()

        # 波特率
        baud_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        baud_frame.pack(fill='x', pady=(0, self.scale(6)))

        tk.Label(baud_frame, text="波特率", font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(3)))

        self.serial_baud_combo = ttk.Combobox(baud_frame, state='readonly',
                                             font=('SF Pro Display', self.scale(8)),
                                             width=self.scale(18))
        self.serial_baud_combo['values'] = ['9600', '19200', '38400', '57600', '115200']
        self.serial_baud_combo.set('115200')
        self.serial_baud_combo.pack(fill='x')

        # 连接按钮和状态
        ctrl_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        ctrl_frame.pack(fill='x', pady=(self.scale(4), 0))

        self.serial_connect_btn = AppleButton(ctrl_frame, "连接", self.toggle_serial_connection,
                                             width=self.scale(90), height=self.scale(30), style="success")
        self.serial_connect_btn.pack(side='left', padx=(0, self.scale(6)))

        status_container = tk.Frame(ctrl_frame, bg=AppleColors.BG_TERTIARY)
        status_container.pack(side='left', fill='y')

        tk.Label(status_container, text="状态:", font=("SF Pro Display", self.scale(8)),
                bg=AppleColors.BG_TERTIARY, fg=AppleColors.TEXT_SECONDARY).pack(side='left', padx=(self.scale(6), self.scale(3)))

        self.serial_status_label = tk.Label(status_container, text="未连接",
                                           font=("SF Pro Display", self.scale(8), "bold"),
                                           bg=AppleColors.BG_TERTIARY, fg=AppleColors.ERROR)
        self.serial_status_label.pack(side='left', padx=(0, self.scale(6)))

        # 右侧：控制按钮
        buttons_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY)
        buttons_frame.pack(side='right', fill='both', expand=True)

        # 基础1234问
        tk.Label(buttons_frame, text="基础问题", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(4)))

        basic_row = tk.Frame(buttons_frame, bg=AppleColors.BG_SECONDARY)
        basic_row.pack(fill='x', pady=(0, self.scale(8)))

        for i in range(1, 5):
            AppleButton(basic_row, f"基础{i}问", lambda idx=i: self.send_serial_command(idx),
                       width=self.scale(100), height=self.scale(32), style="primary").pack(side='left', padx=(0, self.scale(6)))

        # 拓展1234问
        tk.Label(buttons_frame, text="拓展问题", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(4)))

        extend_row = tk.Frame(buttons_frame, bg=AppleColors.BG_SECONDARY)
        extend_row.pack(fill='x')

        for i in range(5, 9):
            AppleButton(extend_row, f"拓展{i-4}问", lambda idx=i: self.send_serial_command(idx),
                       width=self.scale(100), height=self.scale(32), style="secondary").pack(side='left', padx=(0, self.scale(6)))

    def create_network_card(self, parent):
        """创建网络配置卡片（带滚动条）"""
        card = self.create_scrollable_card(parent, height=self.scale(150), inner_height=self.scale(220))

        # 标题
        title = tk.Label(card, text="网络配置", font=("SF Pro Display", self.scale(14), "bold"),
                        bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY)
        title.pack(anchor='w', padx=self.scale(10), pady=(self.scale(8), self.scale(4)))

        content = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content.pack(fill='both', expand=True, padx=self.scale(24), pady=(0, self.scale(12)))

        # 左侧：配置区域
        config = tk.Frame(content, bg=AppleColors.BG_SECONDARY)
        config.pack(side='left', fill='both', expand=True, padx=(0, self.scale(20)))

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(10)),  # 减小字体
            'relief': 'flat',  # 改为flat
            'insertbackground': AppleColors.PRIMARY,
            'highlightthickness': 1,
            'highlightcolor': AppleColors.PRIMARY,
            'highlightbackground': AppleColors.BORDER,
            'bd': 1,  # 添加边框
            'borderwidth': 1
        }

        # 本地配置行
        local_frame = tk.Frame(config, bg=AppleColors.BG_SECONDARY)
        local_frame.pack(fill='x', pady=(0, self.scale(10)))

        # 本地IP列
        local_ip_col = tk.Frame(local_frame, bg=AppleColors.BG_SECONDARY)
        local_ip_col.pack(side='left', fill='both', expand=True, padx=(0, self.scale(12)))

        tk.Label(local_ip_col, text="本地 IP 地址", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(4)))

        self.local_ip_entry = tk.Entry(local_ip_col, **entry_style)
        self.local_ip_entry.insert(0, self.local_ip)
        self.local_ip_entry.pack(fill='x', ipady=self.scale(8), pady=(0, self.scale(2)))

        # 本地端口列
        local_port_col = tk.Frame(local_frame, bg=AppleColors.BG_SECONDARY, width=self.scale(80))
        local_port_col.pack(side='left', fill='y')
        local_port_col.pack_propagate(False)

        tk.Label(local_port_col, text="本地端口", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(4)))

        self.local_port_entry = tk.Entry(local_port_col, **entry_style)
        self.local_port_entry.insert(0, str(self.local_port))
        self.local_port_entry.pack(fill='x', ipady=self.scale(8), pady=(0, self.scale(2)))

        # 目标配置行
        target_frame = tk.Frame(config, bg=AppleColors.BG_SECONDARY)
        target_frame.pack(fill='x')

        # 目标IP列
        target_ip_col = tk.Frame(target_frame, bg=AppleColors.BG_SECONDARY)
        target_ip_col.pack(side='left', fill='both', expand=True, padx=(0, self.scale(12)))

        tk.Label(target_ip_col, text="目标 IP 地址", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(4)))

        self.target_ip_entry = tk.Entry(target_ip_col, **entry_style)
        self.target_ip_entry.insert(0, self.target_ip)
        self.target_ip_entry.pack(fill='x', ipady=self.scale(8), pady=(0, self.scale(2)))

        # 目标端口列
        target_port_col = tk.Frame(target_frame, bg=AppleColors.BG_SECONDARY, width=self.scale(80))
        target_port_col.pack(side='left', fill='y')
        target_port_col.pack_propagate(False)

        tk.Label(target_port_col, text="目标端口", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(4)))

        self.target_port_entry = tk.Entry(target_port_col, **entry_style)
        self.target_port_entry.insert(0, str(self.target_port))
        self.target_port_entry.pack(fill='x', ipady=self.scale(8), pady=(0, self.scale(2)))

        # 右侧：控制区域
        ctrl = tk.Frame(content, bg=AppleColors.BG_SECONDARY, width=self.scale(120))
        ctrl.pack(side='right', fill='y')
        ctrl.pack_propagate(False)

        # 连接按钮
        self.connect_btn = AppleButton(ctrl, "连接", self.toggle_connection,
                                     width=self.scale(120), height=self.scale(44), style="success")
        self.connect_btn.pack(pady=(0, self.scale(10)))

        # 状态框
        status_frame = tk.Frame(ctrl, bg=AppleColors.BG_TERTIARY)
        status_frame.pack(fill='both', expand=True)

        status_label_container = tk.Frame(status_frame, bg=AppleColors.BG_TERTIARY)
        status_label_container.pack(expand=True)

        tk.Label(status_label_container, text="状态:", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_TERTIARY, fg=AppleColors.TEXT_SECONDARY).pack(side='left', padx=(self.scale(8), self.scale(4)))

        self.status_label = tk.Label(status_label_container, text="未连接",
                                     font=("SF Pro Display", self.scale(10), "bold"),
                                     bg=AppleColors.BG_TERTIARY, fg=AppleColors.ERROR)
        self.status_label.pack(side='left', padx=(0, self.scale(8)))

    def create_digit_card(self, parent):
        """创建数码管控制卡片（带滚动条）"""
        card = self.create_scrollable_card(parent, height=self.scale(200), inner_height=self.scale(380))

        # 标题
        tk.Label(card, text="数码管控制", font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(10)))

        content = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content.pack(fill='both', expand=True, padx=self.scale(24), pady=(0, self.scale(20)))

        # 显示区域 - 液体玻璃Canvas
        canvas_height = self.scale(100)
        display = tk.Canvas(content, height=canvas_height, bg=AppleColors.BG_SECONDARY, highlightthickness=0)
        display.pack(fill='x', pady=(0, self.scale(16)))
        self.digit_display_canvas = display  # 保存引用

        # 强制更新以获取实际宽度
        display.update_idletasks()
        canvas_width = display.winfo_width()
        if canvas_width < 100:  # 如果还没有布局完成，使用默认值
            canvas_width = 800

        # 绘制圆角矩形背景 - 带渐变效果
        display.create_rounded_rect = lambda x1, y1, x2, y2, r, **kwargs: display.create_polygon([
            x1+r, y1, x2-r, y1, x2, y1, x2, y1+r, x2, y2-r, x2, y2,
            x2-r, y2, x1+r, y2, x1, y2, x1, y2-r, x1, y1+r, x1, y1
        ], smooth=True, **kwargs)

        # 绘制玻璃质感渐变背景（从上到下）
        for i in range(canvas_height):
            progress = i / canvas_height
            # 从浅蓝色渐变到更浅的蓝色
            r = int(245 + (253-245)*progress)
            g = int(248 + (253-248)*progress)
            b = int(255)
            color = f"#{r:02x}{g:02x}{b:02x}"
            display.create_line(0, i, canvas_width, i, fill=color, width=1)

        # 叠加圆角边框
        display.create_rounded_rect(0, 0, canvas_width, canvas_height, self.scale(16),
                                   fill="", outline=AppleColors.BORDER, width=2)

        display.create_text(canvas_width//2, self.scale(20), text="当前数值",
                          font=("SF Pro Display", self.scale(12)),
                          fill=AppleColors.TEXT_SECONDARY)

        self.digit_display_obj = display.create_text(canvas_width//2, self.scale(60), text="0",
                                                     font=("SF Pro Display", self.scale(48), "bold"),
                                                     fill=AppleColors.PRIMARY)

        # 范围提示
        tk.Label(content, text="范围: -900 到 +900", font=("SF Pro Display", self.scale(11)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_TERTIARY).pack(pady=(0, self.scale(12)))

        # 滑块
        self.digit_scale = tk.Scale(content, from_=-900, to=900, orient='horizontal',
                                    bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY,
                                    troughcolor=AppleColors.BG_TERTIARY,
                                    activebackground=AppleColors.PRIMARY,
                                    highlightthickness=0, font=("SF Pro Display", self.scale(10)),
                                    command=self.on_digit_change, length=self.scale(400), sliderlength=self.scale(30))
        self.digit_scale.set(0)
        self.digit_scale.pack(fill='x', pady=(0, self.scale(16)))

        # 快捷按钮
        btn_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY)
        btn_frame.pack(pady=(0, self.scale(16)))

        AppleButton(btn_frame, "-10", lambda: self.adjust_digit(-10),
                  width=self.scale(70), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(3))
        AppleButton(btn_frame, "-1", lambda: self.adjust_digit(-1),
                  width=self.scale(70), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(3))
        AppleButton(btn_frame, "归零", lambda: self.set_digit(0),
                  width=self.scale(70), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(3))
        AppleButton(btn_frame, "+1", lambda: self.adjust_digit(1),
                  width=self.scale(70), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(3))
        AppleButton(btn_frame, "+10", lambda: self.adjust_digit(10),
                  width=self.scale(70), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(3))

        # 发送按钮
        AppleButton(content, "发送数码管数据", self.send_digit_data,
                  width=self.scale(380), height=self.scale(40), style="primary").pack()

    def create_led_card(self, parent):
        """创建LED控制卡片（带滚动条）"""
        card = self.create_scrollable_card(parent, height=self.scale(200), inner_height=self.scale(350))

        # 标题
        tk.Label(card, text="LED 控制", font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(10)))

        content = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content.pack(fill='both', expand=True, padx=self.scale(24), pady=(0, self.scale(20)))

        # LED显示区域 - 液体玻璃Canvas
        canvas_height = self.scale(100)
        led_canvas = tk.Canvas(content, height=canvas_height, bg=AppleColors.BG_SECONDARY, highlightthickness=0)
        led_canvas.pack(fill='x', pady=(0, self.scale(16)))

        # 强制更新以获取实际宽度
        led_canvas.update_idletasks()
        canvas_width = led_canvas.winfo_width()
        if canvas_width < 100:  # 如果还没有布局完成，使用默认值
            canvas_width = 800

        # 绘制圆角矩形背景函数
        led_canvas.create_rounded_rect = lambda x1, y1, x2, y2, r, **kwargs: led_canvas.create_polygon([
            x1+r, y1, x2-r, y1, x2, y1, x2, y1+r, x2, y2-r, x2, y2,
            x2-r, y2, x1+r, y2, x1, y2, x1, y2-r, x1, y1+r, x1, y1
        ], smooth=True, **kwargs)

        # 绘制玻璃质感渐变背景（粉色调）
        for i in range(canvas_height):
            progress = i / canvas_height
            # 从浅粉色渐变到更浅的粉色
            r = int(255)
            g = int(245 + (253-245)*progress)
            b = int(248 + (253-248)*progress)
            color = f"#{r:02x}{g:02x}{b:02x}"
            led_canvas.create_line(0, i, canvas_width, i, fill=color, width=1)

        # 叠加圆角边框
        led_canvas.create_rounded_rect(0, 0, canvas_width, canvas_height, self.scale(16),
                                      fill="", outline=AppleColors.BORDER, width=2)

        self.led_canvas = led_canvas
        self.led_circles = []
        self.led_vars = []

        # 计算LED间距，使其居中显示
        led_spacing = canvas_width / 5  # 4个LED，5个间隔
        for i in range(4):
            var = tk.IntVar(value=0)
            self.led_vars.append(var)

            x = int(led_spacing * (i + 1))

            # LED发光外圈（毛玻璃效果）
            glow = led_canvas.create_oval(x-self.scale(24), self.scale(28), x+self.scale(24), self.scale(76),
                                         fill=AppleColors.GLASS_BORDER, outline="", width=0)

            # LED圆形指示灯
            circle = led_canvas.create_oval(x-self.scale(20), self.scale(32), x+self.scale(20), self.scale(72),
                                           fill=AppleColors.SEPARATOR, outline="", width=0)
            self.led_circles.append(circle)

            # 标签
            led_canvas.create_text(x, self.scale(15), text=f"LED {i}",
                                  fill=AppleColors.TEXT_SECONDARY,
                                  font=("SF Pro Display", self.scale(11)))

        # 开关控制
        tk.Label(content, text="开关控制", font=("SF Pro Display", self.scale(12)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(pady=(0, self.scale(12)))

        switch_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY)
        switch_frame.pack(pady=(0, self.scale(16)))

        for i in range(4):
            cb = tk.Checkbutton(switch_frame, text=f"LED {i}",
                               variable=self.led_vars[i],
                               command=self.update_led_value,
                               bg=AppleColors.BG_SECONDARY,
                               fg=AppleColors.TEXT_PRIMARY,
                               selectcolor=AppleColors.BG_TERTIARY,
                               font=("SF Pro Display", self.scale(11)),
                               activebackground=AppleColors.BG_SECONDARY)
            cb.pack(side='left', padx=self.scale(12))

        # 快捷按钮
        btn_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY)
        btn_frame.pack(pady=(0, self.scale(16)))

        AppleButton(btn_frame, "全部打开", self.set_all_leds_on,
                  width=self.scale(120), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(6))
        AppleButton(btn_frame, "全部关闭", self.set_all_leds_off,
                  width=self.scale(120), height=self.scale(34), style="secondary").pack(side='left', padx=self.scale(6))

        # 发送按钮
        AppleButton(content, "发送 LED 数据", self.send_led_data,
                  width=self.scale(380), height=self.scale(40), style="primary").pack()

    def create_receive_card(self, parent):
        """创建接收数据卡片"""
        card = self.create_card(parent, height=self.scale(120))

        # 标题
        tk.Label(card, text="接收数据", font=("SF Pro Display", self.scale(20), "bold"),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(24), pady=(self.scale(20), self.scale(12)))

        content = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content.pack(fill='x', padx=self.scale(24), pady=(0, self.scale(20)))

        # 接收显示区域 - 液体玻璃Canvas
        canvas_height = self.scale(60)
        rx_canvas = tk.Canvas(content, height=canvas_height, bg=AppleColors.BG_SECONDARY, highlightthickness=0)
        rx_canvas.pack(fill='x')
        self.rx_canvas = rx_canvas  # 保存引用

        # 强制更新以获取实际宽度
        rx_canvas.update_idletasks()
        canvas_width = rx_canvas.winfo_width()
        if canvas_width < 100:  # 如果还没有布局完成，使用默认值
            canvas_width = 800

        # 绘制圆角矩形背景函数
        rx_canvas.create_rounded_rect = lambda x1, y1, x2, y2, r, **kwargs: rx_canvas.create_polygon([
            x1+r, y1, x2-r, y1, x2, y1, x2, y1+r, x2, y2-r, x2, y2,
            x2-r, y2, x1+r, y2, x1, y2, x1, y2-r, x1, y1+r, x1, y1
        ], smooth=True, **kwargs)

        # 计算两个数据框的位置和大小
        box_width = (canvas_width - self.scale(30)) // 2  # 两个框，中间留间隙
        box1_x = self.scale(10)
        box2_x = box1_x + box_width + self.scale(10)

        # LED状态框 - 带渐变
        for i in range(canvas_height):
            progress = i / canvas_height
            r = int(248 + (253-248)*progress)
            g = int(250 + (253-250)*progress)
            b = int(252 + (255-252)*progress)
            color = f"#{r:02x}{g:02x}{b:02x}"
            rx_canvas.create_line(box1_x, i, box1_x + box_width, i, fill=color, width=1)

        rx_canvas.create_rounded_rect(box1_x, 0, box1_x + box_width, canvas_height, self.scale(14),
                                     fill="", outline=AppleColors.BORDER, width=2)
        rx_canvas.create_text(box1_x + box_width//2, self.scale(15), text="LED 状态 [63:60]",
                            font=("SF Pro Display", self.scale(10)),
                            fill=AppleColors.TEXT_SECONDARY)
        self.rx_led_text = rx_canvas.create_text(box1_x + box_width//2, self.scale(40), text="0x0",
                                                 font=("SF Pro Display", self.scale(18), "bold"),
                                                 fill=AppleColors.TEXT_PRIMARY)

        # 数码管数据框 - 带渐变
        for i in range(canvas_height):
            progress = i / canvas_height
            r = int(248 + (253-248)*progress)
            g = int(250 + (253-250)*progress)
            b = int(252 + (255-252)*progress)
            color = f"#{r:02x}{g:02x}{b:02x}"
            rx_canvas.create_line(box2_x, i, box2_x + box_width, i, fill=color, width=1)

        rx_canvas.create_rounded_rect(box2_x, 0, box2_x + box_width, canvas_height, self.scale(14),
                                     fill="", outline=AppleColors.BORDER, width=2)
        rx_canvas.create_text(box2_x + box_width//2, self.scale(15), text="数码管数据 [55:40]",
                            font=("SF Pro Display", self.scale(10)),
                            fill=AppleColors.TEXT_SECONDARY)
        self.rx_digit_text = rx_canvas.create_text(box2_x + box_width//2, self.scale(40), text="0x0000",
                                                   font=("SF Pro Display", self.scale(18), "bold"),
                                                   fill=AppleColors.TEXT_PRIMARY)

    def create_log_card(self, parent):
        """创建日志卡片"""
        card = self.create_card(parent)

        # 标题栏
        header = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        header.pack(fill='x', padx=self.scale(24), pady=(self.scale(20), self.scale(12)))

        tk.Label(header, text="通信日志", font=("SF Pro Display", self.scale(20), "bold"),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY).pack(side='left')

        AppleButton(header, "清空日志", self.clear_log,
                  width=self.scale(100), height=self.scale(32), style="secondary").pack(side='right')

        # 日志文本
        log_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        log_frame.pack(fill='both', expand=True, padx=self.scale(24), pady=(0, self.scale(20)))

        self.log_text = scrolledtext.ScrolledText(log_frame, height=10, wrap=tk.WORD,
                                                  bg=AppleColors.BG_TERTIARY,
                                                  fg=AppleColors.TEXT_PRIMARY,
                                                  font=("SF Mono", self.scale(10)), relief='flat',
                                                  borderwidth=0,
                                                  insertbackground=AppleColors.PRIMARY)
        self.log_text.pack(fill='both', expand=True)

        # 配置标签
        self.log_text.tag_config("success", foreground=AppleColors.SUCCESS)
        self.log_text.tag_config("error", foreground=AppleColors.ERROR)
        self.log_text.tag_config("info", foreground=AppleColors.INFO)
        self.log_text.tag_config("warning", foreground=AppleColors.WARNING)

    # ========== 功能方法 ==========

    def send_control_command(self, command_byte, description=""):
        """发送控制命令到192.168.240.1:2222"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.sendto(bytes([command_byte]), ("192.168.240.1", 2222))
            sock.close()
            if description:
                self.log(f"已发送控制命令: {description} (0x{command_byte:02X}) → 192.168.240.1:2222", "info")
        except Exception as e:
            self.log(f"发送控制命令失败: {e}", "error")

    def log(self, message, tag="info"):
        """添加日志"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_msg = f"[{timestamp}] {message}\n"
        self.log_text.insert(tk.END, log_msg, tag)
        self.log_text.see(tk.END)

    def clear_log(self):
        """清空日志"""
        self.log_text.delete(1.0, tk.END)
        self.log("日志已清空", "info")

    def toggle_connection(self):
        if not self.is_connected:
            self.connect()
        else:
            self.disconnect()

    def connect(self):
        try:
            self.local_ip = self.local_ip_entry.get()
            self.local_port = int(self.local_port_entry.get())
            self.target_ip = self.target_ip_entry.get()
            self.target_port = int(self.target_port_entry.get())

            self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp_socket.bind((self.local_ip, self.local_port))
            self.udp_socket.settimeout(0.1)

            self.is_connected = True
            self.running = True

            self.receive_thread = threading.Thread(target=self.receive_data, daemon=True)
            self.receive_thread.start()

            self.status_label.config(text="已连接", fg=AppleColors.SUCCESS)

            # 更新按钮
            canvas = self.connect_btn
            canvas.bg_color = AppleColors.ERROR
            canvas.hover_color = canvas.adjust_brightness(AppleColors.ERROR, -0.1)
            canvas.active_color = canvas.adjust_brightness(AppleColors.ERROR, -0.2)
            canvas.itemconfig(canvas.btn_rect, fill=AppleColors.ERROR)
            canvas.itemconfig(canvas.text_id, text="断开")

            self.log(f"成功连接到 {self.local_ip}:{self.local_port}", "success")

            for entry in [self.local_ip_entry, self.local_port_entry,
                         self.target_ip_entry, self.target_port_entry]:
                entry.config(state="disabled")

        except Exception as e:
            self.log(f"连接失败: {e}", "error")
            if self.udp_socket:
                self.udp_socket.close()
                self.udp_socket = None

    def disconnect(self):
        self.running = False
        self.is_connected = False

        if self.udp_socket:
            self.udp_socket.close()
            self.udp_socket = None

        self.status_label.config(text="未连接", fg=AppleColors.ERROR)

        canvas = self.connect_btn
        canvas.bg_color = AppleColors.SUCCESS
        canvas.hover_color = canvas.adjust_brightness(AppleColors.SUCCESS, -0.1)
        canvas.active_color = canvas.adjust_brightness(AppleColors.SUCCESS, -0.2)
        canvas.itemconfig(canvas.btn_rect, fill=AppleColors.SUCCESS)
        canvas.itemconfig(canvas.text_id, text="连接")

        self.log("已断开连接", "warning")

        for entry in [self.local_ip_entry, self.local_port_entry,
                     self.target_ip_entry, self.target_port_entry]:
            entry.config(state="normal")

    def on_digit_change(self, value):
        self.digit_value = int(float(value))
        # 只显示百位数字（0-9）
        hundreds_digit = abs(self.digit_value) // 100
        display_text = str(hundreds_digit)
        # 更新Canvas文本对象
        self.digit_display_canvas.itemconfig(self.digit_display_obj, text=display_text)

    def adjust_digit(self, delta):
        new_value = max(-900, min(900, self.digit_value + delta))
        self.set_digit(new_value)

    def set_digit(self, value):
        self.digit_value = value
        self.digit_scale.set(value)
        # 只显示百位数字（0-9）
        hundreds_digit = abs(value) // 100
        display_text = str(hundreds_digit)
        # 更新Canvas文本对象
        self.digit_display_canvas.itemconfig(self.digit_display_obj, text=display_text)

    def update_led_value(self):
        """
        更新LED状态值
        使用反向映射（参考apple_control_panel.py）:
        LED0 → bit 3, LED1 → bit 2, LED2 → bit 1, LED3 → bit 0
        这样便于肉眼观察，GUI上的LED顺序与硬件板子顺序一致
        """
        self.led_value = 0
        for i, var in enumerate(self.led_vars):
            if var.get():
                # 反向映射: LED0→bit3, LED1→bit2, LED2→bit1, LED3→bit0
                self.led_value |= (1 << (3 - i))

        # 更新LED显示（使用反向映射）
        for i in range(4):
            if self.led_value & (1 << (3 - i)):
                # LED亮起 - 系统蓝
                self.led_canvas.itemconfig(self.led_circles[i], fill=AppleColors.PRIMARY)
            else:
                # LED熄灭 - 浅灰
                self.led_canvas.itemconfig(self.led_circles[i], fill=AppleColors.SEPARATOR)

    def set_all_leds_on(self):
        for var in self.led_vars:
            var.set(1)
        self.update_led_value()

    def set_all_leds_off(self):
        for var in self.led_vars:
            var.set(0)
        self.update_led_value()

    @staticmethod
    def seg_decoder(bin_data):
        """
        七段数码管译码器（基于FPHA.pdf第14-16页）
        硬件：共阳极数码管，active-low编码（0=亮，1=灭）
        输入: 4位二进制数据 (0-15)
        输出: 8位七段码 [dp g f e d c b a]

        管脚对应（FPHA.pdf第16页）:
        DIG0=a, DIG1=b, DIG2=c, DIG3=d, DIG4=e, DIG5=f, DIG6=g, DIG7=dp

        七段显示格式（参考FPHA.pdf第14页）:
             aaa
           f     b
             ggg
           e     c
             ddd
              (dp)

        编码: 0=点亮该段, 1=熄灭该段
        注意: dp段（小数点）通常设为1（熄灭），除非需要显示小数点
        """
        seg_table = {
            # 数字0-9（共阳极，active-low）[dp g f e d c b a]
            0x0: 0b11000000,  # 0 - 显示 ⌈‾⌉|_|
            0x1: 0b11111001,  # 1 - 显示   |  |
            0x2: 0b10100100,  # 2 - 显示 ⌈‾⌉_|‾
            0x3: 0b10110000,  # 3 - 显示 ⌈‾⌉‾|‾
            0x4: 0b10011001,  # 4 - 显示  |‾| |
            0x5: 0b10010010,  # 5 - 显示 ⌈‾|‾‾|‾
            0x6: 0b10000010,  # 6 - 显示 ⌈‾|‾|_|
            0x7: 0b11111000,  # 7 - 显示 ⌈‾⌉ |
            0x8: 0b10000000,  # 8 - 显示 ⌈‾⌉|‾||_|（全亮）
            0x9: 0b10010000,  # 9 - 显示 ⌈‾⌉|‾| |

            # 字母A-F
            0xA: 0b10001000,  # A - 显示 ⌈‾⌉|‾|| |
            0xB: 0b10000011,  # b - 显示  |_||_|
            0xC: 0b11000110,  # C - 显示 ⌈‾  |_
            0xD: 0b10100001,  # d - 显示   | |‾|_|
            0xE: 0b10000110,  # E - 显示 ⌈‾|‾|_

            # 特殊符号
            0xF: 0b10111111,  # 负号"-" - 只点亮g段（中间横杠）
        }
        # 默认全灭（空白）
        return seg_table.get(bin_data & 0xF, 0b11111111)

    def send_digit_data(self):
        """
        发送数码管译码数据到FPGA（参考apple_control_panel.py格式）
        使用8字节简化格式，合并LED和数码管控制
        """
        if not self.is_connected:
            self.log("错误: 未连接", "error")
            return

        try:
            value = int(self.digit_value)
            # 限制范围在-900到+900
            value = max(-900, min(900, value))

            # === 数值分解逻辑 ===
            is_negative = (value < 0)
            abs_value = abs(value)

            # 分解位数
            digit_hundreds = abs_value // 100
            digit_tens = (abs_value % 100) // 10
            digit_ones = abs_value % 10

            # === 七段译码 ===
            seg_code_ones = self.seg_decoder(digit_ones)
            seg_code_tens = self.seg_decoder(digit_tens)
            seg_code_hundreds = self.seg_decoder(digit_hundreds)
            seg_code_sign = self.seg_decoder(0xF if is_negative else 0xA)

            # === 合并为16位编码（参考apple_control_panel.py） ===
            # 4个七段码合并: [符号][百位][十位][个位]
            # 但我们需要将其打包为16位值
            # 方案: 使用低16位存储前两个数码管(符号+百位为高8位，十位+个位为低8位)
            encoded = (seg_code_sign << 24) | (seg_code_hundreds << 16) | (seg_code_tens << 8) | seg_code_ones

            # === LED状态获取 ===
            led_mask = self.led_value & 0x0F

            # === 8字节数据包格式（参考apple_control_panel.py） ===
            # Byte 0: LED mask (高4位) + 数码管位数 (低4位)
            # Byte 1: 编码高8位 (符号位七段码)
            # Byte 2: 编码次高8位 (百位七段码)
            # Byte 3: 编码次低8位 (十位七段码)
            # Byte 4: 编码低8位 (个位七段码)
            # Byte 5-7: 保留
            digits = 4  # 固定4位数码管
            packet = bytearray(8)
            packet[0] = ((led_mask & 0x0F) << 4) | (digits & 0x0F)
            packet[1] = seg_code_sign
            packet[2] = seg_code_hundreds
            packet[3] = seg_code_tens
            packet[4] = seg_code_ones
            # packet[5:7] 自动为0x00

            self.udp_socket.sendto(packet, (self.target_ip, self.target_port))

            # 日志输出
            sign_str = "-" if is_negative else "+"
            self.log(f"已发送LED+数码管数据: LED=0x{led_mask:X}, 数码管={sign_str}{abs_value} → 七段码=[0x{seg_code_sign:02X}, 0x{seg_code_hundreds:02X}, 0x{seg_code_tens:02X}, 0x{seg_code_ones:02X}]", "success")

        except Exception as e:
            self.log(f"发送失败: {e}", "error")

    def send_led_data(self):
        """
        发送LED数据到FPGA（参考apple_control_panel.py格式）
        使用8字节简化格式，同时包含当前数码管状态
        """
        if not self.is_connected:
            self.log("错误: 未连接", "error")
            return

        try:
            # LED值只使用低4位
            led_mask = self.led_value & 0x0F

            # 获取当前数码管值并译码
            value = int(self.digit_value)
            value = max(-100, min(100, value))

            is_negative = (value < 0)
            abs_value = abs(value)

            digit_hundreds = 1 if abs_value >= 100 else 0
            digit_tens = (abs_value % 100) // 10
            digit_ones = abs_value % 10

            seg_code_ones = self.seg_decoder(digit_ones)
            seg_code_tens = self.seg_decoder(digit_tens)
            seg_code_hundreds = self.seg_decoder(digit_hundreds)
            seg_code_sign = self.seg_decoder(0xF if is_negative else 0xA)

            # === 8字节数据包格式（参考apple_control_panel.py） ===
            digits = 4  # 固定4位数码管
            packet = bytearray(8)
            packet[0] = ((led_mask & 0x0F) << 4) | (digits & 0x0F)
            packet[1] = seg_code_sign
            packet[2] = seg_code_hundreds
            packet[3] = seg_code_tens
            packet[4] = seg_code_ones
            # packet[5:7] 自动为0x00

            self.udp_socket.sendto(packet, (self.target_ip, self.target_port))
            self.log(f"已发送LED数据: 值=0x{led_mask:X} (LED3={bool(led_mask&8)} LED2={bool(led_mask&4)} LED1={bool(led_mask&2)} LED0={bool(led_mask&1)})", "success")

        except Exception as e:
            self.log(f"发送失败: {e}", "error")

    def receive_data(self):
        while self.running:
            try:
                data, addr = self.udp_socket.recvfrom(1024)
                if data:
                    self.process_received_data(data, addr)
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self.log(f"接收错误: {e}", "error")
                break

    def process_received_data(self, data, addr):
        try:
            if len(data) >= 8:
                led_status = (data[0] >> 4) & 0x0F
                digit_data = (data[1] << 8) | data[2]

                self.root.after(0, self.update_receive_display, led_status, digit_data)
                self.log(f"接收: LED=0x{led_status:X}, 数码管=0x{digit_data:04X}, 来源={addr[0]}", "info")
        except Exception as e:
            self.log(f"数据处理错误: {e}", "error")

    def update_receive_display(self, led_status, digit_data):
        self.rx_canvas.itemconfig(self.rx_led_text, text=f"0x{led_status:X}")
        self.rx_canvas.itemconfig(self.rx_digit_text, text=f"0x{digit_data:04X}")

    # ========== 串口功能方法 ==========

    def refresh_serial_ports(self):
        """刷新可用串口列表"""
        try:
            ports = serial.tools.list_ports.comports()
            port_list = [port.device for port in ports]

            if port_list:
                self.serial_port_combo['values'] = port_list
                self.serial_port_combo.set(port_list[0])
            else:
                self.serial_port_combo['values'] = ['无可用串口']
                self.serial_port_combo.set('无可用串口')

        except Exception as e:
            self.log(f"刷新串口列表失败: {e}", "error")
            self.serial_port_combo['values'] = ['刷新失败']
            self.serial_port_combo.set('刷新失败')

    def toggle_serial_connection(self):
        """切换串口连接状态"""
        if not self.serial_connected:
            self.connect_serial()
        else:
            self.disconnect_serial()

    def connect_serial(self):
        """连接串口"""
        try:
            port = self.serial_port_combo.get()
            baud = int(self.serial_baud_combo.get())

            if port == '无可用串口' or port == '刷新失败':
                self.log("请先选择有效的串口", "error")
                return

            # 创建串口连接
            self.serial_port = serial.Serial(
                port=port,
                baudrate=baud,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1
            )

            self.serial_connected = True

            # 更新UI
            self.serial_status_label.config(text="已连接", fg=AppleColors.SUCCESS)

            canvas = self.serial_connect_btn
            canvas.bg_color = AppleColors.ERROR
            canvas.hover_color = canvas.adjust_brightness(AppleColors.ERROR, -0.1)
            canvas.active_color = canvas.adjust_brightness(AppleColors.ERROR, -0.2)
            canvas.itemconfig(canvas.btn_rect, fill=AppleColors.ERROR)
            canvas.itemconfig(canvas.text_id, text="断开")

            # 禁用配置控件
            self.serial_port_combo.config(state='disabled')
            self.serial_baud_combo.config(state='disabled')

            self.log(f"串口已连接: {port}, 波特率: {baud}", "success")

        except Exception as e:
            self.log(f"串口连接失败: {e}", "error")
            if self.serial_port:
                try:
                    self.serial_port.close()
                except:
                    pass
                self.serial_port = None

    def disconnect_serial(self):
        """断开串口连接"""
        try:
            if self.serial_port:
                self.serial_port.close()
                self.serial_port = None

            self.serial_connected = False

            # 更新UI
            self.serial_status_label.config(text="未连接", fg=AppleColors.ERROR)

            canvas = self.serial_connect_btn
            canvas.bg_color = AppleColors.SUCCESS
            canvas.hover_color = canvas.adjust_brightness(AppleColors.SUCCESS, -0.1)
            canvas.active_color = canvas.adjust_brightness(AppleColors.SUCCESS, -0.2)
            canvas.itemconfig(canvas.btn_rect, fill=AppleColors.SUCCESS)
            canvas.itemconfig(canvas.text_id, text="连接")

            # 启用配置控件
            self.serial_port_combo.config(state='readonly')
            self.serial_baud_combo.config(state='readonly')

            self.log("串口已断开", "warning")

        except Exception as e:
            self.log(f"断开串口失败: {e}", "error")

    def send_serial_command(self, cmd_id):
        """
        发送串口命令
        cmd_id: 1-4 = 基础1-4问 (0x01-0x04)
        cmd_id: 5-8 = 拓展1-4问 (0x05-0x08)
        """
        if not self.serial_connected or not self.serial_port:
            self.log("错误: 串口未连接", "error")
            return

        try:
            # 构造命令字节
            cmd_byte = bytes([cmd_id])

            # 发送命令
            self.serial_port.write(cmd_byte)

            # 日志输出
            if cmd_id <= 4:
                self.log(f"已发送串口命令: 基础{cmd_id}问 (0x{cmd_id:02X})", "success")
            else:
                self.log(f"已发送串口命令: 拓展{cmd_id-4}问 (0x{cmd_id:02X})", "success")

        except Exception as e:
            self.log(f"串口发送失败: {e}", "error")

    def create_image_send_advanced_tab(self):
        """创建图片发送升级版标签页（带帧同步和性能优化）"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='图片发送升级版')

        # 初始化高级发送线程和数据
        self.adv_send_thread = None
        self.adv_image_data = None
        self.adv_image_pil = None
        self.adv_send_running = False

        # 统计信息
        self.adv_stats = {
            'sent_frames': 0,
            'sent_bytes': 0,
            'start_time': 0
        }

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 图片预览（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_adv_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：图片预览区域
        preview_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        preview_frame.pack(side='right', fill='both', expand=True)

        self.create_adv_preview(preview_frame)

        # 下部：统计信息
        self.create_adv_stats(content)

    def create_extended_receive_tab(self):
        """创建拓展2标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='拓展2')

        # 初始化视频接收线程
        self.ext_video_thread = None
        self.ext_video_start_time = None
        self.ext_current_frame = None

        # 图像处理模式状态
        self.ext_processing_mode = None  # None, 'sobel', 'otsu'

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 视频显示（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_ext_video_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：视频显示区域
        video_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        video_frame.pack(side='right', fill='both', expand=True)

        self.create_ext_video_display(video_frame)

        # 下部：统计信息
        # self.create_ext_video_stats(content)

    def create_ext_video_control_panel(self, parent):
        """创建拓展接收控制面板"""
        # 固定宽度的控制面板
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(280))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="视频控制",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 视频配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(0, self.scale(8)))

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # IP地址
        tk.Label(config_frame, text="接收IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.ext_video_ip_entry = tk.Entry(config_frame, **entry_style)
        self.ext_video_ip_entry.insert(0, "192.168.240.2")
        self.ext_video_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.ext_video_port_entry = tk.Entry(config_frame, **entry_style)
        self.ext_video_port_entry.insert(0, "2")
        self.ext_video_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 分辨率
        tk.Label(config_frame, text="分辨率",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        res_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        res_frame.pack(fill='x', pady=(0, self.scale(6)))

        width_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        width_frame.pack(side='left', fill='x', expand=True, padx=(0, self.scale(3)))

        self.ext_video_width_entry = tk.Entry(width_frame, **entry_style)
        self.ext_video_width_entry.insert(0, "640")
        self.ext_video_width_entry.pack(fill='x', ipady=self.scale(5))

        tk.Label(res_frame, text="×",
                font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(side='left', padx=self.scale(2))

        height_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        height_frame.pack(side='left', fill='x', expand=True, padx=(self.scale(3), 0))

        self.ext_video_height_entry = tk.Entry(height_frame, **entry_style)
        self.ext_video_height_entry.insert(0, "480")
        self.ext_video_height_entry.pack(fill='x', ipady=self.scale(5))

        # 超时设置
        tk.Label(config_frame, text="超时(秒)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.ext_video_timeout_entry = tk.Entry(config_frame, **entry_style)
        self.ext_video_timeout_entry.insert(0, "2")
        self.ext_video_timeout_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(8)))

        # 控制按钮
        self.ext_video_start_btn = AppleButton(content_frame, "开始接收", self.start_ext_video,
                                          width=self.scale(240), height=self.scale(32), style="success")
        self.ext_video_start_btn.pack(pady=(0, self.scale(5)))

        self.ext_video_stop_btn = AppleButton(content_frame, "停止接收", self.stop_ext_video,
                                         width=self.scale(240), height=self.scale(32), style="danger")
        self.ext_video_stop_btn.pack(pady=(0, self.scale(5)))

        # 快速重置按钮（新增）
        self.ext_video_reset_btn = AppleButton(content_frame, "快速重置", self.quick_reset_ext_video,
                                         width=self.scale(240), height=self.scale(32), style="warning")
        self.ext_video_reset_btn.pack(pady=(0, self.scale(5)))

        self.ext_video_save_btn = AppleButton(content_frame, "保存当前帧", self.save_ext_video_frame,
                                         width=self.scale(240), height=self.scale(32), style="secondary")
        self.ext_video_save_btn.pack(pady=(0, self.scale(5)))

        self.ext_video_clear_btn = AppleButton(content_frame, "清空统计", self.clear_ext_video_stats,
                                          width=self.scale(240), height=self.scale(32), style="secondary")
        self.ext_video_clear_btn.pack(pady=(0, self.scale(5)))

        # 图像处理按钮（新增）
        tk.Label(content_frame, text="图像处理模式", font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(self.scale(8), self.scale(4)))

        self.ext_sobel_btn = AppleButton(content_frame, "Sobel模式发送", self.ext_enable_sobel_mode,
                                         width=self.scale(240), height=self.scale(32), style="primary")
        self.ext_sobel_btn.pack(pady=(0, self.scale(5)))

        self.ext_otsu_btn = AppleButton(content_frame, "Otsu发送", self.ext_enable_otsu_mode,
                                        width=self.scale(240), height=self.scale(32), style="primary")
        self.ext_otsu_btn.pack(pady=(0, self.scale(5)))

        self.ext_reset_mode_btn = AppleButton(content_frame, "复位", self.ext_reset_processing_mode,
                                              width=self.scale(240), height=self.scale(32), style="warning")
        self.ext_reset_mode_btn.pack()

        return panel_frame

    def create_ext_video_display(self, parent):
        """创建拓展接收视频显示区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="视频预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 视频显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.ext_video_canvas = tk.Canvas(display_frame,
                                      width=self.scale(640),
                                      height=self.scale(480),
                                      bg=AppleColors.BG_TERTIARY,
                                      highlightthickness=1,
                                      highlightbackground=AppleColors.BORDER)
        self.ext_video_canvas.pack()

        # 默认提示文字
        self.ext_video_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待视频流...\n点击\"开始接收\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_ext_video_stats(self, parent):
        """创建拓展接收统计信息卡片（去除FPS显示）"""
        card = self.create_card(parent, height=self.scale(100))

        # 标题
        tk.Label(card, text="实时统计",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建两行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(5)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(5)
        }

        # 第一行
        self.ext_video_frames_label = tk.Label(row1, text="帧数: 0", **label_style)
        self.ext_video_frames_label.pack(side='left', padx=(0, self.scale(5)))

        self.ext_video_packets_label = tk.Label(row1, text="包数: 0", **label_style)
        self.ext_video_packets_label.pack(side='left')

        # 第二行
        self.ext_video_bytes_label = tk.Label(row2, text="数据量: 0 KB", **label_style)
        self.ext_video_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.ext_video_rate_label = tk.Label(row2, text="速率: 0 KB/s", **label_style)
        self.ext_video_rate_label.pack(side='left', padx=(0, self.scale(5)))

        self.ext_video_buffer_label = tk.Label(row2, text="缓冲: 0 KB", **label_style)
        self.ext_video_buffer_label.pack(side='left')

    def ext_video_callback(self, event_type, data):
        """拓展接收回调（在线程中调用）"""
        if event_type == 'frame':
            self.root.after(0, self.update_ext_video_frame, data)
        elif event_type == 'log':
            self.root.after(0, self.log, data, "info")
        elif event_type == 'error':
            self.root.after(0, self.log, data, "error")
        elif event_type == 'timeout':
            self.root.after(0, self.log, "警告: 接收超时", "warning")

    def update_ext_video_frame(self, img):
        """更新拓展接收视频帧显示（去除本地处理，由FPGA端处理）"""
        try:
            # 保存当前帧
            self.ext_current_frame = img

            # 已去除本地图像处理：
            # - 不再本地应用Sobel滤波
            # - 不再本地应用Otsu二值化
            # 改为通过UDP命令（0x22/0x23/0x24）让FPGA端进行处理

            # 转换numpy数组到PIL Image
            pil_img = Image.fromarray(img)

            # 调整大小以适应Canvas
            canvas_width = self.scale(640)
            canvas_height = self.scale(480)
            pil_img = pil_img.resize((canvas_width, canvas_height), Image.LANCZOS)

            # 转换为PhotoImage
            self.ext_video_photo = ImageTk.PhotoImage(pil_img)

            # 清除Canvas并显示图像
            self.ext_video_canvas.delete("all")
            self.ext_video_canvas.create_image(
                canvas_width//2, canvas_height//2,
                image=self.ext_video_photo,
                anchor='center'
            )

        except Exception as e:
            self.log(f"显示错误: {e}", "error")

    def update_ext_video_stats_display(self):
        """更新拓展接收统计信息显示"""
        if not hasattr(self, 'ext_video_frames_label'):
            return

        if self.ext_video_thread and self.ext_video_thread.running:
            stats = self.ext_video_thread.get_stats()

            self.ext_video_frames_label.config(text=f"帧数: {stats['frames']}")
            self.ext_video_packets_label.config(text=f"包数: {stats['packets']}")
            self.ext_video_bytes_label.config(text=f"数据量: {stats['bytes']/1024:.1f} KB")

            if self.ext_video_start_time:
                elapsed = time.time() - self.ext_video_start_time
                if elapsed > 0:
                    rate = stats['bytes'] / elapsed / 1024
                    self.ext_video_rate_label.config(text=f"速率: {rate:.1f} KB/s")

            self.ext_video_buffer_label.config(text=f"缓冲: {stats['buffer']/1024:.1f} KB")

            # 继续更新
            self.root.after(100, self.update_ext_video_stats_display)

    def start_ext_video(self):
        """开始拓展接收"""
        try:
            ip = self.ext_video_ip_entry.get()
            port = int(self.ext_video_port_entry.get())
            width = int(self.ext_video_width_entry.get())
            height = int(self.ext_video_height_entry.get())
            timeout = float(self.ext_video_timeout_entry.get())

            # 创建并启动线程
            self.ext_video_thread = VideoReceiverThread(self.ext_video_callback)
            self.ext_video_thread.set_config(ip, port, width, height, timeout)
            self.ext_video_thread.start()

            self.ext_video_start_time = time.time()

            # 更新按钮状态
            self.ext_video_ip_entry.config(state='disabled')
            self.ext_video_port_entry.config(state='disabled')
            self.ext_video_width_entry.config(state='disabled')
            self.ext_video_height_entry.config(state='disabled')
            self.ext_video_timeout_entry.config(state='disabled')

            self.log("拓展接收已启动", "success")

        except Exception as e:
            self.log(f"启动失败: {e}", "error")

    def stop_ext_video(self):
        """停止拓展接收"""
        if self.ext_video_thread and self.ext_video_thread.running:
            self.ext_video_thread.stop()
            self.ext_video_thread.join(timeout=2.0)

            # 恢复按钮状态
            self.ext_video_ip_entry.config(state='normal')
            self.ext_video_port_entry.config(state='normal')
            self.ext_video_width_entry.config(state='normal')
            self.ext_video_height_entry.config(state='normal')
            self.ext_video_timeout_entry.config(state='normal')

            self.log("拓展接收已停止", "warning")

    def quick_reset_ext_video(self):
        """快速重置：停止→清除缓冲→重新开始接收"""
        self.log("执行快速重置...", "info")

        # 第1步：停止接收线程
        if self.ext_video_thread and self.ext_video_thread.running:
            self.ext_video_thread.stop()
            self.ext_video_thread.join(timeout=1.0)  # 等待线程结束
            self.log("已停止接收", "info")

        # 第2步：清除线程对象（重要：防止复用已关闭socket的线程）
        self.ext_video_thread = None

        # 第3步：清除当前帧显示
        self.ext_current_frame = None
        self.ext_video_canvas.delete("all")
        self.ext_video_canvas.create_text(
            self.scale(320), self.scale(240),
            text="正在重启接收...",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

        # 第4步：恢复按钮状态（允许修改配置）
        self.ext_video_ip_entry.config(state='normal')
        self.ext_video_port_entry.config(state='normal')
        self.ext_video_width_entry.config(state='normal')
        self.ext_video_height_entry.config(state='normal')
        self.ext_video_timeout_entry.config(state='normal')

        # 第5步：立即重新开始接收（减少延迟到50ms）
        self.root.after(50, self.start_ext_video)

    def save_ext_video_frame(self):
        """保存拓展接收当前视频帧"""
        if self.ext_current_frame is None:
            self.log("没有可保存的视频帧", "warning")
            return

        try:
            # 使用文件对话框选择保存位置
            filename = filedialog.asksaveasfilename(
                defaultextension=".png",
                filetypes=[("PNG图片", "*.png"), ("JPEG图片", "*.jpg"), ("所有文件", "*.*")],
                initialfile=f"ext_frame_{int(time.time())}.png"
            )

            if filename:
                pil_img = Image.fromarray(self.ext_current_frame)
                pil_img.save(filename)
                self.log(f"已保存: {filename}", "success")

        except Exception as e:
            self.log(f"保存失败: {e}", "error")

    def clear_ext_video_stats(self):
        """清空拓展接收统计信息"""
        if self.ext_video_thread:
            self.ext_video_thread.packet_count = 0
            self.ext_video_thread.frame_count = 0
            self.ext_video_thread.total_bytes = 0
            self.ext_video_thread.fps_queue.clear()
            self.ext_video_thread.frame_buffer.clear()

            self.ext_video_start_time = time.time()

            self.log("统计信息已清空", "info")

    # ========== 图像处理方法（拓展2）- 已移除本地处理 ==========
    # 已删除apply_sobel_filter和apply_otsu_threshold方法
    # 图像处理现在由FPGA端完成，通过UDP命令控制（0x22/0x23/0x24）

    def ext_enable_sobel_mode(self):
        """启用Sobel边缘检测模式 - 发送0x22命令"""
        # 发送控制命令0x22到192.168.240.1:2222
        self.send_control_command(0x22, "Sobel模式")

        self.ext_processing_mode = 'sobel'
        self.log("已启用Sobel边缘检测模式 (命令: 0x22)", "success")

        # 更新按钮状态
        self.ext_sobel_btn.itemconfig(self.ext_sobel_btn.btn_rect, fill=AppleColors.SUCCESS)
        self.ext_otsu_btn.itemconfig(self.ext_otsu_btn.btn_rect, fill=AppleColors.PRIMARY)

    def ext_enable_otsu_mode(self):
        """启用Otsu二值化模式 - 发送0x23命令"""
        # 发送控制命令0x23到192.168.240.1:2222
        self.send_control_command(0x23, "Otsu模式")

        self.ext_processing_mode = 'otsu'
        self.log("已启用Otsu二值化模式 (命令: 0x23)", "info")

        # 更新按钮状态
        self.ext_sobel_btn.itemconfig(self.ext_sobel_btn.btn_rect, fill=AppleColors.PRIMARY)
        self.ext_otsu_btn.itemconfig(self.ext_otsu_btn.btn_rect, fill=AppleColors.SUCCESS)

    def ext_reset_processing_mode(self):
        """复位图像处理模式 - 发送0x24命令"""
        # 发送控制命令0x24到192.168.240.1:2222
        self.send_control_command(0x24, "复位模式")

        self.ext_processing_mode = None
        self.log("已复位图像处理模式 (命令: 0x24)", "warning")

        # 恢复按钮状态
        self.ext_sobel_btn.itemconfig(self.ext_sobel_btn.btn_rect, fill=AppleColors.PRIMARY)
        self.ext_otsu_btn.itemconfig(self.ext_otsu_btn.btn_rect, fill=AppleColors.PRIMARY)

    def create_extended3_receive_tab(self):
        """创建拓展3标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='拓展3')

        # 初始化视频接收线程
        self.ext3_video_thread = None
        self.ext3_video_start_time = None
        self.ext3_current_frame = None

        # 初始化串口接收线程（用于车牌识别）
        self.ext3_serial_thread = None

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 视频显示（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_ext3_video_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：视频显示区域
        video_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        video_frame.pack(side='right', fill='both', expand=True)

        self.create_ext3_video_display(video_frame)

        # 下部：串口数据显示
        self.create_ext3_serial_display(content)

    def create_ext3_video_control_panel(self, parent):
        """创建拓展3控制面板"""
        # 固定宽度的控制面板
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(280))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="视频控制",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 视频配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(0, self.scale(8)))

        # 输入框样式
        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # IP地址
        tk.Label(config_frame, text="接收IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.ext3_video_ip_entry = tk.Entry(config_frame, **entry_style)
        self.ext3_video_ip_entry.insert(0, "192.168.240.2")
        self.ext3_video_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.ext3_video_port_entry = tk.Entry(config_frame, **entry_style)
        self.ext3_video_port_entry.insert(0, "2")
        self.ext3_video_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 分辨率
        tk.Label(config_frame, text="分辨率",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        res_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        res_frame.pack(fill='x', pady=(0, self.scale(6)))

        width_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        width_frame.pack(side='left', fill='x', expand=True, padx=(0, self.scale(3)))

        self.ext3_video_width_entry = tk.Entry(width_frame, **entry_style)
        self.ext3_video_width_entry.insert(0, "640")
        self.ext3_video_width_entry.pack(fill='x', ipady=self.scale(5))

        tk.Label(res_frame, text="×",
                font=("SF Pro Display", self.scale(10)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(side='left', padx=self.scale(2))

        height_frame = tk.Frame(res_frame, bg=AppleColors.BG_SECONDARY)
        height_frame.pack(side='left', fill='x', expand=True, padx=(self.scale(3), 0))

        self.ext3_video_height_entry = tk.Entry(height_frame, **entry_style)
        self.ext3_video_height_entry.insert(0, "480")
        self.ext3_video_height_entry.pack(fill='x', ipady=self.scale(5))

        # 超时设置
        tk.Label(config_frame, text="超时(秒)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.ext3_video_timeout_entry = tk.Entry(config_frame, **entry_style)
        self.ext3_video_timeout_entry.insert(0, "2")
        self.ext3_video_timeout_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(8)))

        # 控制按钮
        self.ext3_video_start_btn = AppleButton(content_frame, "开始接收", self.start_ext3_video,
                                          width=self.scale(240), height=self.scale(32), style="success")
        self.ext3_video_start_btn.pack(pady=(0, self.scale(5)))

        self.ext3_video_stop_btn = AppleButton(content_frame, "停止接收", self.stop_ext3_video,
                                         width=self.scale(240), height=self.scale(32), style="danger")
        self.ext3_video_stop_btn.pack(pady=(0, self.scale(5)))

        # 快速重置按钮（新增）
        self.ext3_video_reset_btn = AppleButton(content_frame, "快速重置", self.quick_reset_ext3_video,
                                         width=self.scale(240), height=self.scale(32), style="warning")
        self.ext3_video_reset_btn.pack(pady=(0, self.scale(5)))

        self.ext3_video_save_btn = AppleButton(content_frame, "保存当前帧", self.save_ext3_video_frame,
                                         width=self.scale(240), height=self.scale(32), style="secondary")
        self.ext3_video_save_btn.pack(pady=(0, self.scale(5)))

        self.ext3_video_clear_btn = AppleButton(content_frame, "清空统计", self.clear_ext3_video_stats,
                                          width=self.scale(240), height=self.scale(32), style="secondary")
        self.ext3_video_clear_btn.pack(pady=(0, self.scale(5)))

        # 车牌识别按钮（新增）
        self.ext3_plate_recog_btn = AppleButton(content_frame, "车牌识别", self.start_ext3_plate_recognition,
                                          width=self.scale(240), height=self.scale(32), style="primary")
        self.ext3_plate_recog_btn.pack()

        return panel_frame

    def create_ext3_video_display(self, parent):
        """创建拓展3视频显示区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="视频预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 视频显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.ext3_video_canvas = tk.Canvas(display_frame,
                                      width=self.scale(640),
                                      height=self.scale(480),
                                      bg=AppleColors.BG_TERTIARY,
                                      highlightthickness=1,
                                      highlightbackground=AppleColors.BORDER)
        self.ext3_video_canvas.pack()

        # 默认提示文字
        self.ext3_video_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待视频流...\n点击\"开始接收\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_ext3_serial_display(self, parent):
        """创建拓展3串口数据显示卡片"""
        card = self.create_card(parent, height=self.scale(140))

        # 标题
        tk.Label(card, text="串口数据显示", font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY, fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        content = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        # === 左侧：串口数据显示区域（带滚动条） ===
        left_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY)
        left_frame.pack(side='left', fill='both', expand=True, padx=(0, self.scale(10)))

        # 创建滚动文本框
        self.ext3_serial_text = scrolledtext.ScrolledText(
            left_frame,
            height=4,  # 显示4行
            wrap=tk.WORD,
            bg=AppleColors.BG_TERTIARY,
            fg=AppleColors.TEXT_PRIMARY,
            font=("SF Mono", self.scale(10)),
            relief='solid',
            borderwidth=1,
            insertbackground=AppleColors.PRIMARY
        )
        self.ext3_serial_text.pack(fill='both', expand=True)

        # 插入初始提示文字
        self.ext3_serial_text.insert(tk.END, "等待数据...\n")
        self.ext3_serial_text.config(state='disabled')  # 设为只读

        # === 右侧：大号数字显示区域（固定宽度） ===
        right_frame = tk.Frame(content, bg=AppleColors.BG_SECONDARY, width=self.scale(200))
        right_frame.pack(side='right', fill='y')
        right_frame.pack_propagate(False)  # 禁止自动调整大小

        digit_canvas_height = self.scale(80)
        digit_canvas = tk.Canvas(right_frame,
                                width=self.scale(200),
                                height=digit_canvas_height,
                                bg=AppleColors.BG_SECONDARY,
                                highlightthickness=0)
        digit_canvas.pack(fill='both', expand=True)
        self.ext3_digit_canvas = digit_canvas  # 保存引用

        # 使用固定宽度
        digit_canvas_width = self.scale(200)

        # 绘制圆角矩形背景函数
        digit_canvas.create_rounded_rect = lambda x1, y1, x2, y2, r, **kwargs: digit_canvas.create_polygon([
            x1+r, y1, x2-r, y1, x2, y1, x2, y1+r, x2, y2-r, x2, y2,
            x2-r, y2, x1+r, y2, x1, y2, x1, y2-r, x1, y1+r, x1, y1
        ], smooth=True, **kwargs)

        # 绘制玻璃质感渐变背景（蓝色调）
        for i in range(digit_canvas_height):
            progress = i / digit_canvas_height
            r = int(240 + (250-240)*progress)
            g = int(245 + (252-245)*progress)
            b = int(255)
            color = f"#{r:02x}{g:02x}{b:02x}"
            digit_canvas.create_line(0, i, digit_canvas_width, i, fill=color, width=1)

        # 叠加圆角边框
        digit_canvas.create_rounded_rect(0, 0, digit_canvas_width, digit_canvas_height, self.scale(14),
                                        fill="", outline=AppleColors.BORDER, width=2)

        # 标签
        digit_canvas.create_text(digit_canvas_width//2, self.scale(18), text="当前识别数字",
                                font=("SF Pro Display", self.scale(11)),
                                fill=AppleColors.TEXT_SECONDARY)

        # 大号数字显示（超大字体）
        self.ext3_digit_text = digit_canvas.create_text(digit_canvas_width//2, self.scale(50), text="-",
                                                        font=("SF Pro Display", self.scale(36), "bold"),
                                                        fill=AppleColors.PRIMARY)

    def create_ext3_video_stats(self, parent):
        """创建拓展3统计信息卡片（去除FPS显示）"""
        card = self.create_card(parent, height=self.scale(100))

        # 标题
        tk.Label(card, text="实时统计",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建两行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(5)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(5)
        }

        # 第一行
        self.ext3_video_frames_label = tk.Label(row1, text="帧数: 0", **label_style)
        self.ext3_video_frames_label.pack(side='left', padx=(0, self.scale(5)))

        self.ext3_video_packets_label = tk.Label(row1, text="包数: 0", **label_style)
        self.ext3_video_packets_label.pack(side='left')

        # 第二行
        self.ext3_video_bytes_label = tk.Label(row2, text="数据量: 0 KB", **label_style)
        self.ext3_video_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.ext3_video_rate_label = tk.Label(row2, text="速率: 0 KB/s", **label_style)
        self.ext3_video_rate_label.pack(side='left', padx=(0, self.scale(5)))

        self.ext3_video_buffer_label = tk.Label(row2, text="缓冲: 0 KB", **label_style)
        self.ext3_video_buffer_label.pack(side='left')

    def ext3_video_callback(self, event_type, data):
        """拓展3回调（在线程中调用）"""
        if event_type == 'frame':
            self.root.after(0, self.update_ext3_video_frame, data)
        elif event_type == 'log':
            self.root.after(0, self.log, data, "info")
        elif event_type == 'error':
            self.root.after(0, self.log, data, "error")
        elif event_type == 'timeout':
            self.root.after(0, self.log, "警告: 接收超时", "warning")

    def update_ext3_video_frame(self, img):
        """更新拓展3视频帧显示"""
        try:
            # 保存当前帧
            self.ext3_current_frame = img

            # 转换numpy数组到PIL Image
            pil_img = Image.fromarray(img)

            # 调整大小以适应Canvas
            canvas_width = self.scale(640)
            canvas_height = self.scale(480)
            pil_img = pil_img.resize((canvas_width, canvas_height), Image.LANCZOS)

            # 转换为PhotoImage
            self.ext3_video_photo = ImageTk.PhotoImage(pil_img)

            # 清除Canvas并显示图像
            self.ext3_video_canvas.delete("all")
            self.ext3_video_canvas.create_image(
                canvas_width//2, canvas_height//2,
                image=self.ext3_video_photo,
                anchor='center'
            )

        except Exception as e:
            self.log(f"显示错误: {e}", "error")

    def update_ext3_video_stats_display(self):
        """更新拓展3统计信息显示"""
        if not hasattr(self, 'ext3_video_frames_label'):
            return

        if self.ext3_video_thread and self.ext3_video_thread.running:
            stats = self.ext3_video_thread.get_stats()

            self.ext3_video_frames_label.config(text=f"帧数: {stats['frames']}")
            self.ext3_video_packets_label.config(text=f"包数: {stats['packets']}")
            self.ext3_video_bytes_label.config(text=f"数据量: {stats['bytes']/1024:.1f} KB")

            if self.ext3_video_start_time:
                elapsed = time.time() - self.ext3_video_start_time
                if elapsed > 0:
                    rate = stats['bytes'] / elapsed / 1024
                    self.ext3_video_rate_label.config(text=f"速率: {rate:.1f} KB/s")

            self.ext3_video_buffer_label.config(text=f"缓冲: {stats['buffer']/1024:.1f} KB")

            # 继续更新
            self.root.after(100, self.update_ext3_video_stats_display)

    def start_ext3_video(self):
        """开始拓展3接收"""
        try:
            ip = self.ext3_video_ip_entry.get()
            port = int(self.ext3_video_port_entry.get())
            width = int(self.ext3_video_width_entry.get())
            height = int(self.ext3_video_height_entry.get())
            timeout = float(self.ext3_video_timeout_entry.get())

            # 创建并启动线程
            self.ext3_video_thread = VideoReceiverThread(self.ext3_video_callback)
            self.ext3_video_thread.set_config(ip, port, width, height, timeout)
            self.ext3_video_thread.start()

            self.ext3_video_start_time = time.time()

            # 更新按钮状态
            self.ext3_video_ip_entry.config(state='disabled')
            self.ext3_video_port_entry.config(state='disabled')
            self.ext3_video_width_entry.config(state='disabled')
            self.ext3_video_height_entry.config(state='disabled')
            self.ext3_video_timeout_entry.config(state='disabled')

            self.log("拓展3接收已启动", "success")

        except Exception as e:
            self.log(f"启动失败: {e}", "error")

    def stop_ext3_video(self):
        """停止拓展3接收"""
        if self.ext3_video_thread and self.ext3_video_thread.running:
            self.ext3_video_thread.stop()
            self.ext3_video_thread.join(timeout=2.0)

            # 恢复按钮状态
            self.ext3_video_ip_entry.config(state='normal')
            self.ext3_video_port_entry.config(state='normal')
            self.ext3_video_width_entry.config(state='normal')
            self.ext3_video_height_entry.config(state='normal')
            self.ext3_video_timeout_entry.config(state='normal')

            self.log("拓展3接收已停止", "warning")

    def quick_reset_ext3_video(self):
        """拓展3快速重置：停止→清除缓冲→重新开始接收"""
        self.log("执行快速重置...", "info")

        # 第1步：停止接收线程
        if self.ext3_video_thread and self.ext3_video_thread.running:
            self.ext3_video_thread.stop()
            self.ext3_video_thread.join(timeout=1.0)  # 等待线程结束
            self.log("已停止接收", "info")

        # 第2步：清除线程对象（重要：防止复用已关闭socket的线程）
        self.ext3_video_thread = None

        # 第3步：清除当前帧显示
        self.ext3_current_frame = None
        self.ext3_video_canvas.delete("all")
        self.ext3_video_canvas.create_text(
            self.scale(320), self.scale(240),
            text="正在重启接收...",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

        # 第4步：恢复按钮状态（允许修改配置）
        self.ext3_video_ip_entry.config(state='normal')
        self.ext3_video_port_entry.config(state='normal')
        self.ext3_video_width_entry.config(state='normal')
        self.ext3_video_height_entry.config(state='normal')
        self.ext3_video_timeout_entry.config(state='normal')

        # 第5步：立即重新开始接收（减少延迟到50ms）
        self.root.after(50, self.start_ext3_video)

    def save_ext3_video_frame(self):
        """保存拓展3当前视频帧"""
        if self.ext3_current_frame is None:
            self.log("没有可保存的视频帧", "warning")
            return

        try:
            # 使用文件对话框选择保存位置
            filename = filedialog.asksaveasfilename(
                defaultextension=".png",
                filetypes=[("PNG图片", "*.png"), ("JPEG图片", "*.jpg"), ("所有文件", "*.*")],
                initialfile=f"ext3_frame_{int(time.time())}.png"
            )

            if filename:
                pil_img = Image.fromarray(self.ext3_current_frame)
                pil_img.save(filename)
                self.log(f"已保存: {filename}", "success")

        except Exception as e:
            self.log(f"保存失败: {e}", "error")

    def clear_ext3_video_stats(self):
        """清空拓展3统计信息"""
        if self.ext3_video_thread:
            self.ext3_video_thread.packet_count = 0
            self.ext3_video_thread.frame_count = 0
            self.ext3_video_thread.total_bytes = 0
            self.ext3_video_thread.fps_queue.clear()
            self.ext3_video_thread.frame_buffer.clear()

            self.ext3_video_start_time = time.time()

            self.log("统计信息已清空", "info")

    def update_ext3_serial_display(self, text):
        """更新串口数据显示（添加新行到ScrolledText）"""
        self.ext3_serial_text.config(state='normal')  # 临时解除只读
        self.ext3_serial_text.insert(tk.END, f"{text}\n")
        self.ext3_serial_text.see(tk.END)  # 自动滚动到最新
        self.ext3_serial_text.config(state='disabled')  # 恢复只读

    def start_ext3_plate_recognition(self):
        """开始车牌识别 - 发送0x30命令并启动串口接收"""
        # 发送控制命令0x30到192.168.240.1:2222
        self.send_control_command(0x30, "车牌识别")

        # 启动串口接收线程（如果串口已连接）
        if self.serial_connected and self.serial_port:
            # 创建并启动串口接收线程
            if not hasattr(self, 'ext3_serial_thread') or not self.ext3_serial_thread or not self.ext3_serial_thread.is_alive():
                self.ext3_serial_thread = threading.Thread(target=self.ext3_serial_receive_loop, daemon=True)
                self.ext3_serial_thread.start()
                self.log("已启动车牌识别，串口接收线程已启动", "success")
            else:
                self.log("串口接收线程已在运行中", "info")
        else:
            self.log("车牌识别命令已发送，但串口未连接，无法接收数据", "warning")

    def ext3_serial_receive_loop(self):
        """拓展3串口接收线程 - 接收格式：0xAA + 数据 + 0xCC"""
        receive_buffer = bytearray()

        try:
            while self.serial_connected and self.serial_port:
                try:
                    # 读取可用数据
                    if self.serial_port.in_waiting > 0:
                        data = self.serial_port.read(self.serial_port.in_waiting)
                        receive_buffer.extend(data)

                        # 解析帧数据
                        while len(receive_buffer) >= 3:  # 至少需要：帧头 + 1字节数据 + 帧尾
                            # 查找帧头 0xAA
                            header_index = receive_buffer.find(b'\xAA')

                            if header_index == -1:
                                # 没有帧头，清空缓冲区
                                receive_buffer.clear()
                                break

                            # 移除帧头之前的数据
                            if header_index > 0:
                                receive_buffer = receive_buffer[header_index:]

                            # 查找帧尾 0xCC（从帧头之后开始查找）
                            footer_index = receive_buffer.find(b'\xCC', 1)

                            if footer_index == -1:
                                # 没有帧尾，等待更多数据
                                # 但如果缓冲区过大，清除部分数据防止溢出
                                if len(receive_buffer) > 100:
                                    receive_buffer = receive_buffer[-50:]
                                break

                            # 提取完整帧：0xAA + 数据 + 0xCC
                            frame = receive_buffer[0:footer_index+1]

                            # 提取中间的数据（去掉帧头和帧尾）
                            if len(frame) >= 3:
                                payload = frame[1:-1]  # 去掉第一个字节(0xAA)和最后一个字节(0xCC)

                                # 转换为字符串显示
                                try:
                                    # 尝试解码为ASCII字符串
                                    data_str = payload.decode('ascii', errors='ignore')
                                    # 在主线程更新显示
                                    self.root.after(0, self.update_ext3_received_data, data_str, payload)
                                except:
                                    # 如果解码失败，显示十六进制
                                    hex_str = ' '.join(f'{b:02X}' for b in payload)
                                    self.root.after(0, self.update_ext3_received_data, hex_str, payload)

                            # 移除已处理的帧
                            receive_buffer = receive_buffer[footer_index+1:]

                    else:
                        # 没有数据，短暂休眠
                        time.sleep(0.01)

                except Exception as e:
                    if self.serial_connected:
                        self.root.after(0, self.log, f"串口接收错误: {e}", "error")
                    break

        except Exception as e:
            self.root.after(0, self.log, f"串口接收线程异常: {e}", "error")

    def update_ext3_received_data(self, data_str, raw_data):
        """更新拓展3串口接收的数据显示"""
        try:
            # 更新串口显示区（左侧）
            timestamp = time.strftime('%H:%M:%S')
            display_text = f"[{timestamp}] 收到: {data_str}\n"
            self.update_ext3_serial_display(display_text)

            # 更新大号数字显示区（右侧）
            # 提取数字字符显示
            digits_only = ''.join(c for c in data_str if c.isdigit())
            if digits_only:
                # 如果有多个数字，只显示第一个
                display_digit = digits_only[0] if len(digits_only) > 0 else data_str
            else:
                # 如果没有数字，显示原始字符串（截断到5个字符）
                display_digit = data_str[:5] if len(data_str) <= 5 else data_str[:5]

            self.ext3_digit_canvas.itemconfig(self.ext3_digit_text, text=display_digit)

            # 记录日志
            hex_str = ' '.join(f'{b:02X}' for b in raw_data)
            self.log(f"串口数据: {data_str} (Hex: {hex_str})", "info")

        except Exception as e:
            self.log(f"更新接收数据显示错误: {e}", "error")

    # ========== 图片发送升级版方法 ==========

    def create_adv_control_panel(self, parent):
        """创建高级发送控制面板"""
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(300))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="高级图片发送",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 文件选择
        file_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        file_frame.pack(fill='x', pady=(0, self.scale(8)))

        tk.Label(file_frame, text="图片文件",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.adv_file_label = tk.Label(file_frame, text="未选择文件",
                font=("SF Mono", self.scale(8)),
                bg=AppleColors.BG_TERTIARY,
                fg=AppleColors.TEXT_TERTIARY,
                anchor='w',
                padx=self.scale(8),
                pady=self.scale(5))
        self.adv_file_label.pack(fill='x', pady=(0, self.scale(4)))

        AppleButton(file_frame, "选择图片", self.select_adv_image,
                   width=self.scale(260), height=self.scale(28), style="secondary").pack()

        # 配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(self.scale(8), self.scale(8)))

        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # 目标IP
        tk.Label(config_frame, text="目标IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.adv_ip_entry = tk.Entry(config_frame, **entry_style)
        self.adv_ip_entry.insert(0, "192.168.240.1")
        self.adv_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.adv_port_entry = tk.Entry(config_frame, **entry_style)
        self.adv_port_entry.insert(0, "4")
        self.adv_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 帧间隔(ms)
        tk.Label(config_frame, text="帧间隔(ms)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.adv_frame_interval = tk.Entry(config_frame, **entry_style)
        self.adv_frame_interval.insert(0, "100")
        self.adv_frame_interval.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 包间延迟(μs)
        tk.Label(config_frame, text="包间延迟(μs)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.adv_packet_delay = tk.Entry(config_frame, **entry_style)
        self.adv_packet_delay.insert(0, "100")
        self.adv_packet_delay.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 选项
        option_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        option_frame.pack(fill='x', pady=(self.scale(4), 0))

        self.adv_continuous_var = tk.IntVar(value=1)
        cb1 = tk.Checkbutton(option_frame, text="连续发送",
                           variable=self.adv_continuous_var,
                           bg=AppleColors.BG_SECONDARY,
                           fg=AppleColors.TEXT_PRIMARY,
                           selectcolor=AppleColors.BG_TERTIARY,
                           font=("SF Pro Display", self.scale(9)),
                           activebackground=AppleColors.BG_SECONDARY)
        cb1.pack(anchor='w', pady=(0, self.scale(2)))

        self.adv_frame_sync_var = tk.IntVar(value=1)
        cb2 = tk.Checkbutton(option_frame, text="帧同步标识",
                           variable=self.adv_frame_sync_var,
                           bg=AppleColors.BG_SECONDARY,
                           fg=AppleColors.TEXT_PRIMARY,
                           selectcolor=AppleColors.BG_TERTIARY,
                           font=("SF Pro Display", self.scale(9)),
                           activebackground=AppleColors.BG_SECONDARY)
        cb2.pack(anchor='w')

        # 控制按钮
        btn_container = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        btn_container.pack(fill='x', pady=(self.scale(8), 0))

        self.adv_start_btn = AppleButton(btn_container, "开始发送", self.start_adv_send,
                                         width=self.scale(260), height=self.scale(32), style="success")
        self.adv_start_btn.pack(pady=(0, self.scale(5)))

        self.adv_stop_btn = AppleButton(btn_container, "停止发送", self.stop_adv_send,
                                        width=self.scale(260), height=self.scale(32), style="danger")
        self.adv_stop_btn.pack()

        return panel_frame

    def create_adv_preview(self, parent):
        """创建高级发送预览区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="图片预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 图片显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.adv_canvas = tk.Canvas(display_frame,
                                     width=self.scale(640),
                                     height=self.scale(480),
                                     bg=AppleColors.BG_TERTIARY,
                                     highlightthickness=1,
                                     highlightbackground=AppleColors.BORDER)
        self.adv_canvas.pack()

        # 默认提示文字
        self.adv_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待选择图片...\n点击\"选择图片\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_adv_stats(self, parent):
        """创建高级发送统计信息卡片"""
        card = self.create_card(parent, height=self.scale(120))

        # 标题
        tk.Label(card, text="发送统计（实时）",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建三行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(5)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x', pady=(0, self.scale(5)))

        row3 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row3.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(5)
        }

        # 第一行
        self.adv_status_label = tk.Label(row1, text="状态: 等待中", **label_style)
        self.adv_status_label.pack(side='left', padx=(0, self.scale(5)))

        self.adv_frames_label = tk.Label(row1, text="已发送: 0 帧", **label_style)
        self.adv_frames_label.pack(side='left', padx=(0, self.scale(5)))

        self.adv_throughput_label = tk.Label(row1, text="速率: 0.00 Mbps", **label_style)
        self.adv_throughput_label.pack(side='left')

        # 第二行
        self.adv_fps_label = tk.Label(row2, text="帧率: 0.0 FPS", **label_style)
        self.adv_fps_label.pack(side='left', padx=(0, self.scale(5)))

        self.adv_bytes_label = tk.Label(row2, text="数据量: 0 KB", **label_style)
        self.adv_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.adv_elapsed_label = tk.Label(row2, text="用时: 0.0 秒", **label_style)
        self.adv_elapsed_label.pack(side='left')

        # 第三行：实时信息
        self.adv_packet_info_label = tk.Label(row3, text="包大小: 1400字节 | 总包数: 0", **label_style)
        self.adv_packet_info_label.pack(side='left')

    def select_adv_image(self):
        """选择高级发送图片"""
        filename = filedialog.askopenfilename(
            title="选择图片文件",
            filetypes=[
                ("图片文件", "*.png *.jpg *.jpeg *.bmp *.gif"),
                ("PNG图片", "*.png"),
                ("JPEG图片", "*.jpg *.jpeg"),
                ("BMP图片", "*.bmp"),
                ("所有文件", "*.*")
            ]
        )

        if not filename:
            return

        try:
            # 加载图片
            img = Image.open(filename)

            # 转换为RGB
            if img.mode != 'RGB':
                img = img.convert('RGB')

            # 显示原始尺寸信息
            orig_width, orig_height = img.size
            self.log(f"已加载图片: {filename.split('/')[-1]}, 尺寸: {orig_width}×{orig_height}", "info")

            # 调整到640x480
            img = img.resize((640, 480), Image.LANCZOS)
            self.log(f"图片已缩放到: 640×480", "info")

            self.adv_image_pil = img

            # 转换为字节数据
            img_array = np.array(img, dtype=np.uint8)
            self.adv_image_data = img_array.tobytes()

            # 显示预览
            preview_img = img.resize((self.scale(640), self.scale(480)), Image.LANCZOS)
            self.adv_photo = ImageTk.PhotoImage(preview_img)

            self.adv_canvas.delete("all")
            self.adv_canvas.create_image(
                self.scale(320), self.scale(240),
                image=self.adv_photo,
                anchor='center'
            )

            # 更新文件标签
            short_name = filename.split('/')[-1]
            if len(short_name) > 35:
                short_name = short_name[:32] + "..."
            self.adv_file_label.config(
                text=short_name,
                fg=AppleColors.TEXT_PRIMARY
            )

            self.log(f"图片已准备，大小: {len(self.adv_image_data)} 字节 (640×480 RGB888)", "success")

        except Exception as e:
            self.log(f"加载图片失败: {e}", "error")

    def start_adv_send(self):
        """开始高级发送"""
        if not self.adv_image_data:
            self.log("请先选择图片", "warning")
            return

        if self.adv_send_running:
            self.log("已有发送任务正在进行", "warning")
            return

        try:
            # 重置统计信息
            self.adv_stats = {
                'sent_frames': 0,
                'sent_bytes': 0,
                'start_time': time.time()
            }

            self.adv_send_running = True

            # 启动发送线程
            self.adv_send_thread = threading.Thread(target=self.adv_send_loop, daemon=True)
            self.adv_send_thread.start()

            # 禁用控件
            self.adv_ip_entry.config(state='disabled')
            self.adv_port_entry.config(state='disabled')

            self.log("开始高级发送（带帧同步）", "success")

            # 开始更新统计显示
            self.update_adv_stats_display()

        except Exception as e:
            self.log(f"启动失败: {e}", "error")
            self.adv_send_running = False

    def stop_adv_send(self):
        """停止高级发送"""
        self.adv_send_running = False

        if self.adv_send_thread:
            self.adv_send_thread.join(timeout=2.0)

        # 恢复控件
        self.adv_ip_entry.config(state='normal')
        self.adv_port_entry.config(state='normal')

        self.log("高级发送已停止", "warning")

    def adv_send_loop(self):
        """高级发送循环（带帧同步和性能优化）"""
        if not self.adv_image_data:
            return

        frame_data = self.adv_image_data
        frame_size = len(frame_data)

        # 帧同步标识（3字节，参考udp_debug_tool.py）
        FRAME_HEADER = b'\xAA\x55\xAA' if self.adv_frame_sync_var.get() else b''
        FRAME_FOOTER = b'\x55\xAA\x55' if self.adv_frame_sync_var.get() else b''

        # 添加帧头和帧尾
        frame_with_sync = FRAME_HEADER + frame_data + FRAME_FOOTER
        total_size = len(frame_with_sync)

        # 包大小
        MAX_PACKET_SIZE = 1400

        # 预先分片
        total_packets = (total_size + MAX_PACKET_SIZE - 1) // MAX_PACKET_SIZE
        packets = []
        for i in range(total_packets):
            start_idx = i * MAX_PACKET_SIZE
            end_idx = min(start_idx + MAX_PACKET_SIZE, total_size)
            packets.append(frame_with_sync[start_idx:end_idx])

        # 更新包信息显示
        self.root.after(0, lambda: self.adv_packet_info_label.config(
            text=f"包大小: {MAX_PACKET_SIZE}字节 | 总包数: {total_packets}"
        ))

        self.log(f"开始发送: {frame_size}字节 (640×480 RGB888), 分成{total_packets}个包", "info")

        # 创建UDP socket
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)

            target_ip = self.adv_ip_entry.get()
            target_port = int(self.adv_port_entry.get())
            frame_interval = float(self.adv_frame_interval.get()) / 1000.0
            packet_delay = float(self.adv_packet_delay.get()) / 1_000_000.0

            last_log_time = time.time()

            while self.adv_send_running:
                frame_start_time = time.time()

                # 发送所有分片
                for packet in packets:
                    if not self.adv_send_running:
                        break

                    sock.sendto(packet, (target_ip, target_port))
                    self.adv_stats['sent_bytes'] += len(packet)

                    if packet_delay > 0:
                        time.sleep(packet_delay)

                self.adv_stats['sent_frames'] += 1

                # 每秒更新一次日志
                current_time = time.time()
                if current_time - last_log_time >= 1.0:
                    elapsed = current_time - self.adv_stats['start_time']
                    if elapsed > 0:
                        throughput_mbps = (self.adv_stats['sent_bytes'] * 8) / (elapsed * 1_000_000)
                        fps = self.adv_stats['sent_frames'] / elapsed
                        self.log(
                            f"已发送 {self.adv_stats['sent_frames']} 帧 | "
                            f"速率: {throughput_mbps:.2f} Mbps | "
                            f"帧率: {fps:.1f} FPS",
                            "info"
                        )
                    last_log_time = current_time

                # 如果不是连续发送，只发一帧
                if not self.adv_continuous_var.get():
                    break

                # 帧间隔控制
                frame_time = time.time() - frame_start_time
                sleep_time = frame_interval - frame_time
                if sleep_time > 0:
                    time.sleep(sleep_time)

            sock.close()

            # 最终统计
            total_time = time.time() - self.adv_stats['start_time']
            if total_time > 0:
                avg_throughput = (self.adv_stats['sent_bytes'] * 8) / (total_time * 1_000_000)
                avg_fps = self.adv_stats['sent_frames'] / total_time
                self.log(
                    f"发送完成: {self.adv_stats['sent_frames']} 帧 | "
                    f"平均速率: {avg_throughput:.2f} Mbps | "
                    f"平均帧率: {avg_fps:.1f} FPS",
                    "success"
                )

        except Exception as e:
            self.log(f"发送错误: {e}", "error")
        finally:
            self.adv_send_running = False

    def update_adv_stats_display(self):
        """更新高级发送统计显示"""
        if self.adv_send_running:
            elapsed = time.time() - self.adv_stats['start_time']

            # 计算速率
            throughput_mbps = 0
            fps = 0
            if elapsed > 0:
                throughput_mbps = (self.adv_stats['sent_bytes'] * 8) / (elapsed * 1_000_000)
                fps = self.adv_stats['sent_frames'] / elapsed

            # 更新显示
            status = "发送中" if self.adv_send_running else "已停止"
            self.adv_status_label.config(text=f"状态: {status}")
            self.adv_frames_label.config(text=f"已发送: {self.adv_stats['sent_frames']} 帧")
            self.adv_throughput_label.config(text=f"速率: {throughput_mbps:.2f} Mbps")
            self.adv_fps_label.config(text=f"帧率: {fps:.1f} FPS")
            self.adv_bytes_label.config(text=f"数据量: {self.adv_stats['sent_bytes']//1024} KB")
            self.adv_elapsed_label.config(text=f"用时: {elapsed:.1f} 秒")

            # 继续更新
            self.root.after(100, self.update_adv_stats_display)
        else:
            self.adv_status_label.config(text="状态: 已停止")

    # ========== 视频发送功能 ==========

    def create_video_send_tab(self):
        """创建视频发送标签页"""
        tab = tk.Frame(self.notebook, bg=AppleColors.BG_PRIMARY)
        self.notebook.add(tab, text='视频发送')

        # 初始化视频发送相关变量
        self.video_send_thread = None
        self.video_send_running = False
        self.video_capture = None
        self.video_file_path = None
        self.video_send_stats = {
            'sent_frames': 0,
            'total_frames': 0,
            'sent_bytes': 0,
            'start_time': 0,
            'fps': 0
        }

        # 内容容器
        content = tk.Frame(tab, bg=AppleColors.BG_PRIMARY)
        content.pack(fill='both', expand=True, pady=self.scale(10))

        # 上部：控制区域（左）+ 视频预览（右）
        top_frame = tk.Frame(content, bg=AppleColors.BG_PRIMARY)
        top_frame.pack(fill='both', expand=True, padx=self.scale(10), pady=self.scale(10))

        # 左侧：控制面板
        control_panel = self.create_video_send_control_panel(top_frame)
        control_panel.pack(side='left', fill='both', padx=(0, self.scale(10)))

        # 右侧：视频预览区域
        preview_frame = tk.Frame(top_frame, bg=AppleColors.BG_PRIMARY)
        preview_frame.pack(side='right', fill='both', expand=True)

        self.create_video_send_preview(preview_frame)

        # 下部：统计信息
        self.create_video_send_stats(content)

    def create_video_send_control_panel(self, parent):
        """创建视频发送控制面板"""
        panel_frame = tk.Frame(parent, bg=AppleColors.BG_PRIMARY, width=self.scale(300))
        panel_frame.pack_propagate(False)

        card = self.create_card(panel_frame, height=None)
        card.pack(fill='both', expand=True)

        # 标题
        tk.Label(card, text="视频发送",
                font=("SF Pro Display", self.scale(16), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(12), self.scale(8)))

        content_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        content_frame.pack(fill='both', expand=True, padx=self.scale(15), pady=(0, self.scale(12)))

        # 文件选择
        file_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        file_frame.pack(fill='x', pady=(0, self.scale(8)))

        tk.Label(file_frame, text="视频文件",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_send_file_label = tk.Label(file_frame, text="未选择文件",
                font=("SF Mono", self.scale(8)),
                bg=AppleColors.BG_TERTIARY,
                fg=AppleColors.TEXT_TERTIARY,
                anchor='w',
                padx=self.scale(8),
                pady=self.scale(5))
        self.video_send_file_label.pack(fill='x', pady=(0, self.scale(4)))

        AppleButton(file_frame, "选择视频", self.select_video_file,
                   width=self.scale(260), height=self.scale(28), style="secondary").pack()

        # 配置组
        config_frame = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        config_frame.pack(fill='x', pady=(self.scale(8), self.scale(8)))

        entry_style = {
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'font': ('SF Pro Display', self.scale(9)),
            'relief': 'flat',
            'bd': 1,
            'borderwidth': 1
        }

        # 目标IP
        tk.Label(config_frame, text="目标IP",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_send_ip_entry = tk.Entry(config_frame, **entry_style)
        self.video_send_ip_entry.insert(0, "192.168.240.1")
        self.video_send_ip_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # UDP端口
        tk.Label(config_frame, text="UDP端口",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_send_port_entry = tk.Entry(config_frame, **entry_style)
        self.video_send_port_entry.insert(0, "4")
        self.video_send_port_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 帧率控制
        tk.Label(config_frame, text="播放帧率(FPS)",
                font=("SF Pro Display", self.scale(9)),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_SECONDARY).pack(anchor='w', pady=(0, self.scale(2)))

        self.video_send_fps_entry = tk.Entry(config_frame, **entry_style)
        self.video_send_fps_entry.insert(0, "10")
        self.video_send_fps_entry.pack(fill='x', ipady=self.scale(5), pady=(0, self.scale(6)))

        # 选项
        option_frame = tk.Frame(config_frame, bg=AppleColors.BG_SECONDARY)
        option_frame.pack(fill='x', pady=(self.scale(4), 0))

        self.video_send_loop_var = tk.IntVar(value=0)
        cb1 = tk.Checkbutton(option_frame, text="循环播放",
                           variable=self.video_send_loop_var,
                           bg=AppleColors.BG_SECONDARY,
                           fg=AppleColors.TEXT_PRIMARY,
                           selectcolor=AppleColors.BG_TERTIARY,
                           font=("SF Pro Display", self.scale(9)),
                           activebackground=AppleColors.BG_SECONDARY)
        cb1.pack(anchor='w', pady=(0, self.scale(2)))

        self.video_send_frame_sync_var = tk.IntVar(value=1)
        cb2 = tk.Checkbutton(option_frame, text="帧同步标识",
                           variable=self.video_send_frame_sync_var,
                           bg=AppleColors.BG_SECONDARY,
                           fg=AppleColors.TEXT_PRIMARY,
                           selectcolor=AppleColors.BG_TERTIARY,
                           font=("SF Pro Display", self.scale(9)),
                           activebackground=AppleColors.BG_SECONDARY)
        cb2.pack(anchor='w')

        # 控制按钮
        btn_container = tk.Frame(content_frame, bg=AppleColors.BG_SECONDARY)
        btn_container.pack(fill='x', pady=(self.scale(8), 0))

        self.video_send_start_btn = AppleButton(btn_container, "开始发送", self.start_video_send,
                                         width=self.scale(260), height=self.scale(32), style="success")
        self.video_send_start_btn.pack(pady=(0, self.scale(5)))

        self.video_send_stop_btn = AppleButton(btn_container, "停止发送", self.stop_video_send,
                                        width=self.scale(260), height=self.scale(32), style="danger")
        self.video_send_stop_btn.pack()

        return panel_frame

    def create_video_send_preview(self, parent):
        """创建视频预览区域"""
        card = self.create_card(parent, height=None)

        # 标题
        tk.Label(card, text="视频预览",
                font=("SF Pro Display", self.scale(18), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(20), pady=(self.scale(15), self.scale(10)))

        # 视频显示Canvas
        display_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        display_frame.pack(fill='both', expand=True, padx=self.scale(20), pady=(0, self.scale(15)))

        self.video_send_canvas = tk.Canvas(display_frame,
                                     width=self.scale(640),
                                     height=self.scale(480),
                                     bg=AppleColors.BG_TERTIARY,
                                     highlightthickness=1,
                                     highlightbackground=AppleColors.BORDER)
        self.video_send_canvas.pack()

        # 默认提示文字
        self.video_send_canvas.create_text(
            self.scale(320), self.scale(240),
            text="等待选择视频...\n点击\"选择视频\"开始",
            font=("SF Pro Display", self.scale(16)),
            fill=AppleColors.TEXT_SECONDARY,
            tags="placeholder"
        )

    def create_video_send_stats(self, parent):
        """创建视频发送统计信息卡片"""
        card = self.create_card(parent, height=self.scale(120))

        # 标题
        tk.Label(card, text="发送统计（实时）",
                font=("SF Pro Display", self.scale(14), "bold"),
                bg=AppleColors.BG_SECONDARY,
                fg=AppleColors.TEXT_PRIMARY).pack(
                anchor='w', padx=self.scale(15), pady=(self.scale(10), self.scale(6)))

        stats_frame = tk.Frame(card, bg=AppleColors.BG_SECONDARY)
        stats_frame.pack(fill='x', padx=self.scale(15), pady=(0, self.scale(10)))

        # 创建三行统计信息
        row1 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row1.pack(fill='x', pady=(0, self.scale(5)))

        row2 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row2.pack(fill='x', pady=(0, self.scale(5)))

        row3 = tk.Frame(stats_frame, bg=AppleColors.BG_SECONDARY)
        row3.pack(fill='x')

        # 统计标签样式
        label_style = {
            'font': ('SF Mono', self.scale(9)),
            'bg': AppleColors.BG_TERTIARY,
            'fg': AppleColors.TEXT_PRIMARY,
            'padx': self.scale(8),
            'pady': self.scale(5)
        }

        # 第一行
        self.video_send_status_label = tk.Label(row1, text="状态: 等待中", **label_style)
        self.video_send_status_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_send_progress_label = tk.Label(row1, text="进度: 0/0", **label_style)
        self.video_send_progress_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_send_throughput_label = tk.Label(row1, text="速率: 0.00 Mbps", **label_style)
        self.video_send_throughput_label.pack(side='left')

        # 第二行
        self.video_send_fps_label = tk.Label(row2, text="实际帧率: 0.0 FPS", **label_style)
        self.video_send_fps_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_send_bytes_label = tk.Label(row2, text="数据量: 0 MB", **label_style)
        self.video_send_bytes_label.pack(side='left', padx=(0, self.scale(5)))

        self.video_send_elapsed_label = tk.Label(row2, text="用时: 0.0 秒", **label_style)
        self.video_send_elapsed_label.pack(side='left')

        # 第三行
        self.video_send_info_label = tk.Label(row3, text="分辨率: - | 原始帧率: - FPS", **label_style)
        self.video_send_info_label.pack(side='left')

    def select_video_file(self):
        """选择视频文件"""
        filename = filedialog.askopenfilename(
            title="选择视频文件",
            filetypes=[
                ("视频文件", "*.mp4 *.avi *.mov *.mkv *.flv *.wmv"),
                ("MP4视频", "*.mp4"),
                ("AVI视频", "*.avi"),
                ("MOV视频", "*.mov"),
                ("所有文件", "*.*")
            ]
        )

        if not filename:
            return

        try:
            # 使用OpenCV打开视频
            cap = cv2.VideoCapture(filename)

            if not cap.isOpened():
                self.log(f"无法打开视频文件: {filename}", "error")
                return

            # 获取视频信息
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            original_fps = cap.get(cv2.CAP_PROP_FPS)
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

            # 读取第一帧作为预览
            ret, frame = cap.read()
            if ret:
                # 转换BGR到RGB
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

                # 显示预览
                pil_img = Image.fromarray(frame_rgb)
                pil_img = pil_img.resize((self.scale(640), self.scale(480)), Image.LANCZOS)
                self.video_send_photo = ImageTk.PhotoImage(pil_img)

                self.video_send_canvas.delete("all")
                self.video_send_canvas.create_image(
                    self.scale(320), self.scale(240),
                    image=self.video_send_photo,
                    anchor='center'
                )

            cap.release()

            # 保存视频信息
            self.video_file_path = filename
            self.video_send_stats['total_frames'] = total_frames

            # 更新文件标签
            short_name = filename.split('/')[-1]
            if len(short_name) > 35:
                short_name = short_name[:32] + "..."
            self.video_send_file_label.config(
                text=short_name,
                fg=AppleColors.TEXT_PRIMARY
            )

            # 更新信息标签
            self.video_send_info_label.config(
                text=f"分辨率: {width}×{height} | 原始帧率: {original_fps:.1f} FPS | 总帧数: {total_frames}"
            )

            self.log(f"已加载视频: {short_name}", "success")
            self.log(f"分辨率: {width}×{height}, 帧数: {total_frames}, 帧率: {original_fps:.1f} FPS", "info")

        except Exception as e:
            self.log(f"加载视频失败: {e}", "error")

    def start_video_send(self):
        """开始视频发送"""
        if not self.video_file_path:
            self.log("请先选择视频文件", "warning")
            return

        if self.video_send_running:
            self.log("已有发送任务正在进行", "warning")
            return

        try:
            # 重置统计信息
            self.video_send_stats = {
                'sent_frames': 0,
                'total_frames': self.video_send_stats['total_frames'],
                'sent_bytes': 0,
                'start_time': time.time(),
                'fps': 0
            }

            self.video_send_running = True

            # 启动发送线程
            self.video_send_thread = threading.Thread(target=self.video_send_loop, daemon=True)
            self.video_send_thread.start()

            # 禁用控件
            self.video_send_ip_entry.config(state='disabled')
            self.video_send_port_entry.config(state='disabled')
            self.video_send_fps_entry.config(state='disabled')

            self.log("开始视频发送", "success")

            # 开始更新统计显示
            self.update_video_send_stats_display()

        except Exception as e:
            self.log(f"启动失败: {e}", "error")
            self.video_send_running = False

    def stop_video_send(self):
        """停止视频发送"""
        self.video_send_running = False

        if self.video_send_thread:
            self.video_send_thread.join(timeout=2.0)

        # 恢复控件
        self.video_send_ip_entry.config(state='normal')
        self.video_send_port_entry.config(state='normal')
        self.video_send_fps_entry.config(state='normal')

        self.log("视频发送已停止", "warning")

    def video_send_loop(self):
        """视频发送循环"""
        if not self.video_file_path:
            return

        try:
            # 创建UDP socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)

            target_ip = self.video_send_ip_entry.get()
            target_port = int(self.video_send_port_entry.get())
            target_fps = float(self.video_send_fps_entry.get())
            frame_interval = 1.0 / target_fps if target_fps > 0 else 0.1

            # 帧同步标识
            FRAME_HEADER = b'\xAA\x55\xAA' if self.video_send_frame_sync_var.get() else b''
            FRAME_FOOTER = b'\x55\xAA\x55' if self.video_send_frame_sync_var.get() else b''

            MAX_PACKET_SIZE = 1400

            last_log_time = time.time()

            while self.video_send_running:
                # 打开视频
                cap = cv2.VideoCapture(self.video_file_path)

                if not cap.isOpened():
                    self.log("无法打开视频文件", "error")
                    break

                while self.video_send_running:
                    frame_start_time = time.time()

                    # 读取一帧
                    ret, frame = cap.read()

                    if not ret:
                        # 视频结束
                        if self.video_send_loop_var.get():
                            # 循环播放，重新打开
                            break
                        else:
                            # 不循环，停止发送
                            self.video_send_running = False
                            self.root.after(0, lambda: self.log("视频发送完成", "success"))
                            break

                    # 转换BGR到RGB
                    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

                    # 调整到640x480
                    frame_resized = cv2.resize(frame_rgb, (640, 480))

                    # 转换为字节数据
                    frame_data = frame_resized.tobytes()

                    # 添加帧同步标识
                    frame_with_sync = FRAME_HEADER + frame_data + FRAME_FOOTER
                    total_size = len(frame_with_sync)

                    # 分包发送
                    total_packets = (total_size + MAX_PACKET_SIZE - 1) // MAX_PACKET_SIZE
                    for i in range(total_packets):
                        if not self.video_send_running:
                            break

                        start_idx = i * MAX_PACKET_SIZE
                        end_idx = min(start_idx + MAX_PACKET_SIZE, total_size)
                        packet = frame_with_sync[start_idx:end_idx]

                        sock.sendto(packet, (target_ip, target_port))
                        self.video_send_stats['sent_bytes'] += len(packet)

                    self.video_send_stats['sent_frames'] += 1

                    # 更新预览（每5帧更新一次）
                    if self.video_send_stats['sent_frames'] % 5 == 0:
                        pil_img = Image.fromarray(frame_resized)
                        pil_img = pil_img.resize((self.scale(640), self.scale(480)), Image.LANCZOS)
                        photo = ImageTk.PhotoImage(pil_img)

                        def update_preview(img):
                            self.video_send_photo = img
                            self.video_send_canvas.delete("all")
                            self.video_send_canvas.create_image(
                                self.scale(320), self.scale(240),
                                image=self.video_send_photo,
                                anchor='center'
                            )

                        self.root.after(0, update_preview, photo)

                    # 每秒更新一次日志
                    current_time = time.time()
                    if current_time - last_log_time >= 1.0:
                        elapsed = current_time - self.video_send_stats['start_time']
                        if elapsed > 0:
                            throughput_mbps = (self.video_send_stats['sent_bytes'] * 8) / (elapsed * 1_000_000)
                            actual_fps = self.video_send_stats['sent_frames'] / elapsed
                            self.log(
                                f"已发送 {self.video_send_stats['sent_frames']}/{self.video_send_stats['total_frames']} 帧 | "
                                f"速率: {throughput_mbps:.2f} Mbps | "
                                f"帧率: {actual_fps:.1f} FPS",
                                "info"
                            )
                        last_log_time = current_time

                    # 帧率控制
                    frame_time = time.time() - frame_start_time
                    sleep_time = frame_interval - frame_time
                    if sleep_time > 0:
                        time.sleep(sleep_time)

                cap.release()

                # 如果不循环，退出
                if not self.video_send_loop_var.get():
                    break

            sock.close()

            # 最终统计
            total_time = time.time() - self.video_send_stats['start_time']
            if total_time > 0:
                avg_throughput = (self.video_send_stats['sent_bytes'] * 8) / (total_time * 1_000_000)
                avg_fps = self.video_send_stats['sent_frames'] / total_time
                self.log(
                    f"发送完成: {self.video_send_stats['sent_frames']} 帧 | "
                    f"平均速率: {avg_throughput:.2f} Mbps | "
                    f"平均帧率: {avg_fps:.1f} FPS",
                    "success"
                )

        except Exception as e:
            self.log(f"发送错误: {e}", "error")
        finally:
            self.video_send_running = False

    def update_video_send_stats_display(self):
        """更新视频发送统计显示"""
        if self.video_send_running:
            elapsed = time.time() - self.video_send_stats['start_time']

            # 计算速率
            throughput_mbps = 0
            actual_fps = 0
            if elapsed > 0:
                throughput_mbps = (self.video_send_stats['sent_bytes'] * 8) / (elapsed * 1_000_000)
                actual_fps = self.video_send_stats['sent_frames'] / elapsed

            # 更新显示
            status = "发送中" if self.video_send_running else "已停止"
            self.video_send_status_label.config(text=f"状态: {status}")
            self.video_send_progress_label.config(
                text=f"进度: {self.video_send_stats['sent_frames']}/{self.video_send_stats['total_frames']}")
            self.video_send_throughput_label.config(text=f"速率: {throughput_mbps:.2f} Mbps")
            self.video_send_fps_label.config(text=f"实际帧率: {actual_fps:.1f} FPS")
            self.video_send_bytes_label.config(text=f"数据量: {self.video_send_stats['sent_bytes']/(1024*1024):.2f} MB")
            self.video_send_elapsed_label.config(text=f"用时: {elapsed:.1f} 秒")

            # 继续更新
            self.root.after(100, self.update_video_send_stats_display)
        else:
            self.video_send_status_label.config(text="状态: 已停止")

    def on_closing(self):
        if self.is_connected:
            self.disconnect()
        if self.serial_connected:
            self.disconnect_serial()
        self.root.destroy()


def main():
    root = tk.Tk()
    app = EthernetHostGUI(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()


if __name__ == "__main__":
    main()
