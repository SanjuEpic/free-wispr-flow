"""GPU setup utility — detects NVIDIA GPU and installs CUDA dependencies."""

import subprocess
import sys
from .logger import setup_logger

log = setup_logger("uttr-win.gpu-setup")

CUDA_PACKAGES = [
    "nvidia-cublas-cu12",
    "nvidia-cudnn-cu12",
]


def detect_gpu() -> dict:
    """Return GPU info dict or None if no NVIDIA GPU."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,driver_version",
             "--format=csv,noheader"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(", ")
            return {
                "name": parts[0] if len(parts) > 0 else "Unknown",
                "vram_mb": int(parts[1].replace(" MiB", "")) if len(parts) > 1 else 0,
                "driver": parts[2] if len(parts) > 2 else "Unknown",
            }
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    return None


def check_cuda_libs() -> dict:
    """Check which CUDA packages are installed."""
    status = {}
    for pkg in CUDA_PACKAGES:
        module_name = pkg.replace("-", "_").replace("nvidia_", "nvidia.")
        try:
            __import__(module_name.rsplit("_", 1)[0])
            status[pkg] = True
        except ImportError:
            status[pkg] = False

    try:
        import ctranslate2
        status["ctranslate2_cuda"] = "float16" in ctranslate2.get_supported_compute_types("cuda")
    except Exception:
        status["ctranslate2_cuda"] = False

    return status


def install_cuda_packages(progress_callback=None) -> bool:
    """Install CUDA pip packages. Returns True on success."""
    try:
        if progress_callback:
            progress_callback("Installing CUDA libraries (this may take a few minutes)...")

        cmd = [sys.executable, "-m", "pip", "install"] + CUDA_PACKAGES
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

        if result.returncode != 0:
            log.error("CUDA package install failed: %s", result.stderr[-500:])
            if progress_callback:
                progress_callback(f"Installation failed: {result.stderr[-200:]}")
            return False

        if progress_callback:
            progress_callback("Reinstalling CTranslate2 for CUDA support...")

        cmd2 = [sys.executable, "-m", "pip", "install", "ctranslate2", "--force-reinstall"]
        result2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=600)

        if result2.returncode != 0:
            log.error("CTranslate2 reinstall failed: %s", result2.stderr[-500:])
            if progress_callback:
                progress_callback(f"CTranslate2 reinstall failed: {result2.stderr[-200:]}")
            return False

        if progress_callback:
            progress_callback("GPU setup complete! Restart uttr-win to use CUDA.")
        log.info("CUDA packages installed successfully")
        return True

    except subprocess.TimeoutExpired:
        log.error("CUDA package install timed out")
        if progress_callback:
            progress_callback("Installation timed out. Try running manually: pip install nvidia-cublas-cu12 nvidia-cudnn-cu12")
        return False
    except Exception as e:
        log.error("CUDA install error: %s", e)
        if progress_callback:
            progress_callback(f"Error: {e}")
        return False
