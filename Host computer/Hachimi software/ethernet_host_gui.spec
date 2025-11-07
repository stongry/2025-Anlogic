# -*- mode: python ; coding: utf-8 -*-
"""
FPGA UDP控制GUI - PyInstaller配置文件
使用方法: pyinstaller ethernet_host_gui.spec
"""

block_cipher = None

a = Analysis(
    ['ethernet_host_gui.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('anlu_logo_transparent.png', '.'),  # 打包logo图片
    ],
    hiddenimports=[
        'PIL._tkinter_finder',
        'numpy',
        'cv2',
        'serial',
        'serial.tools.list_ports',
        'tkinter',
        'tkinter.ttk',
        'tkinter.scrolledtext',
        'tkinter.filedialog',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'matplotlib',  # 排除不需要的大型库
        'pandas',
        'scipy',
        'IPython',
        'notebook',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='FPGA_UDP_Control',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,  # 启用UPX压缩，减小文件大小
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # 无控制台窗口（GUI程序）
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,  # 如果有.ico文件，可以在这里指定
)
