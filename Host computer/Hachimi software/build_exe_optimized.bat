@echo off
REM ====================================================
REM 使用spec配置文件打包 - 生成更小的exe文件
REM ====================================================

echo ========================================
echo FPGA UDP控制GUI - 高级打包
echo ========================================
echo.

python --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未检测到Python！
    pause
    exit /b 1
)

echo [步骤1/4] 安装依赖...
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
echo.

echo [步骤2/4] 清理旧文件...
if exist "dist" rmdir /s /q dist
if exist "build" rmdir /s /q build
echo.

echo [步骤3/4] 使用spec配置文件打包...
echo 这将生成优化后的exe文件（更小的体积）
echo.
pyinstaller --noconfirm ethernet_host_gui.spec

if errorlevel 1 (
    echo [错误] 打包失败！
    pause
    exit /b 1
)

echo.
echo [步骤4/4] 打包完成！
echo.
echo 生成文件: dist\FPGA_UDP_Control.exe
dir dist\FPGA_UDP_Control.exe | findstr FPGA_UDP_Control.exe
echo.
pause
