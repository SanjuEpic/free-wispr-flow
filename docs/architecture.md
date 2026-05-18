# Architecture

## Overview

uttr is a single-tier Swift app. All transcription happens in-process via FluidAudio — there is no server, no Python, and no network communication after the initial model download.

## Transcribe Flow

Hotkey → `AudioRecorder` writes WAV → `FluidAudioProvider.transcribe()` → `PasteManager` pastes at cursor

## Components

| File | Responsibility |
|------|---------------|
| `uttr.swift` | App lifecycle, hotkey wiring, provider orchestration |
| `AudioRecorder.swift` | AVAudioEngine capture (16 kHz mono WAV) |
| `HotkeyManager.swift` | Global hotkey registration via Carbon |
| `PasteManager.swift` | Clipboard write + simulated paste |
| `SettingsManager.swift` | YAML-backed settings (`~/Library/Application Support/uttr/settings.yaml`) |
| `MenuBarIconManager.swift` | Status bar icon states and animations |
| `Transcription/TranscriptionProvider.swift` | `TranscriptionProvider` protocol + factory |
| `Transcription/FluidAudioProvider.swift` | FluidAudio integration (Parakeet v2/v3) |

## Settings Schema

```yaml
provider: "fluidaudio.parakeet.v3"   # or fluidaudio.parakeet.v2
fluid_audio:
  model_version: "v3"
hotkey:
  key_code: 37
  modifiers: ["option"]
```

## Model Download

FluidAudio downloads the Parakeet model (~600 MB) on the first `transcribe()` call. The model is cached in the system's ML model store and not re-downloaded on subsequent launches.
