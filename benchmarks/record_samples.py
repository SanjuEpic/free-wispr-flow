"""
Record benchmark audio samples.

Usage: python benchmarks/record_samples.py

Reads each .txt file in benchmarks/samples/, displays the text,
records your voice, and saves a matching .wav file.
Press ENTER to start recording, ENTER again to stop.
"""

import sys
from pathlib import Path

import numpy as np
import sounddevice as sd
from scipy.io import wavfile

SAMPLE_RATE = 16000
SAMPLES_DIR = Path(__file__).parent / "samples"


def record_sample(name: str, text: str) -> None:
    print(f"\n{'='*60}")
    print(f"  Sample: {name}")
    print(f"  Length: {len(text)} chars")
    print(f"{'='*60}")
    print(f"\n  Read this aloud:\n")
    print(f'  "{text}"\n')

    input("  Press ENTER to START recording...")
    print("  🎤 RECORDING... (press ENTER to STOP)")

    frames = []
    recording = True

    def callback(indata, frame_count, time_info, status):
        if recording:
            frames.append(indata.copy())

    stream = sd.InputStream(
        samplerate=SAMPLE_RATE, channels=1, dtype="int16", callback=callback
    )
    stream.start()
    input()
    recording = False
    stream.stop()
    stream.close()

    if not frames:
        print("  No audio captured, skipping.")
        return

    audio = np.concatenate(frames, axis=0)
    duration = len(audio) / SAMPLE_RATE
    out_path = SAMPLES_DIR / f"{name}.wav"
    wavfile.write(str(out_path), SAMPLE_RATE, audio)
    print(f"  Saved: {out_path} ({duration:.1f}s)")


def main():
    txt_files = sorted(SAMPLES_DIR.glob("*.txt"))
    if not txt_files:
        print("No .txt files found in benchmarks/samples/")
        sys.exit(1)

    print("\n  uttr-win Benchmark Recorder")
    print(f"  Found {len(txt_files)} prompts to record.\n")

    for txt in txt_files:
        name = txt.stem
        wav_path = SAMPLES_DIR / f"{name}.wav"

        if wav_path.exists():
            choice = input(f"  {name}.wav already exists. Re-record? [y/N] ").strip().lower()
            if choice != "y":
                print(f"  Skipping {name}")
                continue

        text = txt.read_text(encoding="utf-8").strip()
        record_sample(name, text)

    print(f"\n  Done! Run benchmarks with:")
    print(f"  python benchmarks/benchmark_providers.py --providers 1\n")


if __name__ == "__main__":
    main()
