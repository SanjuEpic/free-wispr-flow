# -*- mode: python ; coding: utf-8 -*-
import os
import sys
from pathlib import Path
from PyInstaller.utils.hooks import collect_all, collect_data_files

gpu_build = os.environ.get("UTTR_GPU", "0") == "1"

block_cipher = None

# onnxruntime (CPU) powers the Silero VAD filter used during transcription.
# collect_all grabs its DLLs + data so the frozen exe can run VAD.
ort_datas, ort_binaries, ort_hidden = collect_all("onnxruntime")
# faster_whisper ships the Silero VAD model under assets/ — bundle it too.
fw_assets = collect_data_files("faster_whisper")

a = Analysis(
    ["launcher.py"],
    pathex=["src"],
    binaries=ort_binaries,
    datas=[
        ("assets/logo.png", "assets"),
        ("assets/sounds", "assets/sounds"),
    ] + ort_datas + fw_assets,
    hiddenimports=[
        "faster_whisper",
        "ctranslate2",
        "sounddevice",
        "_sounddevice_data",
        "pystray._win32",
        "pyperclip",
        "PIL",
        "yaml",
        "platformdirs",
        "scipy.io.wavfile",
    ] + ort_hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "matplotlib", "IPython", "jupyter", "notebook", "tkinter.test",
        "pytest", "py", "pygments", "pydantic",
    ],
    noarchive=False,
)

if gpu_build:
    # Only bundle CUDA DLLs that CTranslate2 actually loads
    NEEDED_DLLS = {
        "cublas64_12.dll", "cublasLt64_12.dll",
        "cudnn64_9.dll", "cudnn_ops64_9.dll", "cudnn_cnn64_9.dll",
        "cudnn_graph64_9.dll",
    }
    for pkg in ["nvidia.cublas", "nvidia.cudnn"]:
        try:
            mod = __import__(pkg, fromlist=[""])
            for base in mod.__path__:
                for d in [os.path.join(base, "bin"), os.path.join(base, "lib")]:
                    if os.path.isdir(d):
                        for f in os.listdir(d):
                            if f in NEEDED_DLLS:
                                a.binaries.append((f, os.path.join(d, f), "BINARY"))
        except ImportError:
            pass
else:
    a.excludes.extend(["nvidia", "nvidia.cublas", "nvidia.cudnn", "nvidia.cuda_nvrtc"])

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="uttr-win",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    icon="assets/logo.png",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="uttr-win",
)
