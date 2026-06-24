# uttr-win — Project Log

A running record of what was built, what broke, and how it was fixed. For the
"how the pieces fit together" view, see [ARCHITECTURE.md](ARCHITECTURE.md).

## What the app is

A Windows tray app for local speech-to-text. Press **Ctrl+Space**, speak, press
again — transcribed text pastes at your cursor. Runs offline using
faster-whisper (`small.en` by default), GPU-accelerated with automatic CPU
fallback.

## Current status

**Shipped as v0.1.1** — published on GitHub Releases, user-tested on a real
machine (hotkey, transcription, paste, sounds, history, settings, and tray
responsiveness all confirmed working). v0.1.1 adds an on-demand "Unload model"
tray action.

| Area | Status |
|------|--------|
| Hotkey (Ctrl+Space) | ✅ Working — start/stop recording |
| Audio capture | ✅ Working — 16kHz mono + 0.6s tail buffer |
| Transcription (CUDA + CPU) | ✅ Working in dev and installed exe; auto CPU fallback |
| Paste-at-cursor | ✅ Working — clipboard + refocus + Ctrl+V |
| Sounds | ✅ Soft pops/chimes (robotic tones replaced) |
| Settings window | ✅ Working — device, model, sounds, autostart |
| History window | ✅ Working — last 10 transcriptions, copy buttons |
| Launch notification | ✅ Windows toast on ready |
| Tray + window responsiveness | ✅ Fixed — main-thread tkinter refactor (bug #9) |
| Installer | ✅ Single universal `uttr-win-setup.exe` on Releases (CUDA + CPU fallback) |
| Unload model (free VRAM) | ✅ Tray action; lazy-reloads on next Ctrl+Space (v0.1.1) |

## Release

- **v0.1.1** — adds the "Unload model" tray action (see Features below).
  Rebuilt universal installer `uttr-win-setup.exe` (~600 MB).
- **v0.1.0** — single universal installer `uttr-win-setup.exe` (~600 MB) on the
  [Releases](https://github.com/SanjuEpic/free-wispr-flow/releases) page.
- Built from the **GPU bundle** (`UTTR_GPU=1`): bundles CUDA so NVIDIA users get
  fast inference, and falls back to CPU automatically on machines without a GPU.
- Releases are **manual** (no auto-build CI): rebuild locally, test, then
  `gh release upload`. A tag-triggered build was considered and deliberately
  skipped — a headless runner can't smoke-test the exe (no mic/GPU/display) and
  would happily publish broken builds.

## Key decisions

- **Parakeet (parakeet.cpp) evaluated and rejected for now.** Built a working
  `parakeet.cpp` (GGUF `tdt-0.6b-v2-q8`) provider and a universal bundle, then
  real-world live-mic tested it against faster-whisper `small.en` on the RTX 3050.
  Verdict: **not worth shipping.** On GPU the two were ~on par for latency and
  accuracy, but Parakeet used **~2× the VRAM** (~1.3 GB vs ~0.6 GB) for no speed
  win, and was **inconsistent on numbers** — e.g. it would render "1.3" as words
  one time and digits the next, where faster-whisper is reliably correct.
  Parakeet's only real edges were CPU latency (~2–3 s vs whisper ~5–8 s) and
  catching soft/whispered speech (no VAD gate), neither of which justified the
  extra GPU cost, the +1.4 GB installer, and the output inconsistency. The
  provider code was reverted; faster-whisper remains the sole engine. Revisit
  only if a CPU-only or soft-speech use case becomes a priority.
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
- **One universal installer, not two.** Originally built separate CPU (~97MB)
  and GPU (~600MB) variants, but the CPU exe didn't run on the test machine and
  the GPU exe already falls back to CPU cleanly (triple-guarded: exception-safe
  CUDA check → `nvidia-smi` absence → load-failure fallback). So
  we publish a single `uttr-win-setup.exe` (the GPU build) and drop the CPU
  variant from Releases. The CPU build still exists (`installer.iss` plain
  target → `uttr-win-cpu-setup.exe`) but is unpublished. The GPU bundle includes
  only the 6 CUDA DLLs ctranslate2 actually loads — not the full cuDNN package.

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

## Features added post-0.1.0

### Unload model (free GPU VRAM on demand) — v0.1.1
- **Why:** the model stays resident in VRAM for the whole session (deliberate —
  keeps each transcription ~1s instead of paying the load cost every press). But
  that ~600MB sits in VRAM even when idle, unavailable to games/other GPU work.
- **What:** a tray menu item **"Unload model (free GPU memory)"** drops the
  loaded model. It lazily reloads on the next **Ctrl+Space** — recording starts
  immediately while the reload runs concurrently in a background thread, and
  `_transcribe` waits (up to `RELOAD_WAIT_TIMEOUT_S = 30`) for it to finish, so
  the reload is invisible unless you stop talking faster than it loads.
- **How VRAM is actually freed:** CPython refcounting — dropping `self._model`
  triggers ctranslate2's native destructor + `cudaFree`. `gc.collect()` is cheap
  insurance for the cycle case, not the mechanism. **nvidia-smi cannot free
  another process's memory** (it's read-only monitoring); there is no CLI to free
  a specific allocation.
- **Caveat (measured):** VRAM does **not** drop to zero. The CUDA *context* stays
  resident while the process lives. Smoke test on RTX 3050: free VRAM
  3400→2853MB on load, back to **3315MB** after unload — reclaimed ~462MB of
  ~547MB, leaving ~85MB context overhead until Quit.
- **Scope:** `unload()` added to the `TranscriptionProvider` ABC (default no-op),
  with real implementations in faster-whisper **and** the NeMo/ONNX stubs (they
  hold GPU models too, so the no-op would have been a dishonest "unloaded").
- Verified by `benchmarks/smoke_unload.py` (load → transcribe → unload → reload →
  transcribe, identical output). See `app.py`
  (`_unload_model`/`_ensure_model_loaded`, the `_on_toggle` reload kick, and the
  reload wait in `_transcribe`).

## Verified facts

### Performance & quantization (measured)
`compute_type="auto"` → **`float16` on GPU, `int8` on CPU** (set in
`faster_whisper_provider.py`).

| | Quantization | Typical 5–8s utterance | Notes |
|---|---|---|---|
| **GPU** | float16 | **~1.3s** | recommended path |
| **CPU** | int8 | **~3.6–3.9s** | ~3–5× slower; grows with clip length |

Quality A/B on the same clip: **GPU (float16) was *more* accurate** ("token
refresh failures") than CPU (int8, heard "figures"). `int8` is lower precision
than `float16`, so a perceived "CPU is better" is run-to-run variance, not real.

### Offline claim (verified)
The installed exe genuinely runs **fully offline after the one-time model
download**. Our code makes zero network calls; the frozen exe loads the model
from a local directory path (faster-whisper skips HuggingFace when given a
directory), and VAD runs from the bundled `silero_vad_v6.onnx`. Proven by
loading + transcribing with `HF_HUB_OFFLINE=1`. (Running *from source* passes a
model *name*, so it does a HuggingFace freshness check at startup — does not
affect the shipped exe.)

## How to build

```bash
# From repo root, with `pip install -e .` done and PyInstaller + Inno Setup installed.

# Universal build (PUBLISHED) — CUDA bundled, auto CPU/GPU at runtime
UTTR_GPU=1 python -m PyInstaller uttr-win.spec --noconfirm --distpath dist-gpu --workpath build-gpu
ISCC.exe /DGPU_BUILD installer.iss        # run via PowerShell for the /D flag
#   → Output/uttr-win-setup.exe   (~600MB)

# Optional CPU-only build (NOT published)
python -m PyInstaller uttr-win.spec --noconfirm
"$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" installer.iss
#   → Output/uttr-win-cpu-setup.exe   (~97MB)
```

Notes:
- The `/DGPU_BUILD` flag must be passed via PowerShell
  (`& "...\ISCC.exe" /DGPU_BUILD installer.iss`); the Git-Bash invocation mangles
  it into "more than one script filename".
- `installer.iss` `OutputName`: GPU build → `uttr-win-setup`, plain build →
  `uttr-win-cpu-setup`.
- To publish: `gh release upload v0.1.0 Output/uttr-win-setup.exe` (delete the
  old asset first; release-asset names can also be renamed via the GitHub API
  without re-uploading).

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
- **Device is a saved setting.** If transcription runs on CPU when a GPU exists,
  check Settings → Device — it may be pinned to `cpu`. Set it to `auto` (or
  `cuda`) for the GPU path.

## Open / possible follow-ups

- **CPU-only installer doesn't run** on the test machine (undiagnosed). Not a
  problem for users since we ship the universal/GPU build, but the root cause
  (likely a missing runtime DLL the GPU build happens to include) is unfixed.
- Terminal flash on very first launch after install (minor, cosmetic).
- Making the hotkey user-configurable (currently hardcoded).
- Wiring up the Parakeet providers (currently stubs).
