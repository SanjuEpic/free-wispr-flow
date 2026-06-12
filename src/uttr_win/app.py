import argparse
import os
import sys
import enum
import threading
import ctypes
from pathlib import Path

from PIL import Image
import pystray

from .audio import AudioRecorder
from .hotkey import HotkeyManager
from .paste import paste_text, ForegroundTracker
from .settings import Settings
from .transcription import get_provider, TranscriptionProvider
from .logger import setup_logger
from .ui.settings_window import SettingsWindow
from .ui.history_window import HistoryWindow
from . import sounds, history

log = setup_logger("uttr-win.app")

if getattr(sys, "frozen", False):
    ICON_PATH = Path(sys._MEIPASS) / "assets" / "logo.png"
else:
    ICON_PATH = Path(__file__).resolve().parent.parent.parent / "assets" / "logo.png"
PROCESSING_TIMEOUT_S = 120

MODEL_CHOICES = {
    "1": "faster-whisper",
    "2": "onnx-parakeet",
    "3": "nemo-parakeet",
}


class AppState(enum.Enum):
    IDLE = "idle"
    LOADING = "loading"
    RECORDING = "recording"
    PROCESSING = "processing"


def _acquire_single_instance() -> bool:
    kernel32 = ctypes.windll.kernel32
    mutex = kernel32.CreateMutexW(None, True, "Global\\uttr-win-single-instance")
    if ctypes.GetLastError() == 183:
        if mutex:
            kernel32.CloseHandle(mutex)
        return False
    return True


class App:
    def __init__(self, provider_id: str | None = None, model_size: str | None = None):
        self._state = AppState.IDLE
        self._lock = threading.Lock()
        self._settings = Settings()
        self._recorder = AudioRecorder()
        self._hotkey = HotkeyManager()
        self._provider: TranscriptionProvider | None = None
        self._icon: pystray.Icon | None = None
        self._provider_override = provider_id
        self._model_size_override = model_size
        self._fg_tracker = ForegroundTracker()
        self._target_hwnd: int = 0
        self._settings_window: SettingsWindow | None = None

    def run(self) -> None:
        log.info("uttr-win starting")
        self._fg_tracker.start()
        self._hotkey.register(on_toggle=self._on_toggle)

        image = self._load_icon()
        menu = pystray.Menu(
            pystray.MenuItem("uttr-win", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                lambda _: f"Status: {self._state.value.title()} | {self._provider.name if self._provider else 'Loading...'}",
                None,
                enabled=False,
            ),
            pystray.MenuItem(
                lambda _: "Ctrl+Space: toggle recording",
                None,
                enabled=False,
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("History", self._open_history),
            pystray.MenuItem("Settings", self._open_settings),
            pystray.MenuItem("Quit", self._quit),
        )
        self._icon = pystray.Icon("uttr-win", image, "uttr-win", menu)

        with self._lock:
            self._state = AppState.LOADING
        threading.Thread(target=self._load_provider, daemon=True).start()

        log.info("Tray icon ready — Ctrl+Space to toggle recording")
        self._icon.run()

    def _load_icon(self) -> Image.Image:
        if ICON_PATH.exists():
            return Image.open(ICON_PATH).resize((64, 64))
        return Image.new("RGB", (64, 64), color=(45, 120, 220))

    def _update_tray(self) -> None:
        if self._icon:
            self._icon.update_menu()

    def _load_provider(self) -> None:
        provider_id = self._provider_override or self._settings.get("provider", "faster-whisper")
        log.info("Loading transcription provider: %s", provider_id)

        settings_data = dict(self._settings._data)
        if self._model_size_override and provider_id == "faster-whisper":
            settings_data.setdefault("faster_whisper", {})["model"] = self._model_size_override

        try:
            self._provider = get_provider(provider_id, settings_data)
            self._provider.prepare()
            log.info("Provider ready: %s", self._provider.name)
        except NotImplementedError:
            log.warning("Provider %s not yet implemented — falling back to faster-whisper", provider_id)
            self._provider = get_provider("faster-whisper", settings_data)
            self._provider.prepare()
        except Exception as e:
            log.error("Failed to load provider: %s", e)
            self._provider = None
        finally:
            with self._lock:
                if self._state == AppState.LOADING:
                    self._state = AppState.IDLE
            self._update_tray()
            if self._icon and self._provider:
                try:
                    self._icon.notify(
                        "Ready! Press Ctrl+Space to start recording.",
                        "uttr-win",
                    )
                except Exception:
                    pass

    def _on_toggle(self) -> None:
        with self._lock:
            if self._state == AppState.IDLE:
                self._target_hwnd = self._fg_tracker.last_hwnd
                self._state = AppState.RECORDING
                self._recorder.start()
                sounds.play("start", self._settings.get("sounds_enabled", True))
                log.info("State -> RECORDING (target hwnd=%s)", self._target_hwnd)
                self._update_tray()
                return
            elif self._state == AppState.RECORDING:
                self._state = AppState.PROCESSING
                target = self._target_hwnd
            elif self._state == AppState.LOADING:
                log.info("Model still loading, please wait")
                return
            else:
                return

        # Outside lock: stop recording, transcribe
        sounds.play("stop", self._settings.get("sounds_enabled", True))
        audio_path = self._recorder.stop()
        self._update_tray()
        log.info("State -> PROCESSING")

        if not audio_path:
            log.warning("No audio captured")
            with self._lock:
                self._state = AppState.IDLE
            self._update_tray()
            return

        t = threading.Thread(target=self._transcribe, args=(audio_path, target), daemon=True)
        t.start()
        threading.Thread(target=self._processing_watchdog, args=(t,), daemon=True).start()

    def _processing_watchdog(self, transcribe_thread: threading.Thread) -> None:
        transcribe_thread.join(timeout=PROCESSING_TIMEOUT_S)
        if transcribe_thread.is_alive():
            log.error("Transcription timed out after %ds", PROCESSING_TIMEOUT_S)
            with self._lock:
                if self._state == AppState.PROCESSING:
                    self._state = AppState.IDLE
            self._update_tray()
            sounds.play("error", self._settings.get("sounds_enabled", True))

    def _transcribe(self, audio_path: str, target_hwnd: int) -> None:
        try:
            if not self._provider:
                log.error("No transcription provider available")
                sounds.play("error", self._settings.get("sounds_enabled", True))
                return

            text = self._provider.transcribe(audio_path)
            if text.strip():
                paste_text(text.strip(), target_hwnd=target_hwnd)
                history.add(text.strip(), self._settings.get("history_max", 10))
                sounds.play("success", self._settings.get("sounds_enabled", True))
                log.info("Transcription complete (%d chars): %s", len(text), text[:200])
            else:
                log.warning("Empty transcription result")
                sounds.play("error", self._settings.get("sounds_enabled", True))
        except Exception as e:
            log.error("Transcription failed: %s", e)
            sounds.play("error", self._settings.get("sounds_enabled", True))
        finally:
            with self._lock:
                self._state = AppState.IDLE
            self._update_tray()
            try:
                os.unlink(audio_path)
            except OSError:
                pass

    def _open_history(self, icon: pystray.Icon, item) -> None:
        HistoryWindow().open()

    def _open_settings(self, icon: pystray.Icon, item) -> None:
        self._settings_window = SettingsWindow(self._settings, on_reload=self._reload_provider)
        self._settings_window.open()

    def _reload_provider(self) -> None:
        with self._lock:
            if self._state == AppState.RECORDING or self._state == AppState.PROCESSING:
                log.warning("Cannot reload provider while recording/processing")
                return
            self._state = AppState.LOADING
        self._provider_override = None
        self._model_size_override = None
        self._update_tray()
        threading.Thread(target=self._load_provider, daemon=True).start()

    def _quit(self, icon: pystray.Icon, item) -> None:
        log.info("Shutting down")
        self._fg_tracker.stop()
        self._hotkey.shutdown()
        if self._recorder.is_recording:
            self._recorder.stop()
        icon.stop()


def main():
    parser = argparse.ArgumentParser(description="uttr-win: local speech-to-text for Windows")
    parser.add_argument(
        "-model",
        choices=["1", "2", "3"],
        default=None,
        help="STT provider: 1=faster-whisper, 2=onnx-parakeet, 3=nemo-parakeet",
    )
    parser.add_argument(
        "-size",
        choices=["tiny.en", "base.en", "small.en", "medium.en", "large-v3-turbo",
                 "distil-large-v3", "distil-medium.en"],
        default=None,
        help="Whisper model size (only for faster-whisper). Smaller = faster, larger = more accurate",
    )
    args = parser.parse_args()

    provider_id = MODEL_CHOICES.get(args.model) if args.model else None

    if not _acquire_single_instance():
        print("uttr-win is already running.")
        sys.exit(1)

    app = App(provider_id=provider_id, model_size=args.size)
    app.run()


if __name__ == "__main__":
    main()
