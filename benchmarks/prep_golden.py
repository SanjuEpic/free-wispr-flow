"""
Build a small LibriSpeech test-clean golden set for WER benchmarking.

Streams the dataset (no full 346MB download), takes the first N utterances, and
writes 16 kHz mono <id>.wav + <id>.txt pairs into benchmarks/golden/.

Usage: python benchmarks/prep_golden.py [--n 50]
"""
import argparse
from pathlib import Path

import io

import soundfile as sf
from datasets import Audio, load_dataset

OUT = Path(__file__).parent / "golden"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=50)
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)

    # decode=False avoids datasets' torchcodec/torch dependency — we get the raw FLAC
    # bytes and decode them ourselves with soundfile (LibriSpeech is already 16 kHz mono).
    ds = load_dataset("openslr/librispeech_asr", "clean", split="test", streaming=True)
    ds = ds.cast_column("audio", Audio(decode=False))
    n = 0
    sr = None
    for ex in ds:
        if n >= args.n:
            break
        uid = ex["id"]
        data, sr = sf.read(io.BytesIO(ex["audio"]["bytes"]))
        sf.write(str(OUT / f"{uid}.wav"), data, sr, subtype="PCM_16")
        (OUT / f"{uid}.txt").write_text(ex["text"].strip(), encoding="utf-8")
        n += 1
        if n % 10 == 0:
            print(f"  {n} utterances...")
    print(f"Wrote {n} utterances to {OUT}/ (sr={sr})")


if __name__ == "__main__":
    main()
