import sys
import threading
import tkinter as tk
from tkinter import ttk, messagebox
from typing import Callable

from ..logger import setup_logger
from ..gpu_setup import detect_gpu, check_cuda_libs, install_cuda_packages

log = setup_logger("uttr-win.settings-ui")

MODEL_SIZES = [
    "tiny.en",
    "base.en",
    "small.en (recommended)",
]
DEVICES = ["auto", "cpu", "cuda"]
COMPUTE_TYPES = ["auto", "float16", "int8"]

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
APP_NAME = "uttr-win"


def _get_autostart() -> bool:
    import winreg
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_READ)
        winreg.QueryValueEx(key, APP_NAME)
        winreg.CloseKey(key)
        return True
    except FileNotFoundError:
        return False
    except OSError:
        return False


def _set_autostart(enabled: bool) -> None:
    import winreg
    key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE)
    if enabled:
        exe_path = sys.executable if getattr(sys, "frozen", False) else f'"{sys.executable}" -m uttr_win.app'
        winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, exe_path)
    else:
        try:
            winreg.DeleteValue(key, APP_NAME)
        except FileNotFoundError:
            pass
    winreg.CloseKey(key)


class SettingsWindow:
    """A Toplevel settings window. All methods must run on the main (tkinter)
    thread — the window is a child of the app's persistent hidden root."""

    def __init__(self, parent: tk.Misc, settings, on_reload: Callable):
        self._parent = parent
        self._settings = settings
        self._on_reload = on_reload
        self._win: tk.Toplevel | None = None

    def open(self) -> None:
        if self._win is not None and self._win.winfo_exists():
            self._win.lift()
            self._win.focus_force()
            return
        self._win = tk.Toplevel(self._parent)
        self._win.title("uttr-win Settings")
        self._win.resizable(False, False)
        self._win.attributes("-topmost", True)
        self._win.protocol("WM_DELETE_WINDOW", self._cancel)
        self._build_ui()
        self._center_window()

    def _center_window(self) -> None:
        self._win.update_idletasks()
        w = self._win.winfo_width()
        h = self._win.winfo_height()
        x = (self._win.winfo_screenwidth() - w) // 2
        y = (self._win.winfo_screenheight() - h) // 2
        self._win.geometry(f"+{x}+{y}")

    def _build_ui(self) -> None:
        root = self._win
        root.configure(padx=20, pady=15)

        title = ttk.Label(root, text="uttr-win Settings", font=("Segoe UI", 14, "bold"))
        title.grid(row=0, column=0, columnspan=3, pady=(0, 15), sticky="w")

        row = 1

        # Device
        ttk.Label(root, text="Device:").grid(row=row, column=0, sticky="w", pady=5)
        self._device_var = tk.StringVar(value=self._settings.get("faster_whisper.device", "auto"))
        device_cb = ttk.Combobox(root, textvariable=self._device_var, values=DEVICES, state="readonly", width=18)
        device_cb.grid(row=row, column=1, sticky="w", pady=5, padx=(10, 0))
        row += 1

        # GPU status info
        self._gpu_frame = ttk.LabelFrame(root, text="GPU Status", padding=8)
        self._gpu_frame.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(5, 10))
        self._gpu_status_label = ttk.Label(self._gpu_frame, text="Checking...", wraplength=350)
        self._gpu_status_label.pack(anchor="w")
        self._gpu_action_btn = ttk.Button(self._gpu_frame, text="Install GPU Support", command=self._install_gpu)
        self._gpu_action_btn.pack(anchor="w", pady=(5, 0))
        self._gpu_action_btn.pack_forget()
        self._gpu_progress_label = ttk.Label(self._gpu_frame, text="", wraplength=350, foreground="gray")
        self._gpu_progress_label.pack(anchor="w")
        self._gpu_progress_label.pack_forget()
        threading.Thread(target=self._check_gpu_status, daemon=True).start()
        row += 1

        # Model Size
        ttk.Label(root, text="Model Size:").grid(row=row, column=0, sticky="w", pady=5)
        current_model = self._settings.get("faster_whisper.model", "small.en")
        display_val = next((m for m in MODEL_SIZES if m.startswith(current_model)), MODEL_SIZES[2])
        self._model_var = tk.StringVar(value=display_val)
        model_cb = ttk.Combobox(root, textvariable=self._model_var, values=MODEL_SIZES, state="readonly", width=22)
        model_cb.grid(row=row, column=1, sticky="w", pady=5, padx=(10, 0))
        row += 1

        # Compute Type
        ttk.Label(root, text="Compute Type:").grid(row=row, column=0, sticky="w", pady=5)
        self._compute_var = tk.StringVar(value=self._settings.get("faster_whisper.compute_type", "auto"))
        compute_cb = ttk.Combobox(root, textvariable=self._compute_var, values=COMPUTE_TYPES, state="readonly", width=18)
        compute_cb.grid(row=row, column=1, sticky="w", pady=5, padx=(10, 0))
        row += 1

        # Sounds
        self._sounds_var = tk.BooleanVar(value=self._settings.get("sounds_enabled", True))
        sounds_cb = ttk.Checkbutton(root, text="Enable sounds", variable=self._sounds_var)
        sounds_cb.grid(row=row, column=0, columnspan=3, sticky="w", pady=5)
        row += 1

        # Hotkey (read-only, hardcoded to match hotkey.py registration)
        ttk.Label(root, text="Hotkey:").grid(row=row, column=0, sticky="w", pady=5)
        ttk.Label(root, text="CTRL+SPACE", font=("Segoe UI", 10, "bold")).grid(
            row=row, column=1, sticky="w", pady=5, padx=(10, 0)
        )
        row += 1

        # Start with Windows
        self._autostart_var = tk.BooleanVar(value=_get_autostart())
        autostart_cb = ttk.Checkbutton(root, text="Start with Windows", variable=self._autostart_var)
        autostart_cb.grid(row=row, column=0, columnspan=3, sticky="w", pady=5)
        row += 1

        # Separator
        ttk.Separator(root, orient="horizontal").grid(row=row, column=0, columnspan=3, sticky="ew", pady=10)
        row += 1

        # Buttons
        btn_frame = ttk.Frame(root)
        btn_frame.grid(row=row, column=0, columnspan=3, sticky="e")

        ttk.Button(btn_frame, text="Cancel", command=self._cancel).pack(side="right", padx=(5, 0))
        ttk.Button(btn_frame, text="Save & Reload", command=self._save).pack(side="right")

    def _alive(self) -> bool:
        return self._win is not None and self._win.winfo_exists()

    def _check_gpu_status(self) -> None:
        gpu = detect_gpu()
        cuda_status = check_cuda_libs()
        is_frozen = getattr(sys, "frozen", False)

        def update():
            if not self._alive():
                return
            if not gpu:
                self._gpu_status_label.config(text="No NVIDIA GPU detected. Using CPU.")
                return

            gpu_text = f"{gpu['name']} ({gpu['vram_mb']}MB VRAM, driver {gpu['driver']})"

            if cuda_status.get("ctranslate2_cuda"):
                self._gpu_status_label.config(
                    text=f"{gpu_text}\nCUDA: Ready (auto mode will use GPU when memory available)",
                    foreground="green",
                )
            elif is_frozen:
                self._gpu_status_label.config(
                    text=f"{gpu_text}\nCUDA not available in this runtime. Auto mode will use CPU.",
                    foreground="orange",
                )
            else:
                self._gpu_status_label.config(
                    text=f"{gpu_text}\nCUDA libraries not installed. Click below to enable GPU acceleration.",
                    foreground="orange",
                )
                self._gpu_action_btn.pack(anchor="w", pady=(5, 0))

        if self._alive():
            self._win.after(0, update)

    def _install_gpu(self) -> None:
        self._gpu_action_btn.config(state="disabled", text="Installing...")
        self._gpu_progress_label.pack(anchor="w", pady=(3, 0))

        def do_install():
            def progress(msg):
                if self._alive():
                    self._win.after(0, lambda: self._gpu_progress_label.config(text=msg))

            success = install_cuda_packages(progress_callback=progress)

            def done():
                if not self._alive():
                    return
                if success:
                    self._gpu_status_label.config(
                        text="GPU support installed! Save & Reload to activate.",
                        foreground="green",
                    )
                    self._gpu_action_btn.pack_forget()
                    messagebox.showinfo(
                        "GPU Setup Complete",
                        "CUDA libraries installed successfully.\n\n"
                        "Click 'Save & Reload' to start using GPU acceleration.",
                        parent=self._win,
                    )
                else:
                    self._gpu_action_btn.config(state="normal", text="Retry Install")

            if self._alive():
                self._win.after(0, done)

        threading.Thread(target=do_install, daemon=True).start()

    def _save(self) -> None:
        self._settings.set("faster_whisper.device", self._device_var.get())
        model_val = self._model_var.get().split(" (")[0]
        self._settings.set("faster_whisper.model", model_val)
        self._settings.set("faster_whisper.compute_type", self._compute_var.get())
        self._settings.set("sounds_enabled", self._sounds_var.get())
        _set_autostart(self._autostart_var.get())

        log.info("Settings saved (device=%s, model=%s, compute=%s, sounds=%s, autostart=%s)",
                 self._device_var.get(), self._model_var.get(), self._compute_var.get(),
                 self._sounds_var.get(), self._autostart_var.get())

        self._close()
        self._on_reload()

    def _cancel(self) -> None:
        self._close()

    def _close(self) -> None:
        if self._win is not None:
            self._win.destroy()
            self._win = None
