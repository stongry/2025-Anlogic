#!/bin/bash
# 以太网UDP上位机启动脚本

# 脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 切换到程序目录
cd "$SCRIPT_DIR"

# 检查Python是否安装
if ! command -v python3 &> /dev/null; then
    echo "错误: 未找到Python3，请先安装Python3"
    exit 1
fi

# 检查tkinter是否可用
python3 -c "import tkinter" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "错误: tkinter未安装"
    echo "请运行以下命令安装："
    echo "  Ubuntu/Debian: sudo apt-get install python3-tk"
    echo "  Fedora: sudo dnf install python3-tkinter"
    echo "  Arch: sudo pacman -S tk"
    exit 1
fi

# 启动程序
echo "正在启动以太网UDP上位机..."
python3 ethernet_host_gui.py

# 检查退出状态
if [ $? -ne 0 ]; then
    echo "程序异常退出，退出码: $?"
    exit 1
fi
