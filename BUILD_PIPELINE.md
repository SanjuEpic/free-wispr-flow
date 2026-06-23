# How uttr-win is packaged: Python → exe → installer

A guide for the Python-minded: how the source in `src/uttr_win/` becomes the
downloadable `uttr-win-setup.exe` on the Releases page. Two separate tools do two
separate jobs — **PyInstaller** ("run without Python") and **Inno Setup**
("distribute & install").

## The one-liner

> PyInstaller packs the Python interpreter + your code + the CUDA libs into a
> *folder that runs on a machine with no Python*. Inno Setup wraps that folder
> into a *single setup.exe* that installs to Program Files with a Start-menu
> shortcut, autostart registry entry, and an uninstaller.

## The flow

```
  YOUR PYTHON SOURCE                 STAGE 1: FREEZE                 STAGE 2: INSTALLER
  ┌────────────────────┐            (PyInstaller)                   (Inno Setup)
  │ src/uttr_win/*.py  │
  │ launcher.py  ◄─────┼──┐         ┌───────────────────┐         ┌──────────────────────┐
  │ assets/ (icon,wav) │  │ reads   │  uttr-win.spec    │         │   installer.iss      │
  └────────────────────┘  └────────►│  (build recipe)   │         │  (install recipe)    │
                                     └─────────┬─────────┘         └──────────┬───────────┘
   env: UTTR_GPU=1 ──────────────────────────►│                              │
   (spec bundles CUDA when set)                │ PyInstaller                  │ ISCC.exe
                                               ▼                              │ /DGPU_BUILD
                                     ┌───────────────────────┐                │
                                     │  dist-gpu/uttr-win/   │  ── input ────►│
                                     │  ├─ uttr-win.exe (22MB│                ▼
                                     │  │   bootloader+code) │     ┌──────────────────────┐
                                     │  ├─ python313.dll     │     │ Output/              │
                                     │  ├─ cuda/cudnn .dlls  │     │  uttr-win-setup.exe  │
                                     │  ├─ _internal/ (deps) │     │  (~600 MB, ONE file) │
                                     │  └─ assets/           │     └──────────┬───────────┘
                                     └───────────────────────┘                │ user double-clicks
                                        "works, but it's a                    ▼
                                         100s-of-files folder"      ┌──────────────────────┐
                                                                    │ C:\Program Files\... │
                                                                    │  + Start Menu icon   │
                                                                    │  + registry (autostart)
                                                                    │  + uninstaller       │
                                                                    └──────────────────────┘
```

## The pieces (mapped to real files in this repo)

**`launcher.py` — entry point.** PyInstaller freezes *one* start script. From
source you run `python -m uttr_win.app`; the frozen exe starts at `launcher.py`,
which boots the same app. The `getattr(sys, "frozen", False)` checks in the code
(e.g. `faster_whisper_provider.py`) mean "am I running inside the exe or from
source?" — the exe path loads the model from a bundled local dir instead of
hitting HuggingFace.

**`uttr-win.spec` — the PyInstaller recipe (it's just Python).** Declares the
entry script, extra data to drag along (`assets/`, the Silero VAD `.onnx`), and
**hidden imports** (modules PyInstaller's static analysis misses — common with ML
libs). It reads the `UTTR_GPU` env var: when set, it bundles the multi-hundred-MB
CUDA DLLs. That's why the build command is `$env:UTTR_GPU=1; python -m PyInstaller ...`.

**PyInstaller "freezing"** traces every import, then copies the Python interpreter
(`python313.dll`), your bytecode, and all dependency `.dll`/`.pyd` files into
`dist-gpu/uttr-win/`. The `uttr-win.exe` in there is a small **bootloader** (~22 MB)
— not your code, but a launcher that spins up the embedded Python and runs your
bytecode from `_internal/`. This folder already works — but it's hundreds of loose
files, hostile to ship.

**`installer.iss` — the Inno Setup recipe (Pascal-ish, not Python).** Takes
everything in `dist-gpu/uttr-win/`, compresses it into one self-extracting
`setup.exe`, and on the user's machine: copies to Program Files, makes the
Start-menu shortcut, writes the autostart registry key, and generates an
uninstaller. The `/DGPU_BUILD` flag is a compile-time switch (like `#define`)
telling it to package the GPU folder.

**`ISCC.exe`** is Inno's command-line compiler — reads `installer.iss`, emits
`Output/uttr-win-setup.exe`, the file users download.

## Why two tools (the part that trips up Python folks)

| | PyInstaller | Inno Setup |
|---|---|---|
| Problem solved | Run on a machine with **no Python** | **Distribute & install** cleanly |
| Output | A *folder* of files | A *single* setup.exe |
| Analogy | bundling a venv + the interpreter | the Next→Next→Finish wizard / `.msi` |
| Skippable? | No — users have no Python | Yes, but you'd ship a 100-file zip |

## The build commands (from PROJECT_LOG)

```powershell
# Stage 1 — freeze (universal/GPU build: CUDA bundled, auto CPU fallback)
$env:UTTR_GPU=1
python -m PyInstaller uttr-win.spec --noconfirm --distpath dist-gpu --workpath build-gpu
#   → dist-gpu/uttr-win/  (the runnable folder)

# Stage 2 — installer
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" /DGPU_BUILD installer.iss
#   → Output/uttr-win-setup.exe  (~600 MB, the shippable file)
```

## What ships vs what doesn't

- **Shipped:** the GPU build only — one universal installer that bundles CUDA so
  NVIDIA users get fast inference and CPU-only machines fall back automatically.
- **Releases are manual:** rebuild locally, smoke-test the exe, then
  `gh release create` / `gh release upload`. No tag-triggered CI build — a headless
  runner can't smoke-test the exe (no mic/GPU/display) and could publish a broken one.
