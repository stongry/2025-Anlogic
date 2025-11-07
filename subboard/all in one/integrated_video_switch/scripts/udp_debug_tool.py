    #!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP调试工具 - 发送RGB888彩条数据并接收解析调试信息
"""

import sys
import socket
import struct
import threading
import time
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                             QHBoxLayout, QPushButton, QTextEdit, QLabel,
                             QLineEdit, QGroupBox, QSpinBox, QCheckBox, QTabWidget,
                             QTableWidget, QTableWidgetItem, QHeaderView, QFileDialog)
from PyQt5.QtCore import pyqtSignal, QObject, Qt
from PyQt5.QtGui import QColor, QTextCursor, QImage, QPixmap
from PIL import Image
import numpy as np

class UDPSignals(QObject):
    """信号类，用于线程间通信"""
    log_signal = pyqtSignal(str, str)  # 消息, 类型(info/success/error/warning)
    debug_data_signal = pyqtSignal(dict)  # 调试数据

class UDPDebugTool(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("FPGA UDP 调试工具")
        self.setGeometry(100, 100, 1200, 800)

        # UDP配置
        self.local_ip = "192.168.240.2"
        self.local_port = 2
        self.target_ip = "192.168.240.1"
        self.target_port = 4

        # UDP socket
        self.sock = None
        self.running = False
        self.send_thread = None
        self.recv_thread = None

        # 信号
        self.signals = UDPSignals()
        self.signals.log_signal.connect(self.append_log)
        self.signals.debug_data_signal.connect(self.update_debug_table)

        # 统计信息
        self.stats = {
            'sent_frames': 0,
            'sent_bytes': 0,
            'recv_packets': 0,
            'recv_bytes': 0,
            'rgb_packets': 0,
            'sdram_packets': 0,
            'start_time': 0,
            'last_update_time': 0
        }

        # 调试数据存储
        self.debug_data_list = []

        # 自定义图片数据
        self.custom_image_data = None

        self.init_ui()

    def init_ui(self):
        """初始化UI"""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)

        # 配置区域
        config_group = QGroupBox("网络配置")
        config_layout = QHBoxLayout()

        config_layout.addWidget(QLabel("本地IP:"))
        self.local_ip_edit = QLineEdit(self.local_ip)
        config_layout.addWidget(self.local_ip_edit)

        config_layout.addWidget(QLabel("本地端口:"))
        self.local_port_spin = QSpinBox()
        self.local_port_spin.setRange(1, 65535)
        self.local_port_spin.setValue(self.local_port)
        config_layout.addWidget(self.local_port_spin)

        config_layout.addWidget(QLabel("目标IP:"))
        self.target_ip_edit = QLineEdit(self.target_ip)
        config_layout.addWidget(self.target_ip_edit)

        config_layout.addWidget(QLabel("目标端口:"))
        self.target_port_spin = QSpinBox()
        self.target_port_spin.setRange(1, 65535)
        self.target_port_spin.setValue(self.target_port)
        config_layout.addWidget(self.target_port_spin)

        config_group.setLayout(config_layout)
        main_layout.addWidget(config_group)

        # 控制区域
        control_group = QGroupBox("控制")
        control_layout = QHBoxLayout()

        self.connect_btn = QPushButton("连接")
        self.connect_btn.clicked.connect(self.toggle_connection)
        control_layout.addWidget(self.connect_btn)

        self.send_colorbar_btn = QPushButton("发送彩条")
        self.send_colorbar_btn.clicked.connect(self.start_send_colorbar)
        self.send_colorbar_btn.setEnabled(False)
        control_layout.addWidget(self.send_colorbar_btn)

        self.load_image_btn = QPushButton("加载图片")
        self.load_image_btn.clicked.connect(self.load_image)
        self.load_image_btn.setEnabled(False)
        control_layout.addWidget(self.load_image_btn)

        self.send_image_btn = QPushButton("发送图片")
        self.send_image_btn.clicked.connect(self.start_send_image)
        self.send_image_btn.setEnabled(False)
        control_layout.addWidget(self.send_image_btn)

        self.stop_send_btn = QPushButton("停止发送")
        self.stop_send_btn.clicked.connect(self.stop_send_colorbar)
        self.stop_send_btn.setEnabled(False)
        control_layout.addWidget(self.stop_send_btn)

        control_layout.addWidget(QLabel("帧间隔(ms):"))
        self.frame_interval_spin = QSpinBox()
        self.frame_interval_spin.setRange(10, 10000)
        self.frame_interval_spin.setValue(100)
        control_layout.addWidget(self.frame_interval_spin)

        control_layout.addWidget(QLabel("包间隔(us):"))
        self.packet_delay_spin = QSpinBox()
        self.packet_delay_spin.setRange(0, 10000)
        self.packet_delay_spin.setValue(100)  # 默认0.1ms
        self.packet_delay_spin.setToolTip("控制UDP包之间的延迟，减少FPGA接收缓冲区溢出")
        control_layout.addWidget(self.packet_delay_spin)

        self.continuous_check = QCheckBox("连续发送")
        self.continuous_check.setChecked(True)
        control_layout.addWidget(self.continuous_check)

        control_layout.addStretch()

        self.clear_btn = QPushButton("清除日志")
        self.clear_btn.clicked.connect(self.clear_log)
        control_layout.addWidget(self.clear_btn)

        self.copy_log_btn = QPushButton("复制日志")
        self.copy_log_btn.clicked.connect(self.copy_log)
        control_layout.addWidget(self.copy_log_btn)

        self.test_send_btn = QPushButton("测试发送(单包)")
        self.test_send_btn.clicked.connect(self.test_send_single_packet)
        self.test_send_btn.setEnabled(False)
        control_layout.addWidget(self.test_send_btn)

        control_group.setLayout(control_layout)
        main_layout.addWidget(control_group)

        # 统计信息
        stats_group = QGroupBox("统计信息")
        stats_layout = QHBoxLayout()

        self.stats_label = QLabel()
        self.update_stats_display()
        stats_layout.addWidget(self.stats_label)

        stats_group.setLayout(stats_layout)
        main_layout.addWidget(stats_group)

        # 标签页
        tab_widget = QTabWidget()

        # 日志标签页
        log_tab = QWidget()
        log_layout = QVBoxLayout(log_tab)
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        log_layout.addWidget(self.log_text)
        tab_widget.addTab(log_tab, "日志")

        # 调试数据标签页
        debug_tab = QWidget()
        debug_layout = QVBoxLayout(debug_tab)

        debug_control_layout = QHBoxLayout()
        self.clear_debug_btn = QPushButton("清除调试数据")
        self.clear_debug_btn.clicked.connect(self.clear_debug_table)
        debug_control_layout.addWidget(self.clear_debug_btn)

        self.copy_debug_btn = QPushButton("复制调试数据")
        self.copy_debug_btn.clicked.connect(self.copy_debug_data)
        debug_control_layout.addWidget(self.copy_debug_btn)

        self.auto_scroll_check = QCheckBox("自动滚动")
        self.auto_scroll_check.setChecked(True)
        debug_control_layout.addWidget(self.auto_scroll_check)

        debug_control_layout.addStretch()
        debug_layout.addLayout(debug_control_layout)

        self.debug_table = QTableWidget()
        self.debug_table.setColumnCount(7)
        self.debug_table.setHorizontalHeaderLabels([
            "时间", "类型", "序列号", "数据1", "数据2", "数据3", "原始数据"
        ])
        self.debug_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)
        debug_layout.addWidget(self.debug_table)

        tab_widget.addTab(debug_tab, "调试数据")

        main_layout.addWidget(tab_widget)

        # 状态栏
        self.statusBar().showMessage("就绪")

    def toggle_connection(self):
        """切换连接状态"""
        if not self.running:
            self.connect()
        else:
            self.disconnect()

    def connect(self):
        """建立UDP连接"""
        try:
            self.local_ip = self.local_ip_edit.text()
            self.local_port = self.local_port_spin.value()
            self.target_ip = self.target_ip_edit.text()
            self.target_port = self.target_port_spin.value()

            # 创建UDP socket
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

            # 设置socket选项 - 性能优化
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            # 增大发送和接收缓冲区，提高吞吐量
            # 默认通常是几十KB，增大到1MB可以显著提升性能
            try:
                self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)  # 1MB发送缓冲
                self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024 * 1024)  # 1MB接收缓冲
            except:
                pass  # 某些系统可能不支持设置这么大的缓冲区

            # 绑定到本地地址
            self.sock.bind((self.local_ip, self.local_port))
            self.sock.settimeout(0.1)  # 设置超时，避免阻塞

            self.running = True

            # 启动接收线程
            self.recv_thread = threading.Thread(target=self.receive_loop, daemon=True)
            self.recv_thread.start()

            self.signals.log_signal.emit(
                f"已连接: {self.local_ip}:{self.local_port} -> {self.target_ip}:{self.target_port}",
                "success"
            )

            self.connect_btn.setText("断开")
            self.send_colorbar_btn.setEnabled(True)
            self.load_image_btn.setEnabled(True)
            self.test_send_btn.setEnabled(True)
            self.statusBar().showMessage("已连接")

            # 禁用配置编辑
            self.local_ip_edit.setEnabled(False)
            self.local_port_spin.setEnabled(False)
            self.target_ip_edit.setEnabled(False)
            self.target_port_spin.setEnabled(False)

        except Exception as e:
            import traceback
            error_msg = f"连接失败: {str(e)}\n{traceback.format_exc()}"
            self.signals.log_signal.emit(error_msg, "error")
            self.statusBar().showMessage("连接失败")

            # 清理
            if self.sock:
                try:
                    self.sock.close()
                except:
                    pass
                self.sock = None
            self.running = False

    def disconnect(self):
        """断开UDP连接"""
        self.running = False

        if self.send_thread and self.send_thread.is_alive():
            self.send_thread.join(timeout=1)

        if self.recv_thread and self.recv_thread.is_alive():
            self.recv_thread.join(timeout=1)

        if self.sock:
            self.sock.close()
            self.sock = None

        self.signals.log_signal.emit("已断开连接", "info")
        self.connect_btn.setText("连接")
        self.send_colorbar_btn.setEnabled(False)
        self.load_image_btn.setEnabled(False)
        self.send_image_btn.setEnabled(False)
        self.test_send_btn.setEnabled(False)
        self.stop_send_btn.setEnabled(False)
        self.statusBar().showMessage("已断开")

        # 启用配置编辑
        self.local_ip_edit.setEnabled(True)
        self.local_port_spin.setEnabled(True)
        self.target_ip_edit.setEnabled(True)
        self.target_port_spin.setEnabled(True)

    def start_send_colorbar(self):
        """开始发送彩条数据"""
        if self.send_thread and self.send_thread.is_alive():
            self.signals.log_signal.emit("已经在发送中", "warning")
            return

        self.stats['start_time'] = time.time()
        self.stats['last_update_time'] = time.time()
        self.send_thread = threading.Thread(target=self.send_colorbar_loop, daemon=True)
        self.send_thread.start()

        self.send_colorbar_btn.setEnabled(False)
        self.send_image_btn.setEnabled(False)
        self.stop_send_btn.setEnabled(True)
        self.signals.log_signal.emit("开始发送彩条数据", "success")

    def start_send_image(self):
        """开始发送自定义图片数据"""
        if not self.custom_image_data:
            self.signals.log_signal.emit("请先加载图片", "warning")
            return

        if self.send_thread and self.send_thread.is_alive():
            self.signals.log_signal.emit("已经在发送中", "warning")
            return

        self.stats['start_time'] = time.time()
        self.stats['last_update_time'] = time.time()
        self.send_thread = threading.Thread(target=self.send_image_loop, daemon=True)
        self.send_thread.start()

        self.send_colorbar_btn.setEnabled(False)
        self.send_image_btn.setEnabled(False)
        self.stop_send_btn.setEnabled(True)
        self.signals.log_signal.emit("开始发送图片数据", "success")

    def stop_send_colorbar(self):
        """停止发送彩条数据"""
        if self.send_thread:
            self.send_thread = None

        self.send_colorbar_btn.setEnabled(True)
        if self.custom_image_data:
            self.send_image_btn.setEnabled(True)
        self.stop_send_btn.setEnabled(False)
        self.signals.log_signal.emit("停止发送数据", "info")

    def load_image(self):
        """加载图片并转换为640x480 RGB888格式"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择图片",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.bmp *.gif);;所有文件 (*.*)"
        )

        if not file_path:
            return

        try:
            # 使用PIL加载图片
            img = Image.open(file_path)

            # 转换为RGB模式（如果是RGBA或其他模式）
            if img.mode != 'RGB':
                img = img.convert('RGB')

            # 调整大小为640x480
            img_resized = img.resize((640, 480), Image.LANCZOS)

            # 转换为numpy数组
            img_array = np.array(img_resized, dtype=np.uint8)

            # 转换为字节流 (RGB888格式)
            self.custom_image_data = img_array.tobytes()

            self.signals.log_signal.emit(
                f"成功加载图片: {file_path}\n"
                f"原始尺寸: {img.size}, 调整后: 640x480, "
                f"数据大小: {len(self.custom_image_data)} 字节",
                "success"
            )

            # 启用发送图片按钮
            self.send_image_btn.setEnabled(True)

        except Exception as e:
            import traceback
            error_msg = f"加载图片失败: {str(e)}\n{traceback.format_exc()}"
            self.signals.log_signal.emit(error_msg, "error")
            self.custom_image_data = None
            self.send_image_btn.setEnabled(False)

    def generate_colorbar_frame(self):
        """生成彩条帧数据 (640x480 RGB888)"""
        width = 640
        height = 480

        # 8色彩条: 白、黄、青、绿、品红、红、蓝、黑
        colors = [
            (255, 255, 255),  # 白
            (255, 255, 0),    # 黄
            (0, 255, 255),    # 青
            (0, 255, 0),      # 绿
            (255, 0, 255),    # 品红
            (255, 0, 0),      # 红
            (0, 0, 255),      # 蓝
            (0, 0, 0),        # 黑
        ]

        bar_width = width // len(colors)
        frame_data = bytearray()

        for y in range(height):
            for x in range(width):
                color_index = x // bar_width
                if color_index >= len(colors):
                    color_index = len(colors) - 1

                r, g, b = colors[color_index]
                # 尝试BGR顺序（蓝-绿-红）而不是RGB
                frame_data.extend([r, g, b])

        return bytes(frame_data)

    def send_colorbar_loop(self):
        """发送彩条数据循环 - 优化版本"""
        frame_data = self.generate_colorbar_frame()
        self._send_frame_loop(frame_data, "彩条")

    def send_image_loop(self):
        """发送图片数据循环 - 优化版本"""
        if not self.custom_image_data:
            self.signals.log_signal.emit("没有图片数据可发送", "error")
            return
        self._send_frame_loop(self.custom_image_data, "图片")

    def _send_frame_loop(self, frame_data, data_type):
        """通用帧发送循环 - 性能优化版本 + 帧同步"""
        frame_size = len(frame_data)

        # 帧头标识 (4字节): 0xAA55AA55
        FRAME_HEADER = b'\xAA\x55\xAA'
        # 帧尾标识 (4字节): 0x55AA55AAAA
        FRAME_FOOTER = b'\x55\xAA\x55'

        # 添加帧头和帧尾
        frame_with_sync = FRAME_HEADER + frame_data + FRAME_FOOTER
        total_size = len(frame_with_sync)

        # 优化：调整包大小，为帧同步留出空间
        # 以太网MTU通常是1500字节，减去IP头(20)和UDP头(8)，实际可用约1472字节
        # 但为了更好的兼容性和减少丢包，使用稍小的值
        MAX_PACKET_SIZE = 1400  # 字节，平衡性能和可靠性

        total_packets = (total_size + MAX_PACKET_SIZE - 1) // MAX_PACKET_SIZE

        self.signals.log_signal.emit(
            f"开始发送{data_type}帧: {frame_size} 字节 (640x480 RGB888), "
            f"添加帧同步后: {total_size} 字节, "
            f"将分成 {total_packets} 个UDP包发送 (每包{MAX_PACKET_SIZE}字节)",
            "info"
        )

        send_count = 0
        last_log_time = time.time()

        # 优化：预先分片数据，避免循环中重复计算
        packets = []
        for i in range(total_packets):
            start_idx = i * MAX_PACKET_SIZE
            end_idx = min(start_idx + MAX_PACKET_SIZE, total_size)
            packets.append(frame_with_sync[start_idx:end_idx])

        while self.send_thread and self.running:
            try:
                frame_start_time = time.time()

                # 批量发送所有分片
                for packet in packets:
                    if not self.send_thread or not self.running:
                        break

                    # 发送分片
                    self.sock.sendto(packet, (self.target_ip, self.target_port))
                    self.stats['sent_bytes'] += len(packet)

                    # 优化：添加可调节的包间延迟以控制发送速率
                    # 避免FPGA接收缓冲区溢出导致的数据错位
                    packet_delay = self.packet_delay_spin.value() / 1_000_000.0  # 转换为秒
                    if packet_delay > 0:
                        time.sleep(packet_delay)

                send_count += 1
                self.stats['sent_frames'] += 1

                # 计算实时传输速率
                current_time = time.time()
                if current_time - last_log_time >= 1.0:  # 每秒更新一次
                    elapsed = current_time - self.stats['start_time']
                    if elapsed > 0:
                        throughput_mbps = (self.stats['sent_bytes'] * 8) / (elapsed * 1_000_000)
                        fps = self.stats['sent_frames'] / elapsed

                        self.signals.log_signal.emit(
                            f"已发送 {send_count} 帧 | "
                            f"速率: {throughput_mbps:.2f} Mbps | "
                            f"帧率: {fps:.1f} FPS | "
                            f"总数据: {self.stats['sent_bytes']//1024} KB",
                            "info"
                        )
                        last_log_time = current_time

                self.update_stats_display()

                # 如果不是连续发送，只发送一帧
                if not self.continuous_check.isChecked():
                    break

                # 帧间隔控制
                frame_time = time.time() - frame_start_time
                target_interval = self.frame_interval_spin.value() / 1000.0
                sleep_time = target_interval - frame_time
                if sleep_time > 0:
                    time.sleep(sleep_time)

            except Exception as e:
                self.signals.log_signal.emit(f"发送错误: {str(e)}", "error")
                break

        # 最终统计
        total_time = time.time() - self.stats['start_time']
        if total_time > 0:
            avg_throughput = (self.stats['sent_bytes'] * 8) / (total_time * 1_000_000)
            avg_fps = self.stats['sent_frames'] / total_time
            self.signals.log_signal.emit(
                f"发送完成: {send_count} 帧 | "
                f"平均速率: {avg_throughput:.2f} Mbps | "
                f"平均帧率: {avg_fps:.1f} FPS",
                "success"
            )

        if not self.continuous_check.isChecked():
            # 在主线程中更新按钮状态
            self.send_colorbar_btn.setEnabled(True)
            if self.custom_image_data:
                self.send_image_btn.setEnabled(True)
            self.stop_send_btn.setEnabled(False)

    def receive_loop(self):
        """接收数据循环"""
        receive_buffer = bytearray()  # 接收缓冲区
        max_buffer_size = 65536  # 最大缓冲区大小

        try:
            while self.running:
                try:
                    data, addr = self.sock.recvfrom(65535)

                    if data:
                        self.stats['recv_packets'] += 1
                        self.stats['recv_bytes'] += len(data)

                        # 添加到接收缓冲区
                        receive_buffer.extend(data)

                        # 限制缓冲区大小，防止内存溢出
                        if len(receive_buffer) > max_buffer_size:
                            # 只保留最新的数据
                            receive_buffer = receive_buffer[-max_buffer_size:]

                        # 每收到一定数量的数据才更新统计和解析
                        if self.stats['recv_packets'] % 10 == 0:
                            self.update_stats_display()

                        # 批量解析（减少UI更新频率）
                        if len(receive_buffer) >= 1024 or self.stats['recv_packets'] % 20 == 0:
                            self.parse_debug_data(bytes(receive_buffer))
                            receive_buffer.clear()

                except socket.timeout:
                    # 超时时也处理剩余缓冲区数据
                    if len(receive_buffer) > 0:
                        self.parse_debug_data(bytes(receive_buffer))
                        receive_buffer.clear()
                    continue
                except Exception as e:
                    if self.running:
                        self.signals.log_signal.emit(f"接收错误: {str(e)}", "error")
                        break
        except Exception as e:
            self.signals.log_signal.emit(f"接收线程异常: {str(e)}", "error")

    def parse_debug_data(self, data):
        """解析调试数据包"""
        offset = 0

        while offset < len(data) - 4:  # 至少需要4字节的头部
            # 查找帧头 0xAA55AA55
            if (offset + 3 < len(data) and
                data[offset] == 0xAA and data[offset+1] == 0x55 and
                data[offset+2] == 0xAA and data[offset+3] == 0x55):

                # 检查是否有足够的数据读取类型和序列号
                if offset + 6 > len(data):
                    break

                packet_type = data[offset + 4]
                seq_num = data[offset + 5]

                debug_info = {
                    'time': time.strftime('%H:%M:%S'),
                    'type': '',
                    'seq': seq_num,
                    'data1': '',
                    'data2': '',
                    'data3': '',
                    'raw': ''
                }

                if packet_type == 0x01:  # RGB数据包 (16字节)
                    if offset + 16 <= len(data):
                        packet = data[offset:offset+16]

                        # 验证帧尾 0x55AA55AA
                        if (packet[12] == 0x55 and packet[13] == 0xAA and
                            packet[14] == 0x55 and packet[15] == 0xAA):

                            r = packet[6]
                            g = packet[7]
                            b = packet[8]
                            write_req = packet[9] & 0x01
                            write_req_ack = packet[10] & 0x01
                            data_valid = packet[11] & 0x01

                            debug_info['type'] = 'RGB'
                            debug_info['data1'] = f"RGB: {r:02X} {g:02X} {b:02X}"
                            debug_info['data2'] = f"WR:{write_req} ACK:{write_req_ack}"
                            debug_info['data3'] = f"Valid:{data_valid}"
                            debug_info['raw'] = ' '.join(f'{x:02X}' for x in packet)

                            self.stats['rgb_packets'] += 1
                            self.signals.debug_data_signal.emit(debug_info)

                            offset += 16
                            continue

                elif packet_type == 0x02:  # SDRAM数据包 (32字节)
                    if offset + 32 <= len(data):
                        packet = data[offset:offset+32]

                        # 验证帧尾 0x55AA55AA
                        if (packet[28] == 0x55 and packet[29] == 0xAA and
                            packet[30] == 0x55 and packet[31] == 0xAA):

                            op_type = "写" if packet[6] == 0x57 else "读"  # W=0x57, R=0x52
                            addr = (packet[8] << 24) | (packet[9] << 16) | (packet[10] << 8) | packet[11]
                            data_val = (packet[12] << 24) | (packet[13] << 16) | (packet[14] << 8) | packet[15]
                            wr_en = packet[16] & 0x01
                            rd_en = packet[17] & 0x01

                            debug_info['type'] = f'SDRAM-{op_type}'
                            debug_info['data1'] = f"Addr: 0x{addr:08X}"
                            debug_info['data2'] = f"Data: 0x{data_val:08X}"
                            debug_info['data3'] = f"WR_EN:{wr_en} RD_EN:{rd_en}"
                            debug_info['raw'] = ' '.join(f'{x:02X}' for x in packet[:20]) + '...'  # 只显示前20字节

                            self.stats['sdram_packets'] += 1
                            self.signals.debug_data_signal.emit(debug_info)

                            offset += 32
                            continue

            offset += 1

    def update_debug_table(self, debug_info):
        """更新调试数据表格"""
        self.debug_data_list.append(debug_info)

        # 限制列表长度
        if len(self.debug_data_list) > 500:  # 从1000减少到500
            self.debug_data_list.pop(0)

        # 批量更新表格（减少UI刷新频率）
        if len(self.debug_data_list) % 5 == 0:  # 每5个数据更新一次UI
            self._batch_update_table()

    def _batch_update_table(self):
        """批量更新表格（减少UI刷新）"""
        # 只更新最新的几条记录
        start_index = max(0, len(self.debug_data_list) - 5)

        for i in range(start_index, len(self.debug_data_list)):
            debug_info = self.debug_data_list[i]
            row = self.debug_table.rowCount()
            self.debug_table.insertRow(row)

            self.debug_table.setItem(row, 0, QTableWidgetItem(debug_info['time']))

            type_item = QTableWidgetItem(debug_info['type'])
            if 'RGB' in debug_info['type']:
                type_item.setBackground(QColor(200, 255, 200))
            elif 'SDRAM' in debug_info['type']:
                type_item.setBackground(QColor(200, 200, 255))
            self.debug_table.setItem(row, 1, type_item)

            self.debug_table.setItem(row, 2, QTableWidgetItem(str(debug_info['seq'])))
            self.debug_table.setItem(row, 3, QTableWidgetItem(debug_info['data1']))
            self.debug_table.setItem(row, 4, QTableWidgetItem(debug_info['data2']))
            self.debug_table.setItem(row, 5, QTableWidgetItem(debug_info['data3']))
            self.debug_table.setItem(row, 6, QTableWidgetItem(debug_info['raw']))

        # 自动滚动
        if self.auto_scroll_check.isChecked():
            self.debug_table.scrollToBottom()

        # 限制表格行数
        if self.debug_table.rowCount() > 500:  # 从1000减少到500
            for _ in range(self.debug_table.rowCount() - 500):
                self.debug_table.removeRow(0)

    def clear_debug_table(self):
        """清除调试数据表格"""
        self.debug_table.setRowCount(0)
        self.debug_data_list.clear()
        self.signals.log_signal.emit("已清除调试数据", "info")

    def copy_debug_data(self):
        """复制调试数据到剪贴板"""
        if len(self.debug_data_list) == 0:
            self.signals.log_signal.emit("没有调试数据可复制", "warning")
            return

        # 构建文本格式
        text = "=" * 80 + "\n"
        text += "调试数据日志\n"
        text += f"统计信息: 共 {len(self.debug_data_list)} 条记录\n"
        text += f"RGB包: {self.stats['rgb_packets']}, SDRAM包: {self.stats['sdram_packets']}\n"
        text += "=" * 80 + "\n\n"

        for i, data in enumerate(self.debug_data_list):
            text += f"[{i+1}] {data['time']} | {data['type']:12} | SEQ:{data['seq']:3d} | "
            text += f"{data['data1']:20} | {data['data2']:20} | {data['data3']:20}\n"
            text += f"    原始: {data['raw']}\n\n"

        # 复制到剪贴板
        clipboard = QApplication.clipboard()
        clipboard.setText(text)

        self.signals.log_signal.emit(f"已复制 {len(self.debug_data_list)} 条调试数据到剪贴板", "success")

    def update_stats_display(self):
        """更新统计信息显示 - 包含实时速率"""
        # 计算实时传输速率
        elapsed = time.time() - self.stats['start_time'] if self.stats['start_time'] > 0 else 0
        throughput_mbps = 0
        if elapsed > 0:
            throughput_mbps = (self.stats['sent_bytes'] * 8) / (elapsed * 1_000_000)

        stats_text = (
            f"发送: {self.stats['sent_frames']} 帧 / {self.stats['sent_bytes']//1024} KB"
        )

        if throughput_mbps > 0:
            stats_text += f" / {throughput_mbps:.2f} Mbps"

        stats_text += (
            f" | 接收: {self.stats['recv_packets']} 包 / {self.stats['recv_bytes']//1024} KB | "
            f"RGB: {self.stats['rgb_packets']} | SDRAM: {self.stats['sdram_packets']}"
        )

        self.stats_label.setText(stats_text)

    def append_log(self, message, msg_type="info"):
        """添加日志"""
        timestamp = time.strftime('%H:%M:%S')

        color_map = {
            'info': 'black',
            'success': 'green',
            'error': 'red',
            'warning': 'orange'
        }

        color = color_map.get(msg_type, 'black')

        self.log_text.setTextColor(QColor(color))
        self.log_text.append(f"[{timestamp}] {message}")
        self.log_text.moveCursor(QTextCursor.End)

    def clear_log(self):
        """清除日志"""
        self.log_text.clear()

    def copy_log(self):
        """复制日志到剪贴板"""
        log_content = self.log_text.toPlainText()
        if not log_content:
            self.signals.log_signal.emit("日志为空，无法复制", "warning")
            return

        clipboard = QApplication.clipboard()
        clipboard.setText(log_content)
        self.signals.log_signal.emit("已复制日志到剪贴板", "success")

    def test_send_single_packet(self):
        """测试发送单个数据包（小包，用于调试）"""
        if not self.running or not self.sock:
            self.signals.log_signal.emit("请先连接", "warning")
            return

        try:
            # 发送小测试包：10个像素的RGB数据 (30字节)
            test_data = bytearray()

            # 10个像素，颜色循环：红、绿、蓝、白、黄、青、品红、橙、紫、灰
            test_colors = [
                (255, 0, 0),      # 红
                (0, 255, 0),      # 绿
                (0, 0, 255),      # 蓝
                (255, 255, 255),  # 白
                (255, 255, 0),    # 黄
                (0, 255, 255),    # 青
                (255, 0, 255),    # 品红
                (255, 128, 0),    # 橙
                (128, 0, 255),    # 紫
                (128, 128, 128),  # 灰
            ]

            for r, g, b in test_colors:
                test_data.extend([r, g, b])

            # 发送测试包
            self.sock.sendto(bytes(test_data), (self.target_ip, self.target_port))

            self.stats['sent_frames'] += 1
            self.stats['sent_bytes'] += len(test_data)
            self.update_stats_display()

            self.signals.log_signal.emit(
                f"测试发送: {len(test_data)}字节 (10像素RGB888) -> {self.target_ip}:{self.target_port}",
                "success"
            )

            # 显示发送的数据内容
            hex_str = ' '.join(f'{b:02X}' for b in test_data[:30])
            self.signals.log_signal.emit(f"数据内容: {hex_str}...", "info")

        except Exception as e:
            self.signals.log_signal.emit(f"测试发送失败: {str(e)}", "error")

    def closeEvent(self, event):
        """关闭事件"""
        if self.running:
            self.disconnect()
        event.accept()

def main():
    app = QApplication(sys.argv)
    window = UDPDebugTool()
    window.show()
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()
