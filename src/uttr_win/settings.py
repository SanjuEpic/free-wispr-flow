import yaml
from pathlib import Path
from platformdirs import user_data_dir

APP_NAME = "uttr-win"
DATA_DIR = Path(user_data_dir(APP_NAME, appauthor=False))

DEFAULT_SETTINGS = {
    "provider": "faster-whisper",
    "faster_whisper": {
        "model": "small.en",
        "device": "auto",
        "compute_type": "auto",
    },
    "onnx_parakeet": {
        "model_path": "",
    },
    "nemo_parakeet": {
        "model_name": "nvidia/parakeet-tdt-0.6b-v2",
    },
    "hotkey": {
        "combination": "ctrl+space",
    },
    "sounds_enabled": True,
    "history_max": 10,
}


class Settings:
    def __init__(self):
        self._path = DATA_DIR / "settings.yaml"
        self._data: dict = {}
        self.load()

    def load(self):
        if self._path.exists():
            with open(self._path, "r", encoding="utf-8") as f:
                self._data = yaml.safe_load(f) or {}
        for key, val in DEFAULT_SETTINGS.items():
            if key not in self._data:
                self._data[key] = val
            elif isinstance(val, dict):
                for k, v in val.items():
                    if k not in self._data[key]:
                        self._data[key][k] = v

    def save(self):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with open(self._path, "w", encoding="utf-8") as f:
            yaml.dump(self._data, f, default_flow_style=False)

    def get(self, key: str, default=None):
        keys = key.split(".")
        val = self._data
        for k in keys:
            if isinstance(val, dict) and k in val:
                val = val[k]
            else:
                return default
        return val

    def set(self, key: str, value):
        keys = key.split(".")
        d = self._data
        for k in keys[:-1]:
            if k not in d or not isinstance(d[k], dict):
                d[k] = {}
            d = d[k]
        d[keys[-1]] = value
        self.save()
