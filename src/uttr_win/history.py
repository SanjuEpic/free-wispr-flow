import json
import threading
import uuid
from datetime import datetime, timezone
from .settings import DATA_DIR
from .logger import setup_logger

log = setup_logger("uttr-win.history")

HISTORY_PATH = DATA_DIR / "history.json"
_file_lock = threading.Lock()


def _load() -> list[dict]:
    if HISTORY_PATH.exists():
        try:
            return json.loads(HISTORY_PATH.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return []
    return []


def _save(entries: list[dict]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    HISTORY_PATH.write_text(json.dumps(entries, indent=2, ensure_ascii=False), encoding="utf-8")


def add(text: str, max_entries: int = 10) -> None:
    with _file_lock:
        entries = _load()
        entries.append({
            "id": str(uuid.uuid4()),
            "text": text,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })
        if len(entries) > max_entries:
            entries = entries[-max_entries:]
        _save(entries)
    log.info("History entry added (%d total)", len(entries))


def get_all() -> list[dict]:
    return _load()


def clear() -> None:
    _save([])
    log.info("History cleared")
