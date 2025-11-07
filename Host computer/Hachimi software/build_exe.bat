@echo off
REM ====================================================
REM FPGA以太网UDP控制GUI - Windows EXE打包脚本
REM ====================================================

echo ========================================
echo FPGA UDP控制GUI - 打包工具
echo ========================================
echo.

REM 检查Python是否安装
python --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未检测到Python！请先安装Python 3.7或更高版本
    echo 下载地址: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo [步骤1/4] 检测到Python版本:
python --version
echo.

REM 安装依赖
echo [步骤2/4] 安装依赖包...
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
if errorlevel 1 (
    echo [错误] 依赖安装失败！
    pause
    exit /b 1
)
echo [成功] 依赖包安装完成
echo.

REM 清理旧的打包文件
echo [步骤3/4] 清理旧的打包文件...
if exist "dist" rmdir /s /q dist
if exist "build" rmdir /s /q build
if exist "ethernet_host_gui.spec" del /q ethernet_host_gui.spec
echo [成功] 清理完成
echo.

REM 使用PyInstaller打包
echo [步骤4/4] 开始打包exe文件...
echo 这可能需要几分钟时间，请耐心等待...
echo.

pyinstaller --noconfirm ^
    --onefile ^
    --windowed ^
    --name "FPGA_UDP_Control" ^
    --add-data "anlu_logo_transparent.png;." ^
    --hidden-import "PIL._tkinter_finder" ^
    --hidden-import "numpy" ^
    --hidden-import "cv2" ^
    --hidden-import "serial" ^
    --hidden-import "serial.tools.list_ports" ^
    --collect-all cv2 ^
    --collect-all numpy ^
    ethernet_host_gui.py

if errorlevel 1 (
    echo.
    echo [错误] 打包失败！
    pause
    exit /b 1
)

echo.
echo ========================================
echo [成功] 打包完成！
echo ========================================
echo.
echo 生成的文件位置:
echo   dist\FPGA_UDP_Control.exe
echo.
echo 文件大小:
dir dist\FPGA_UDP_Control.exe | findstr FPGA_UDP_Control.exe
echo.
echo 您可以将 dist\FPGA_UDP_Control.exe 复制到任何Windows电脑上运行
echo 无需安装Python或任何依赖库！
echo.
echo ========================================
pause
