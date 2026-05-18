# Getting Started

This guide walks you through installing and setting up uttr.

## Installation

### Option 1: Homebrew (Recommended)

```bash
brew tap ShishirAravindan/uttr
brew install --cask uttr
```

No additional dependencies required.

### Option 2: Download from Releases

1. Download the latest `.zip` from [GitHub Releases](https://github.com/ShishirAravindan/homebrew-uttr/releases)
2. Extract and move `uttr.app` to `/Applications`

### Allowing the App (Gatekeeper)

Since the app is not notarized, macOS will block it on first launch:

1. Try to open the app — you'll see a warning
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the uttr message
4. Click **Open** in the confirmation dialog

## Required Permissions

### Microphone Access

Required for recording your speech.

- The app prompts automatically on first recording attempt
- Or grant manually: **System Settings → Privacy & Security → Microphone**

### Accessibility Access

Required for global hotkeys and pasting text at your cursor.

- The app prompts automatically
- Or grant manually: **System Settings → Privacy & Security → Accessibility**

## First Run

1. **Launch the app** — look for the icon in your menu bar
2. **Grant permissions** — follow the prompts for Microphone and Accessibility
3. **Press your hotkey** (default: `⌥L`) to start recording
4. **Speak**, then press the hotkey again to stop

The first transcription downloads the Parakeet model (~600 MB). Subsequent transcriptions are instant.

## Using the App

### Basic Workflow

1. Place your cursor where you want text to appear
2. Press the hotkey to **start recording** (menu bar icon changes)
3. Speak clearly into your microphone
4. Press the hotkey again to **stop recording**
5. Transcribed text is automatically pasted at your cursor

### Settings

Access via menu bar icon → Settings:

| Setting | Description |
|---------|-------------|
| **Provider** | Parakeet v3 (multilingual) or v2 (English only) |
| **Hotkey** | Click "Change" to record a new shortcut |

## Next Steps

- [Configuration Guide](configuration.md) — All settings explained
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
