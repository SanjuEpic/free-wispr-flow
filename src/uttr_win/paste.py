import ctypes
import ctypes.wintypes
import threading
import time
import pyperclip
from .logger import setup_logger

log = setup_logger("uttr-win.paste")

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008
VK_CONTROL = 0x11
VK_V = 0x56
VK_MENU = 0x12
VK_LWIN = 0x5B
VK_RWIN = 0x5C
VK_SPACE = 0x20

SW_RESTORE = 9
SW_SHOW = 5


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", ctypes.wintypes.LONG),
        ("dy", ctypes.wintypes.LONG),
        ("mouseData", ctypes.wintypes.DWORD),
        ("dwFlags", ctypes.wintypes.DWORD),
        ("time", ctypes.wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", ctypes.wintypes.WORD),
        ("wScan", ctypes.wintypes.WORD),
        ("dwFlags", ctypes.wintypes.DWORD),
        ("time", ctypes.wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", ctypes.wintypes.DWORD),
        ("wParamL", ctypes.wintypes.WORD),
        ("wParamH", ctypes.wintypes.WORD),
    ]


class INPUT(ctypes.Structure):
    class _INPUT(ctypes.Union):
        _fields_ = [
            ("mi", MOUSEINPUT),
            ("ki", KEYBDINPUT),
            ("hi", HARDWAREINPUT),
        ]

    _fields_ = [
        ("type", ctypes.wintypes.DWORD),
        ("_input", _INPUT),
    ]


SCAN_CTRL = 0x1D
SCAN_V = 0x2F


def _send_key(vk: int, scan: int = 0, up: bool = False) -> INPUT:
    inp = INPUT(type=INPUT_KEYBOARD)
    inp._input.ki.wVk = vk
    inp._input.ki.wScan = scan
    flags = KEYEVENTF_KEYUP if up else 0
    if scan:
        flags |= KEYEVENTF_SCANCODE
    inp._input.ki.dwFlags = flags
    return inp


def _release_modifiers():
    for vk in (VK_MENU, VK_LWIN, VK_RWIN, VK_SPACE):
        inp = INPUT(type=INPUT_KEYBOARD)
        inp._input.ki.wVk = vk
        inp._input.ki.dwFlags = KEYEVENTF_KEYUP
        inputs = (INPUT * 1)(inp)
        user32.SendInput(1, ctypes.byref(inputs), ctypes.sizeof(INPUT))


def _send_ctrl_v():
    inputs = (INPUT * 4)(
        _send_key(VK_CONTROL, SCAN_CTRL),
        _send_key(VK_V, SCAN_V),
        _send_key(VK_V, SCAN_V, up=True),
        _send_key(VK_CONTROL, SCAN_CTRL, up=True),
    )
    sent = user32.SendInput(4, ctypes.byref(inputs), ctypes.sizeof(INPUT))
    log.info("SendInput returned %d (expected 4)", sent)


def _get_window_title(hwnd: int) -> str:
    buf = ctypes.create_unicode_buffer(256)
    user32.GetWindowTextW(hwnd, buf, 256)
    return buf.value


def get_foreground_window() -> int:
    return user32.GetForegroundWindow()


class ForegroundTracker:
    """Polls the foreground window and remembers the last non-self HWND."""

    def __init__(self):
        self._last_hwnd: int = 0
        self._self_pids: set[int] = set()
        self._running = False
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()

    def start(self) -> None:
        import os
        self._self_pids = {os.getpid()}
        self._running = True
        self._thread = threading.Thread(target=self._poll, daemon=True)
        self._thread.start()
        log.info("ForegroundTracker started (own pid=%s)", self._self_pids)

    def stop(self) -> None:
        self._running = False

    def _poll(self) -> None:
        while self._running:
            hwnd = user32.GetForegroundWindow()
            if hwnd:
                pid = ctypes.wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                if pid.value not in self._self_pids:
                    with self._lock:
                        if hwnd != self._last_hwnd:
                            title = _get_window_title(hwnd)
                            log.debug("Tracked foreground: hwnd=%s pid=%s title='%s'", hwnd, pid.value, title)
                        self._last_hwnd = hwnd
            time.sleep(0.1)

    @property
    def last_hwnd(self) -> int:
        with self._lock:
            return self._last_hwnd


def _force_foreground(hwnd: int) -> bool:
    """Bring hwnd to foreground using the Alt-key trick.

    Windows blocks SetForegroundWindow from background processes. Sending a
    fake Alt press/release makes Windows think we're responding to user input,
    which lifts the restriction.
    """
    if not hwnd or not user32.IsWindow(hwnd):
        log.warning("Target hwnd %s is invalid", hwnd)
        return False

    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, SW_RESTORE)
        time.sleep(0.05)

    fg = user32.GetForegroundWindow()
    if fg == hwnd:
        log.info("Target already in foreground")
        return True

    # The Alt-key trick: press and release Alt to fool the foreground lock
    alt_down = _send_key(VK_MENU)
    alt_up = _send_key(VK_MENU, up=True)
    inputs = (INPUT * 2)(alt_down, alt_up)
    user32.SendInput(2, ctypes.byref(inputs), ctypes.sizeof(INPUT))

    current_thread = kernel32.GetCurrentThreadId()
    fg_thread = user32.GetWindowThreadProcessId(fg, None)
    target_thread = user32.GetWindowThreadProcessId(hwnd, None)

    attached_fg = False
    attached_target = False

    if current_thread != fg_thread:
        attached_fg = bool(user32.AttachThreadInput(current_thread, fg_thread, True))
    if target_thread != fg_thread and current_thread != target_thread:
        attached_target = bool(user32.AttachThreadInput(current_thread, target_thread, True))

    user32.BringWindowToTop(hwnd)
    user32.ShowWindow(hwnd, SW_SHOW)
    result = user32.SetForegroundWindow(hwnd)

    if attached_fg:
        user32.AttachThreadInput(current_thread, fg_thread, False)
    if attached_target:
        user32.AttachThreadInput(current_thread, target_thread, False)

    title = _get_window_title(hwnd)
    if result:
        log.info("SetForegroundWindow succeeded for hwnd=%s '%s'", hwnd, title)
    else:
        log.warning("SetForegroundWindow FAILED for hwnd=%s '%s' (error=%s)",
                     hwnd, title, ctypes.GetLastError())

    return bool(result)


def paste_text(text: str, target_hwnd: int = 0) -> None:
    _release_modifiers()
    time.sleep(0.05)

    pyperclip.copy(text)
    log.info("Clipboard set (%d chars). Target hwnd=%s '%s'",
             len(text), target_hwnd, _get_window_title(target_hwnd) if target_hwnd else "none")

    if target_hwnd:
        _force_foreground(target_hwnd)
        time.sleep(0.2)

        actual_fg = user32.GetForegroundWindow()
        actual_title = _get_window_title(actual_fg)
        log.info("After focus restore: fg hwnd=%s '%s'", actual_fg, actual_title)

    _release_modifiers()
    time.sleep(0.05)
    _send_ctrl_v()
    log.info("Ctrl+V sent")
