# Development Guide

This guide covers building and developing uttr from source.

## Prerequisites

- **Xcode 15+** — [Download from Mac App Store](https://apps.apple.com/app/xcode/id497799835)
- **macOS 14 (Sonoma)+** — Required for deployment target
- **Apple Silicon** — Required for FluidAudio / Neural Engine

## Repository Structure

```
uttr/
├── Swift/                          # macOS app source
│   ├── uttr.swift                  # App entry point
│   ├── AudioRecorder.swift         # Audio capture
│   ├── HotkeyManager.swift         # Global hotkeys
│   ├── Transcription/              # Provider protocol + implementations
│   └── ...
├── docs/                           # Documentation
├── Casks/uttr.rb                   # Homebrew cask formula
├── uttr.xcodeproj/                 # Xcode project
└── README.md
```

## Building the App

### 1. Clone the Repository

```bash
git clone https://github.com/Rakk301/homebrew-uttr.git
cd homebrew-uttr
```

### 2. Open in Xcode

```bash
open uttr.xcodeproj
```

### 3. Build and Run

- Select the **uttr** scheme
- Press `Cmd+R` to build and run
- Grant permissions when prompted

Or use the build script:

```bash
./build.sh -c Debug
```

## Required Permissions

When running from Xcode, you'll need to grant:

| Permission | Purpose | How to Grant |
|------------|---------|--------------|
| Microphone | Audio recording | Prompt appears, or System Settings → Privacy |
| Accessibility | Global hotkeys, paste | System Settings → Privacy → Accessibility |

**Tip:** If hotkeys stop working, check that Xcode (or the built app) is in the Accessibility list.

## Debugging

### Swift Logs

Logs appear in Xcode console. Filter by component:

- `[AudioRecorder]` — Recording issues
- `[HotkeyManager]` — Hotkey registration
- `[FluidAudioProvider]` — Transcription issues

### Common Issues

**Hotkey not working:**
- Verify Accessibility permission is granted
- Check another app isn't using the same hotkey

**Transcription fails on first run:**
- The Parakeet model (~600 MB) downloads on first use — wait for completion
- Check network connectivity if download stalls

## Code Style

- One file per component/responsibility
- Use `Logger` for all logging, not `print()`
- Prefer `async/await` for asynchronous operations
- Follow existing patterns in the codebase

## Building for Distribution

```bash
./build.sh -c Release
```

This builds, then installs to `/Applications/uttr.app`. See [Releasing Guide](releasing.md) for the full release process.

## Related Docs

- [Architecture](architecture.md) — How it works internally
- [Configuration](configuration.md) — Settings reference
- [Troubleshooting](troubleshooting.md) — Common issues
