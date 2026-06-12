import ctypes
import ctypes.wintypes
import threading
from typing import Callable
from .logger import setup_logger

log = setup_logger("uttr-win.hotkey")

user32 = ctypes.windll.user32

MOD_CONTROL = 0x0002
MOD_NOREPEAT = 0x4000

WM_HOTKEY = 0x0312
HOTKEY_ID = 1
VK_SPACE = 0x20


class HotkeyManager:
    def __init__(self):
        self._on_toggle: Callable | None = None
        self._thread: threading.Thread | None = None
        self._thread_id: int | None = None
        self._running = False

    def register(self, on_toggle: Callable) -> None:
        self._on_toggle = on_toggle
        self._running = True
        self._thread = threading.Thread(target=self._message_loop, daemon=True)
        self._thread.start()

    def _message_loop(self) -> None:
        self._thread_id = ctypes.windll.kernel32.GetCurrentThreadId()

        mods = MOD_CONTROL | MOD_NOREPEAT
        if not user32.RegisterHotKey(None, HOTKEY_ID, mods, VK_SPACE):
            error = ctypes.GetLastError()
            log.error(
                "Failed to register Ctrl+Space (error %d). "
                "The hotkey may be in use by another application.",
                error,
            )
            user32.MessageBoxW(
                None,
                f"uttr-win: Failed to register hotkey Ctrl+Space.\n"
                f"Another application may be using it (error {error}).",
                "uttr-win — Hotkey Error",
                0x10,
            )
            return

        log.info("Hotkey registered: Ctrl+Space (toggle recording)")

        msg = ctypes.wintypes.MSG()
        while self._running:
            ret = user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
            if ret <= 0:
                break
            if msg.message == WM_HOTKEY and msg.wParam == HOTKEY_ID:
                if self._running and self._on_toggle:
                    self._on_toggle()

        user32.UnregisterHotKey(None, HOTKEY_ID)
        log.info("Hotkey unregistered")

    def shutdown(self) -> None:
        self._running = False
        if self._thread_id:
            user32.PostThreadMessageW(self._thread_id, 0x0012, 0, 0)  # WM_QUIT
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2)
        self._thread = None
        self._thread_id = None
        log.info("Hotkey manager shut down")
