# Troubleshooting

Common issues and solutions for uttr.

## Installation Issues

### "App can't be opened because Apple cannot check it for malicious software"

The app is not notarized. To open it:

1. Go to **System Settings → Privacy & Security**
2. Scroll down to find the message about uttr
3. Click **Open Anyway**
4. Click **Open** in the confirmation dialog

## Permission Issues

### Global hotkey not working

1. Open **System Settings → Privacy & Security → Accessibility**
2. Find uttr in the list
3. Toggle it **off**, then **on** again
4. Restart the app

If the app isn't in the list, try pressing the hotkey once — this should trigger the permission prompt.

### Microphone permission denied

1. Open **System Settings → Privacy & Security → Microphone**
2. Ensure uttr is toggled **on**
3. If not listed, reset permissions:
   ```bash
   tccutil reset Microphone io.github.ShishirAravindan.uttr
   ```

### "Recording failed" error

- Check another app isn't using the microphone exclusively
- Verify your input device is selected in **System Settings → Sound → Input**
- Try unplugging and reconnecting external microphones

## Transcription Issues

### App seems to hang on first transcription

This is normal. The first transcription triggers a one-time download of the Parakeet model (~600 MB). Wait for it to complete — subsequent transcriptions are instant.

### Poor accuracy

1. **Speak clearly** — Parakeet works best with clear speech and minimal background noise
2. **Use a better microphone** — Built-in mic works, but an external mic improves results
3. **Switch providers** — Try Parakeet v3 (multilingual) if using v2

### Text not pasting

1. **Check cursor position** — Click where you want text before starting
2. **Check Accessibility permission** — Required for paste simulation
3. **Try a different app** — Some apps block paste simulation

## Log Files

Check logs for detailed error information:

```bash
# App logs
cat ~/Library/Application\ Support/uttr/transcriptions.log

# System logs (if app crashes)
log show --predicate 'process == "uttr"' --last 10m
```

## Reset Everything

If nothing works, reset to defaults:

```bash
rm ~/Library/Application\ Support/uttr/settings.yaml
```

Then restart the app.

## Getting Help

If you're still stuck:

1. Check [existing issues](https://github.com/ShishirAravindan/homebrew-uttr/issues)
2. Open a [new issue](https://github.com/ShishirAravindan/homebrew-uttr/issues/new) with:
   - macOS version
   - Steps to reproduce
   - Relevant log output
