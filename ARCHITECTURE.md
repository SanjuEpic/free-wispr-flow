# uttr-win — Architecture

A high-level map of how speech becomes pasted text. Read this first if you're
trying to understand "what does what" without diving into every file.

## The one-sentence version

You press **Ctrl+Space**, speak, press **Ctrl+Space** again — the app records your
mic, runs it through a local Whisper model on your GPU/CPU, and pastes the
resulting text into whatever window your cursor was in.

## End-to-end flow

```
                              ┌─────────────────────────────┐
                              │           YOU               │
                              │  (mic + the active window)  │
                              └──────────────┬──────────────┘
                                             │ press Ctrl+Space
                                             ▼
   ┌───────────────────────────────────────────────────────────────────────┐
   │                            uttr-win (tray app)                          │
   │                                                                         │
   │   hotkey.py ──────────► app.py (state machine) ◄──────── sounds.py      │
   │   listens for           IDLE→RECORDING→PROCESSING        plays pop/     │
   │   Ctrl+Space            →IDLE                            chime/error     │
   │       │                      │                                          │
   │       │  toggle              │ start/stop                               │
   │       ▼                      ▼                                          │
   │   (1) START            audio.py                                         │
   │       captures the     records mic to a temp .wav (16kHz mono)          │
   │       active window    + 0.6s tail buffer so trailing words aren't cut  │
   │       via paste.py's        │                                           │
   │       ForegroundTracker     ▼                                           │
   │                        transcription/ (provider abstraction)            │
   │                        faster_whisper_provider.py                       │
   │                        loads Whisper model on CUDA (auto-falls          │
   │                        back to CPU), returns text                       │
   │                             │                                           │
   │                             ▼                                           │
   │                        paste.py                                         │
   │                        1. copy text to clipboard (pyperclip)            │
   │                        2. refocus the original window                   │
   │                        3. send Ctrl+V via Win32 SendInput               │
   │                             │                                           │
   │                             ├──► history.py  (saves last 10 to JSON)    │
   │                             └──► sounds.py    (success chime)           │
   └─────────────────────────────┬───────────────────────────────────────────┘
                                 │ Ctrl+V
                                 ▼
                    ┌─────────────────────────────┐
                    │  Your target window         │
                    │  (Notepad, VS Code, Chrome…)│
                    │  → transcribed text appears │
                    └─────────────────────────────┘
```

## The state machine (app.py)

The whole app is driven by four states. Each Ctrl+Space press moves it forward.

```
   IDLE ──Ctrl+Space──► RECORDING ──Ctrl+Space──► PROCESSING ──(done)──► IDLE
    ▲                    (mic open,                (transcribe +            │
    │                     start sound)              paste + sounds)         │
    └──────────────────────────────────────────────────────────────────────┘

   LOADING  (only at startup / after Settings reload — model is loading;
             hotkey presses are ignored until it becomes IDLE)
```

## Who does what (file responsibilities)

| File | Responsibility |
|------|----------------|
| `launcher.py` | PyInstaller entry point. Just calls `uttr_win.app.main()`. Exists because PyInstaller can't run a module with relative imports directly. |
| `app.py` | **The brain.** Tray icon, menu (History/Settings/Quit), the IDLE→RECORDING→PROCESSING state machine, wiring every other module together. |
| `hotkey.py` | Registers the global **Ctrl+Space** hotkey via Win32 `RegisterHotKey` and fires a callback on each press. |
| `audio.py` | Opens the mic (`sounddevice`), buffers frames, writes a temp 16kHz mono WAV. Adds a 0.6s tail so the last word isn't clipped. |
| `transcription/base.py` | Abstract `TranscriptionProvider` — the contract every backend implements (`prepare`, `transcribe`, `name`, `is_ready`). |
| `transcription/factory.py` | Picks a provider by id from settings (`faster-whisper` default). |
| `transcription/faster_whisper_provider.py` | The real STT engine. Auto-detects CUDA vs CPU by free VRAM, loads the Whisper model, transcribes the WAV. Handles the frozen-exe symlink workaround (see PROJECT_LOG). |
| `transcription/onnx_parakeet_provider.py`, `nemo_parakeet_provider.py` | Alternative backends (stubs / not default). |
| `paste.py` | Clipboard + focus + `Ctrl+V` injection. Tracks the foreground window so it knows *where* to paste. Releases stray modifier keys before pasting. |
| `sounds.py` | Plays start / stop / success / error WAVs via `winsound`. |
| `history.py` | Appends each transcription to `history.json` (keeps last 10). |
| `settings.py` | Loads/saves `settings.yaml`, holds defaults (model, device, hotkey label, etc.). |
| `ui/settings_window.py` | Tkinter settings window (device, model size, sounds, autostart, GPU status). |
| `ui/history_window.py` | Tkinter window listing recent transcriptions with Copy buttons. |
| `logger.py` | Central logging to `%LOCALAPPDATA%\uttr-win\logs\uttr.log`. |
| `gpu_setup.py` | GPU detection + (source-install) CUDA package installer used by the settings GPU panel. |

## Where things live at runtime

| Path | What |
|------|------|
| `%LOCALAPPDATA%\uttr-win\logs\uttr.log` | Runtime log — **first place to look when something breaks.** |
| `%LOCALAPPDATA%\uttr-win\settings.yaml` | Saved settings. |
| `%LOCALAPPDATA%\uttr-win\history.json` | Transcription history. |
| `%LOCALAPPDATA%\uttr-win\models-local\<size>\` | Flat (symlink-free) model copy used by the installed .exe. |
| `~\.cache\huggingface\hub\` | Model cache used when running from Python source (dev mode). |

## Threading model (why it doesn't freeze)

`pystray` owns the main thread for the tray icon. Everything slow runs off it:

- **Hotkey listener** — its own thread running a Win32 message loop.
- **Foreground tracker** — polls the active window every 100ms on its own thread.
- **Model load** — daemon thread at startup (and on Settings reload).
- **Transcription** — daemon thread per recording, with a watchdog thread that
  resets state if it hangs > 120s.
- **Settings / History windows** — each spawns its own Tkinter `Tk()` thread.

## Build & distribution flow

```
   src/ ──pyinstaller uttr-win.spec──► dist/uttr-win/      (folder of exe+deps)
                                              │
                                  installer.iss (Inno Setup)
                                              │
                                              ▼
                                  Output/uttr-win-setup.exe       (CPU, ~97MB)
                                  Output/uttr-win-gpu-setup.exe   (GPU, ~590MB)
```

CPU vs GPU is controlled by the `UTTR_GPU=1` env var at PyInstaller time (which
CUDA DLLs to bundle) and the `/DGPU_BUILD` flag at Inno Setup time (which
`dist` folder + output name to use).
