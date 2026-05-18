<img src="docs/assets/logo.png" alt="uttr" width="96">

# uttr

A macOS menu bar app for fast, local speech-to-text transcription. Press a hotkey, speak, and the transcribed text is automatically pasted at your cursor — no cloud, no Python, no dependencies.

Powered by [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) running on the Apple Neural Engine via [FluidAudio](https://github.com/FluidAudio/FluidAudio).

## Installation

```bash
brew tap ShishirAravindan/uttr
brew install --cask uttr
```

That's it. No Python, no `uv`, no setup.

## Quick Start

1. Launch **uttr** — the icon appears in your menu bar
2. Grant permissions when prompted: **Microphone** and **Accessibility**
3. Press the hotkey (default: `⌥L`) to start recording
4. Speak, then press the hotkey again to stop
5. Transcribed text is pasted at your cursor

The first transcription downloads the Parakeet model (~600 MB). Subsequent transcriptions are instant.

## Configuration

Settings are stored at `~/Library/Application Support/uttr/settings.yaml`.

Configure via menu bar → Settings, or edit the YAML directly.

See [Configuration Guide](docs/configuration.md) for all options.

## Documentation

- [Getting Started](docs/getting-started.md) — Detailed setup and first-run guide
- [Configuration](docs/configuration.md) — All settings explained
- [Architecture](docs/architecture.md) — How it works (for contributors)
- [Development](docs/development.md) — Building from source
- [Troubleshooting](docs/troubleshooting.md) — Common issues and fixes

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1 or later) — required for the Neural Engine

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
