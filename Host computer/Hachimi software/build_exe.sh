#!/bin/bash
# ====================================================
# FPGA以太网UDP控制GUI - Linux/Mac打包脚本
# ====================================================

echo "========================================"
echo "FPGA UDP控制GUI - 打包工具"
echo "========================================"
echo ""

# 检查Python
if ! command -v python3 &> /dev/null; then
    echo "[错误] 未检测到Python3！请先安装Python 3.7或更高版本"
    exit 1
fi

echo "[步骤1/4] 检测到Python版本:"
python3 --version
echo ""

# 安装依赖
echo "[步骤2/4] 安装依赖包..."
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

if [ $? -ne 0 ]; then
    echo "[错误] 依赖安装失败！"
    exit 1
fi
echo "[成功] 依赖包安装完成"
echo ""

# 清理旧文件
echo "[步骤3/4] 清理旧的打包文件..."
rm -rf dist build ethernet_host_gui.spec
echo "[成功] 清理完成"
echo ""

# 打包
echo "[步骤4/4] 开始打包..."
echo "这可能需要几分钟时间，请耐心等待..."
echo ""

pyinstaller --noconfirm \
    --onefile \
    --windowed \
    --name "FPGA_UDP_Control" \
    --add-data "anlu_logo_transparent.png:." \
    --hidden-import "PIL._tkinter_finder" \
    --hidden-import "numpy" \
    --hidden-import "cv2" \
    --hidden-import "serial" \
    --hidden-import "serial.tools.list_ports" \
    --collect-all cv2 \
    --collect-all numpy \
    ethernet_host_gui.py

if [ $? -ne 0 ]; then
    echo ""
    echo "[错误] 打包失败！"
    exit 1
fi

echo ""
echo "========================================"
echo "[成功] 打包完成！"
echo "========================================"
echo ""
echo "生成的文件位置:"
echo "  dist/FPGA_UDP_Control"
echo ""
echo "文件大小:"
ls -lh dist/FPGA_UDP_Control | awk '{print $5, $9}'
echo ""
echo "运行方法:"
echo "  ./dist/FPGA_UDP_Control"
echo ""
echo "或者赋予执行权限后双击运行:"
echo "  chmod +x dist/FPGA_UDP_Control"
echo ""
echo "========================================"
