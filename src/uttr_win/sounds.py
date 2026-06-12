import sys
import threading
import winsound
from pathlib import Path
from .logger import setup_logger

log = setup_logger("uttr-win.sounds")

if getattr(sys, "frozen", False):
    ASSETS_DIR = Path(sys._MEIPASS) / "assets" / "sounds"
else:
    ASSETS_DIR = Path(__file__).resolve().parent.parent.parent / "assets" / "sounds"

SOUND_MAP = {
    "start": "start.wav",
    "stop": "stop.wav",
    "success": "success.wav",
    "error": "error.wav",
}


def play(sound_name: str, enabled: bool = True) -> None:
    if not enabled:
        return
    wav = ASSETS_DIR / SOUND_MAP.get(sound_name, "")
    if not wav.exists():
        winsound.MessageBeep(winsound.MB_OK)
        return

    def _play():
        try:
            winsound.PlaySound(str(wav), winsound.SND_FILENAME | winsound.SND_NODEFAULT)
        except Exception as e:
            log.warning("Sound playback failed: %s", e)

    threading.Thread(target=_play, daemon=True).start()
