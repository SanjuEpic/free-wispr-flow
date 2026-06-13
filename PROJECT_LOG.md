# uttr-win — Project Log

A running record of what was built, what broke, and how it was fixed. For the
"how the pieces fit together" view, see [ARCHITECTURE.md](ARCHITECTURE.md).

## What the app is

A Windows tray app for local speech-to-text. Press **Ctrl+Space**, speak, press
again — transcribed text pastes at your cursor. Runs offline using
faster-whisper (`small.en` by default), GPU-accelerated with automatic CPU
fallback.

## Current status (as of last session)

| Area | Status |
|------|--------|
| Hotkey (Ctrl+Space) | ✅ Working — start/stop recording |
| Audio capture | ✅ Working — 16kHz mono + 0.6s tail buffer |
| Transcription (CUDA) | ✅ Working in dev; fixed for installed exe |
| Paste-at-cursor | ✅ Working — clipboard + refocus + Ctrl+V |
| Sounds | ✅ Replaced robotic tones with soft pops/chimes |
| Settings window | ✅ Working — device, model, sounds, autostart |
| History window | ✅ Working — last 10 transcriptions, copy buttons |
| Launch notification | ✅ Windows toast on ready |
| CPU + GPU installers | ✅ Building (`Output\uttr-win-setup.exe`, `...-gpu-setup.exe`) |

## Key decisions

- **Hotkey = Ctrl+Space.** Earlier tried `Alt+Win+Space` — failed: `Alt+Space`
  is a reserved Windows system shortcut (opens the window system menu), and
  `Win`-combos are partly reserved on Win11. `Ctrl+D` was rejected (browser
  bookmark conflict). Settled on `Ctrl+Space`. The hotkey is **hardcoded** in
  `hotkey.py`; the Settings window shows a fixed `CTRL+SPACE` label so it can't
  drift from the real registration.
- **Model default = `small.en`.** Dropdown trimmed to `tiny.en / base.en /
  small.en (recommended)` so beginners don't pick huge slow models.
- **Distribution = PyInstaller folder bundle + Inno Setup**, not single-file
  exe (single-file extracts to temp on every launch — slow, AV-flagged).
- **Two installer variants.** CPU (~97MB) and GPU (~590MB, bundles only the 6
  CUDA DLLs ctranslate2 actually loads — not the full cuDNN package).

## Bugs found & fixed

### 1. Model wouldn't load in the installed exe (the big one)
- **Symptom:** Transcription always failed with "No transcription provider
  available" → error sound. Worked fine from `python -m uttr_win.app`.
- **Cause:** HuggingFace caches `model.bin` as a Windows **symlink** into a
  `blobs/` folder. Python follows it fine, but the **bundled ctranslate2 C++
  library in the frozen exe cannot follow the symlink.**
- **Failed first attempt:** Redirecting `HUGGINGFACE_HUB_CACHE` to a new folder
  — didn't help, HF still created symlinks there.
- **Fix:** In frozen mode, download a **flat, symlink-free copy** via
  `faster_whisper.download_model(output_dir=...)` to
  `%LOCALAPPDATA%\uttr-win\models-local\<size>\`, then load `WhisperModel` from
  that path. Verified `model.bin` is a real 483MB file, not a symlink. Dev mode
  is unchanged (still uses the HF cache by model name).
  See `faster_whisper_provider.py::_resolve_model_source`.

### 2. Paste-at-cursor failed from the exe
- **Symptom:** `SendInput` returned 0; nothing pasted, even manual Ctrl+V dead.
- **Cause:** Lingering modifier-key state after the hotkey fired + stricter
  `SendInput` rules for a `console=False` background process.
- **Fix in `paste.py`:** release Alt/Win/Space key-ups before pasting
  (`_release_modifiers`), add scan codes to the Ctrl+V input, small sleeps to
  let the input queue drain.

### 3. PyInstaller "attempted relative import"
- **Cause:** spec pointed at `src/uttr_win/app.py` which uses relative imports.
- **Fix:** added `launcher.py` (absolute import `from uttr_win.app import main`)
  as the entry point.

### 4. Sounds / icon not found in exe
- **Cause:** `Path(__file__).parent...` resolves wrong when frozen.
- **Fix:** check `sys.frozen` and use `sys._MEIPASS` in `sounds.py` and
  `app.py`.

### 5. Settings showed wrong hotkey ("alt+win+space")
- **Cause:** stale default in `settings.py` + window read it from config.
- **Fix:** default changed to `ctrl+space`; Settings window now shows a
  hardcoded `CTRL+SPACE` label.

### 6. Robotic-sounding tones
- **Fix:** regenerated soft sine-wave pops/chimes (0.18–0.34s) into
  `assets/sounds/` — gentle start/stop pops, ascending success chime, soft low
  error tone.

### 7. GPU installer bloat (999MB → 590MB)
- **Cause:** bundled all cuDNN DLLs + pydantic + onnxruntime.
- **Fix:** whitelist only the 6 CUDA DLLs ctranslate2 loads; exclude unused
  packages in the spec.

### 8. VAD failed in the exe — "Applying the VAD filter requires the onnxruntime package"
- **Symptom:** Transcription failed → error chime, *after* the model loaded OK.
- **Root cause:** Not VAD itself — VAD works. The `vad_filter=True` path uses
  the Silero VAD model via **`onnxruntime`**, which step 7 had **excluded from
  the bundle** for size. Dev mode worked because the dev venv has onnxruntime;
  the frozen exe did not.
- **Wrong first fix:** dropped `vad_filter=True` entirely. This removed a
  *working* feature (and risks Whisper hallucinating phantom text on silence)
  just to avoid a dependency we had removed ourselves.
- **Correct fix:** keep VAD; properly bundle the dependency. In `uttr-win.spec`:
  `collect_all("onnxruntime")` (DLLs + data) + `collect_data_files("faster_whisper")`
  (ships `assets/silero_vad_v6.onnx`), and removed `onnxruntime` from `excludes`.
  Verified both bundles contain `onnxruntime.dll` and `silero_vad_v6.onnx`.
- **Lesson:** when a frozen-exe feature fails with "requires package X", the fix
  is usually to bundle X, not to delete the feature.

### 9. App crashed on Save & Reload; tray froze / responded late
- **Symptom:** Pressing Save & Reload silently killed the whole app (no
  "Shutting down" log, single-instance lock released → relaunch needed). The
  tray icon also froze or responded late, sometimes needing a relaunch.
- **Root cause (one cause, three symptoms):** Settings and History each created
  their **own `Tk()` root in a background thread**. tkinter is not thread-safe;
  running it off the main thread and creating/destroying multiple roots across
  threads intermittently corrupts the Tcl interpreter → hard segfault, which
  also destabilised the pystray loop (freezes).
- **Fix (windowing refactor):**
  - One persistent **hidden `Tk()` root on the main thread**; Settings/History
    are now `Toplevel`s of it (no per-window `Tk()`, no per-window threads).
  - **pystray runs in a background thread**; its menu callbacks only enqueue a
    token onto a `queue.Queue`.
  - The main thread polls that queue via `root.after(100, ...)` and creates the
    windows — so all tkinter work happens on one thread.
  - Background work (GPU probe, CUDA install) marshals UI updates with
    `win.after(...)`, guarded by `winfo_exists()`.
  - See `app.py` (`run`/`_poll_ui_queue`/`_show_*`/`_shutdown`),
    `ui/settings_window.py`, `ui/history_window.py`.
- **Verified:** open → Save (destroy + reload) → reopen → cancel, and history
  open/refresh/clear/close all run with no crash; full app launches and stays
  stable.

## How to build

```bash
# From repo root, with `pip install -e .` done and PyInstaller + Inno Setup installed.

# CPU variant
python -m PyInstaller uttr-win.spec --noconfirm
"$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" installer.iss
#   → Output/uttr-win-setup.exe   (~97MB)

# GPU variant
UTTR_GPU=1 python -m PyInstaller uttr-win.spec --noconfirm --distpath dist-gpu --workpath build-gpu
ISCC.exe /DGPU_BUILD installer.iss        # run via PowerShell for the /D flag
#   → Output/uttr-win-gpu-setup.exe   (~590MB)
```

Note: the `/DGPU_BUILD` flag must be passed via PowerShell
(`& "...\ISCC.exe" /DGPU_BUILD installer.iss`); the Git-Bash invocation mangles
it into "more than one script filename".

## How to test (dev, no rebuild)

```bash
# Kill any stale instances first (single-instance mutex + leftover processes)
#   PowerShell: Get-Process python,uttr-win | Stop-Process -Force

python -m uttr_win.app
# Then: click into Notepad → Ctrl+Space → speak → Ctrl+Space → text should paste.
```

**First debugging stop is always the log:**
`%LOCALAPPDATA%\uttr-win\logs\uttr.log`
- `Model loaded on cuda` → provider OK
- `SendInput returned 4 (expected 4)` → paste OK
- `No transcription provider available` → model failed to load (check above it)

## Known gotchas

- **Single-instance mutex:** a second launch silently exits. If a hotkey seems
  dead, an old instance may still be holding it — kill stale `python`/`uttr-win`
  processes.
- **Launch notification** is a Windows toast; if Focus Assist / notifications
  are muted you won't see "Ready! Press Ctrl+Space to start recording."
- **First exe launch** may pause to create the flat model copy (one-time).

## Open / possible follow-ups

- Terminal flash on very first launch after install (minor, cosmetic).
- Making the hotkey user-configurable (currently hardcoded).
- Wiring up the Parakeet providers (currently stubs).
