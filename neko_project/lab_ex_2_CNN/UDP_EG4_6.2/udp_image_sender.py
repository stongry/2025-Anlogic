"""
UDP Image Sender - PyQt5 GUI Application
Generates test images and sends them via UDP to FPGA
Image size: 80x100 pixels
"""

import sys
import socket
import struct
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                             QHBoxLayout, QPushButton, QLabel, QLineEdit,
                             QComboBox, QSpinBox, QGroupBox, QTextEdit, QColorDialog)
from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PyQt5.QtGui import QImage, QPixmap, QPainter, QColor
from PIL import Image
import numpy as np
import time

# Image dimensions
IMG_WIDTH = 80
IMG_HEIGHT = 100


class ImageGenerator:
    """Generate various test patterns for 80x100 images"""

    @staticmethod
    def solid_color(color):
        """Generate solid color image"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT), color)
        return img

    @staticmethod
    def horizontal_gradient(color1, color2):
        """Generate horizontal gradient"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT))
        pixels = img.load()

        for y in range(IMG_HEIGHT):
            for x in range(IMG_WIDTH):
                ratio = x / (IMG_WIDTH - 1)
                r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
                g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
                b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
                pixels[x, y] = (r, g, b)

        return img

    @staticmethod
    def vertical_gradient(color1, color2):
        """Generate vertical gradient"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT))
        pixels = img.load()

        for y in range(IMG_HEIGHT):
            ratio = y / (IMG_HEIGHT - 1)
            r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
            g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
            b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
            for x in range(IMG_WIDTH):
                pixels[x, y] = (r, g, b)

        return img

    @staticmethod
    def checkerboard(color1, color2, square_size=10):
        """Generate checkerboard pattern"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT))
        pixels = img.load()

        for y in range(IMG_HEIGHT):
            for x in range(IMG_WIDTH):
                if ((x // square_size) + (y // square_size)) % 2 == 0:
                    pixels[x, y] = color1
                else:
                    pixels[x, y] = color2

        return img

    @staticmethod
    def stripes_horizontal(color1, color2, stripe_width=10):
        """Generate horizontal stripes"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT))
        pixels = img.load()

        for y in range(IMG_HEIGHT):
            color = color1 if (y // stripe_width) % 2 == 0 else color2
            for x in range(IMG_WIDTH):
                pixels[x, y] = color

        return img

    @staticmethod
    def stripes_vertical(color1, color2, stripe_width=10):
        """Generate vertical stripes"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT))
        pixels = img.load()

        for x in range(IMG_WIDTH):
            color = color1 if (x // stripe_width) % 2 == 0 else color2
            for y in range(IMG_HEIGHT):
                pixels[x, y] = color

        return img

    @staticmethod
    def rgb_bars():
        """Generate RGB color bars"""
        img = Image.new('RGB', (IMG_WIDTH, IMG_HEIGHT))
        pixels = img.load()

        colors = [
            (255, 255, 255),  # White
            (255, 255, 0),    # Yellow
            (0, 255, 255),    # Cyan
            (0, 255, 0),      # Green
            (255, 0, 255),    # Magenta
            (255, 0, 0),      # Red
            (0, 0, 255),      # Blue
            (0, 0, 0)         # Black
        ]

        bar_width = IMG_WIDTH // len(colors)

        for x in range(IMG_WIDTH):
            color_idx = min(x // bar_width, len(colors) - 1)
            for y in range(IMG_HEIGHT):
                pixels[x, y] = colors[color_idx]

        return img


class UDPSenderThread(QThread):
    """Thread for sending UDP packets"""
    progress = pyqtSignal(str)
    finished = pyqtSignal(bool, str)

    def __init__(self, image, target_ip, target_port):
        super().__init__()
        self.image = image
        self.target_ip = target_ip
        self.target_port = target_port
        self.running = True

    def run(self):
        try:
            # Create UDP socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

            # Convert image to pixel data
            pixels = list(self.image.getdata())
            total_pixels = len(pixels)

            self.progress.emit(f"开始发送 {total_pixels} 个像素...")

            # Send each pixel
            for idx, (r, g, b) in enumerate(pixels):
                if not self.running:
                    self.progress.emit("发送已取消")
                    self.finished.emit(False, "发送已取消")
                    return

                # Format: f1 + address(4 hex) + rgb(6 hex)
                # Example: f10000ff0000 (address 0x0000, color 0xff0000)
                address = f"{idx:04x}"
                rgb_hex = f"{r:02x}{g:02x}{b:02x}"
                packet_data = f"f1{address}{rgb_hex}"

                # Convert hex string to bytes
                packet_bytes = bytes.fromhex(packet_data)

                # Send UDP packet
                sock.sendto(packet_bytes, (self.target_ip, self.target_port))

                # Progress update every 100 pixels
                if idx % 100 == 0:
                    progress_pct = (idx / total_pixels) * 100
                    self.progress.emit(f"发送进度: {idx}/{total_pixels} ({progress_pct:.1f}%)")

                # Small delay to avoid overwhelming the network
                time.sleep(0.0001)

            sock.close()
            self.progress.emit(f"发送完成！共发送 {total_pixels} 个像素")
            self.finished.emit(True, "发送成功")

        except Exception as e:
            self.progress.emit(f"错误: {str(e)}")
            self.finished.emit(False, str(e))

    def stop(self):
        self.running = False


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.current_image = None
        self.sender_thread = None
        self.color1 = (255, 0, 0)  # Red
        self.color2 = (0, 0, 255)  # Blue

        self.init_ui()
        self.generate_default_image()

    def init_ui(self):
        self.setWindowTitle('UDP Image Sender - 80x100')
        self.setGeometry(100, 100, 900, 700)

        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        # Main layout
        main_layout = QHBoxLayout()
        central_widget.setLayout(main_layout)

        # Left panel - Controls
        left_panel = QVBoxLayout()
        main_layout.addLayout(left_panel, 1)

        # Right panel - Preview
        right_panel = QVBoxLayout()
        main_layout.addLayout(right_panel, 1)

        # === Network Settings ===
        network_group = QGroupBox("网络设置")
        network_layout = QVBoxLayout()

        ip_layout = QHBoxLayout()
        ip_layout.addWidget(QLabel("目标IP:"))
        self.ip_input = QLineEdit("192.168.240.1")
        ip_layout.addWidget(self.ip_input)
        network_layout.addLayout(ip_layout)

        port_layout = QHBoxLayout()
        port_layout.addWidget(QLabel("目标端口:"))
        self.port_input = QSpinBox()
        self.port_input.setRange(1, 65535)
        self.port_input.setValue(1)
        port_layout.addWidget(self.port_input)
        network_layout.addLayout(port_layout)

        network_group.setLayout(network_layout)
        left_panel.addWidget(network_group)

        # === Pattern Selection ===
        pattern_group = QGroupBox("图案选择")
        pattern_layout = QVBoxLayout()

        self.pattern_combo = QComboBox()
        self.pattern_combo.addItems([
            "纯色",
            "水平渐变",
            "垂直渐变",
            "棋盘格",
            "水平条纹",
            "垂直条纹",
            "RGB彩条"
        ])
        self.pattern_combo.currentIndexChanged.connect(self.on_pattern_changed)
        pattern_layout.addWidget(self.pattern_combo)

        # Color selection
        color_layout = QHBoxLayout()
        self.color1_btn = QPushButton("颜色1")
        self.color1_btn.clicked.connect(lambda: self.choose_color(1))
        self.color1_btn.setStyleSheet(f"background-color: rgb{self.color1}")
        color_layout.addWidget(self.color1_btn)

        self.color2_btn = QPushButton("颜色2")
        self.color2_btn.clicked.connect(lambda: self.choose_color(2))
        self.color2_btn.setStyleSheet(f"background-color: rgb{self.color2}")
        color_layout.addWidget(self.color2_btn)
        pattern_layout.addLayout(color_layout)

        # Pattern size
        size_layout = QHBoxLayout()
        size_layout.addWidget(QLabel("图案大小:"))
        self.size_spin = QSpinBox()
        self.size_spin.setRange(1, 50)
        self.size_spin.setValue(10)
        self.size_spin.valueChanged.connect(self.generate_image)
        size_layout.addWidget(self.size_spin)
        pattern_layout.addLayout(size_layout)

        pattern_group.setLayout(pattern_layout)
        left_panel.addWidget(pattern_group)

        # === Action Buttons ===
        action_group = QGroupBox("操作")
        action_layout = QVBoxLayout()

        self.generate_btn = QPushButton("生成图像")
        self.generate_btn.clicked.connect(self.generate_image)
        action_layout.addWidget(self.generate_btn)

        self.send_btn = QPushButton("发送图像")
        self.send_btn.clicked.connect(self.send_image)
        action_layout.addWidget(self.send_btn)

        self.save_btn = QPushButton("保存图像")
        self.save_btn.clicked.connect(self.save_image)
        action_layout.addWidget(self.save_btn)

        action_group.setLayout(action_layout)
        left_panel.addWidget(action_group)

        # === Status Log ===
        log_group = QGroupBox("状态日志")
        log_layout = QVBoxLayout()

        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setMaximumHeight(200)
        log_layout.addWidget(self.log_text)

        log_group.setLayout(log_layout)
        left_panel.addWidget(log_group)

        left_panel.addStretch()

        # === Image Preview ===
        preview_group = QGroupBox("图像预览 (80x100)")
        preview_layout = QVBoxLayout()

        self.preview_label = QLabel()
        self.preview_label.setAlignment(Qt.AlignCenter)
        self.preview_label.setMinimumSize(400, 500)
        self.preview_label.setStyleSheet("border: 1px solid black; background-color: white;")
        preview_layout.addWidget(self.preview_label)

        # Image info
        self.info_label = QLabel("图像尺寸: 80x100 像素")
        self.info_label.setAlignment(Qt.AlignCenter)
        preview_layout.addWidget(self.info_label)

        preview_group.setLayout(preview_layout)
        right_panel.addWidget(preview_group)

        self.log("程序启动成功")
        self.log(f"图像尺寸: {IMG_WIDTH}x{IMG_HEIGHT}")

    def log(self, message):
        """Add message to log"""
        timestamp = time.strftime("%H:%M:%S")
        self.log_text.append(f"[{timestamp}] {message}")

    def choose_color(self, color_num):
        """Open color picker dialog"""
        if color_num == 1:
            initial_color = QColor(*self.color1)
        else:
            initial_color = QColor(*self.color2)

        color = QColorDialog.getColor(initial_color, self, "选择颜色")

        if color.isValid():
            rgb = (color.red(), color.green(), color.blue())
            if color_num == 1:
                self.color1 = rgb
                self.color1_btn.setStyleSheet(f"background-color: rgb{rgb}")
            else:
                self.color2 = rgb
                self.color2_btn.setStyleSheet(f"background-color: rgb{rgb}")

            self.generate_image()

    def on_pattern_changed(self):
        """Handle pattern selection change"""
        pattern = self.pattern_combo.currentText()

        # Enable/disable color buttons based on pattern
        if pattern == "RGB彩条":
            self.color1_btn.setEnabled(False)
            self.color2_btn.setEnabled(False)
            self.size_spin.setEnabled(False)
        elif pattern == "纯色":
            self.color1_btn.setEnabled(True)
            self.color2_btn.setEnabled(False)
            self.size_spin.setEnabled(False)
        elif pattern in ["水平渐变", "垂直渐变"]:
            self.color1_btn.setEnabled(True)
            self.color2_btn.setEnabled(True)
            self.size_spin.setEnabled(False)
        else:
            self.color1_btn.setEnabled(True)
            self.color2_btn.setEnabled(True)
            self.size_spin.setEnabled(True)

        self.generate_image()

    def generate_default_image(self):
        """Generate default test image"""
        self.current_image = ImageGenerator.rgb_bars()
        self.update_preview()
        self.log("生成默认RGB彩条图像")

    def generate_image(self):
        """Generate image based on current settings"""
        pattern = self.pattern_combo.currentText()
        size = self.size_spin.value()

        try:
            if pattern == "纯色":
                self.current_image = ImageGenerator.solid_color(self.color1)
            elif pattern == "水平渐变":
                self.current_image = ImageGenerator.horizontal_gradient(self.color1, self.color2)
            elif pattern == "垂直渐变":
                self.current_image = ImageGenerator.vertical_gradient(self.color1, self.color2)
            elif pattern == "棋盘格":
                self.current_image = ImageGenerator.checkerboard(self.color1, self.color2, size)
            elif pattern == "水平条纹":
                self.current_image = ImageGenerator.stripes_horizontal(self.color1, self.color2, size)
            elif pattern == "垂直条纹":
                self.current_image = ImageGenerator.stripes_vertical(self.color1, self.color2, size)
            elif pattern == "RGB彩条":
                self.current_image = ImageGenerator.rgb_bars()

            self.update_preview()
            self.log(f"生成图像: {pattern}")

        except Exception as e:
            self.log(f"生成图像失败: {str(e)}")

    def update_preview(self):
        """Update image preview"""
        if self.current_image:
            # Convert PIL Image to QPixmap
            img_array = np.array(self.current_image)
            height, width, channel = img_array.shape
            bytes_per_line = 3 * width
            q_image = QImage(img_array.data, width, height, bytes_per_line, QImage.Format_RGB888)

            # Scale up for better visibility
            pixmap = QPixmap.fromImage(q_image)
            scaled_pixmap = pixmap.scaled(400, 500, Qt.KeepAspectRatio, Qt.FastTransformation)

            self.preview_label.setPixmap(scaled_pixmap)

    def send_image(self):
        """Send image via UDP"""
        if not self.current_image:
            self.log("错误: 没有可发送的图像")
            return

        if self.sender_thread and self.sender_thread.isRunning():
            self.log("警告: 正在发送中，请等待...")
            return

        target_ip = self.ip_input.text()
        target_port = self.port_input.value()

        self.log(f"开始发送图像到 {target_ip}:{target_port}")

        # Create and start sender thread
        self.sender_thread = UDPSenderThread(self.current_image, target_ip, target_port)
        self.sender_thread.progress.connect(self.log)
        self.sender_thread.finished.connect(self.on_send_finished)
        self.sender_thread.start()

        self.send_btn.setEnabled(False)

    def on_send_finished(self, success, message):
        """Handle send completion"""
        self.send_btn.setEnabled(True)
        if success:
            self.log("✓ 发送成功")
        else:
            self.log(f"✗ 发送失败: {message}")

    def save_image(self):
        """Save current image to file"""
        if not self.current_image:
            self.log("错误: 没有可保存的图像")
            return

        try:
            filename = f"test_image_{time.strftime('%Y%m%d_%H%M%S')}.png"
            self.current_image.save(filename)
            self.log(f"图像已保存: {filename}")
        except Exception as e:
            self.log(f"保存失败: {str(e)}")


def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == '__main__':
    main()
