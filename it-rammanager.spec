# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_submodules

block_cipher = None

hiddenimports = collect_submodules('psutil')


a = Analysis(
    ['qt_app/main.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
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
    name='IT RAM Manager',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
)

app = BUNDLE(
    exe,
    name='IT RAM Manager.app',
    icon=None,  # set to a .icns path if available
    bundle_identifier='com.it.rammanager',
    info_plist={
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '11.0',
        'NSHumanReadableCopyright': '© 2025 IT',
    },
)


