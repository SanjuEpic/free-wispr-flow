# uttr-win

Windows speech-to-text app. Press Alt+L, speak, text pastes at cursor.

## Stack
- Python 3.11+, pystray, keyboard, sounddevice, faster-whisper
- Pluggable transcription: faster-whisper (default), ONNX Parakeet, NeMo Parakeet

## Project layout
- `src/uttr_win/` — all source code
- `src/uttr_win/transcription/` — provider ABC + implementations
- `assets/` — icon and sounds
- `benchmarks/` — STT provider comparison scripts

## Run
```
pip install -e .
python -m uttr_win.app
```

## Conventions
- No comments unless the WHY is non-obvious
- Keep modules single-responsibility
- All providers implement `TranscriptionProvider` ABC
