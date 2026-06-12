"""
Benchmark STT providers with real audio files.

Usage:
    python benchmarks/benchmark_providers.py
    python benchmarks/benchmark_providers.py --providers fw   (faster-whisper only)
    python benchmarks/benchmark_providers.py --providers all  (all providers)

Records latency and WER for each model variant.
Place .wav files in benchmarks/samples/ with matching .txt reference files.
"""

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

FASTER_WHISPER_SIZES = [
    "tiny.en",
    "base.en",
    "small.en",
    "medium.en",
    "distil-medium.en",
    "distil-large-v3",
    "large-v3-turbo",
]


def compute_wer(reference: str, hypothesis: str) -> float:
    ref_words = reference.lower().split()
    hyp_words = hypothesis.lower().split()
    if not ref_words:
        return 0.0 if not hyp_words else 1.0

    d = [[0] * (len(hyp_words) + 1) for _ in range(len(ref_words) + 1)]
    for i in range(len(ref_words) + 1):
        d[i][0] = i
    for j in range(len(hyp_words) + 1):
        d[0][j] = j
    for i in range(1, len(ref_words) + 1):
        for j in range(1, len(hyp_words) + 1):
            cost = 0 if ref_words[i - 1] == hyp_words[j - 1] else 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
    return d[len(ref_words)][len(hyp_words)] / len(ref_words)


def benchmark_faster_whisper(model_size: str, audio_files: list[Path]) -> dict | None:
    from uttr_win.transcription.faster_whisper_provider import FasterWhisperProvider

    print(f"\n  faster-whisper ({model_size})")
    print(f"  {'-' * 40}")

    try:
        provider = FasterWhisperProvider(model_size=model_size, device="auto", compute_type="auto")
        t0 = time.perf_counter()
        provider.prepare()
        load_time = time.perf_counter() - t0
        print(f"  Model load: {load_time:.2f}s")
    except Exception as e:
        print(f"  FAILED: {e}")
        return None

    results = []
    for wav in audio_files:
        ref_file = wav.with_suffix(".txt")
        reference = ref_file.read_text(encoding="utf-8").strip() if ref_file.exists() else None

        t0 = time.perf_counter()
        try:
            text = provider.transcribe(str(wav))
        except Exception as e:
            print(f"    {wav.stem}: ERROR — {e}")
            continue
        latency = time.perf_counter() - t0

        wer = compute_wer(reference, text) if reference else None
        results.append({"file": wav.stem, "latency": latency, "wer": wer, "text": text})

        wer_str = f"WER={wer:.1%}" if wer is not None else "no ref"
        print(f"    {wav.stem}: {latency:.2f}s | {wer_str}")
        print(f"      -> {text[:120]}")

    return {
        "name": f"faster-whisper ({model_size})",
        "load_time": load_time,
        "results": results,
    }


def benchmark_nemo(audio_files: list[Path]) -> dict | None:
    from uttr_win.transcription.nemo_parakeet_provider import NemoParakeetProvider

    print(f"\n  NeMo Parakeet")
    print(f"  {'-' * 40}")

    try:
        provider = NemoParakeetProvider()
        t0 = time.perf_counter()
        provider.prepare()
        load_time = time.perf_counter() - t0
        print(f"  Model load: {load_time:.2f}s")
    except Exception as e:
        print(f"  SKIPPED: {e}")
        return None

    results = []
    for wav in audio_files:
        ref_file = wav.with_suffix(".txt")
        reference = ref_file.read_text(encoding="utf-8").strip() if ref_file.exists() else None

        t0 = time.perf_counter()
        try:
            text = provider.transcribe(str(wav))
        except Exception as e:
            print(f"    {wav.stem}: ERROR — {e}")
            continue
        latency = time.perf_counter() - t0

        wer = compute_wer(reference, text) if reference else None
        results.append({"file": wav.stem, "latency": latency, "wer": wer, "text": text})

        wer_str = f"WER={wer:.1%}" if wer is not None else "no ref"
        print(f"    {wav.stem}: {latency:.2f}s | {wer_str}")
        print(f"      -> {text[:120]}")

    return {
        "name": "NeMo Parakeet",
        "load_time": load_time,
        "results": results,
    }


def benchmark_onnx(audio_files: list[Path]) -> dict | None:
    from uttr_win.transcription.onnx_parakeet_provider import OnnxParakeetProvider

    print(f"\n  ONNX Parakeet")
    print(f"  {'-' * 40}")

    try:
        provider = OnnxParakeetProvider()
        t0 = time.perf_counter()
        provider.prepare()
        load_time = time.perf_counter() - t0
        print(f"  Model load: {load_time:.2f}s")
    except Exception as e:
        print(f"  SKIPPED: {e}")
        return None

    results = []
    for wav in audio_files:
        ref_file = wav.with_suffix(".txt")
        reference = ref_file.read_text(encoding="utf-8").strip() if ref_file.exists() else None

        t0 = time.perf_counter()
        try:
            text = provider.transcribe(str(wav))
        except Exception as e:
            print(f"    {wav.stem}: ERROR — {e}")
            continue
        latency = time.perf_counter() - t0

        wer = compute_wer(reference, text) if reference else None
        results.append({"file": wav.stem, "latency": latency, "wer": wer, "text": text})

        wer_str = f"WER={wer:.1%}" if wer is not None else "no ref"
        print(f"    {wav.stem}: {latency:.2f}s | {wer_str}")
        print(f"      -> {text[:120]}")

    return {
        "name": "ONNX Parakeet",
        "load_time": load_time,
        "results": results,
    }


def print_summary(all_results: list[dict], output_path: Path | None = None):
    lines = []

    def out(s=""):
        print(s)
        lines.append(s)

    out(f"\n{'=' * 80}")
    out("BENCHMARK RESULTS")
    out(f"{'=' * 80}")
    out(f"{'Model':<30} {'Load':>6} {'Avg Lat':>8} {'Avg WER':>8}  {'Short':>6} {'Med':>6} {'Long':>6}")
    out("-" * 80)

    for entry in all_results:
        name = entry["name"]
        load = entry["load_time"]
        results = entry["results"]
        if not results:
            continue

        avg_lat = sum(r["latency"] for r in results) / len(results)
        wers = [r["wer"] for r in results if r["wer"] is not None]
        avg_wer = sum(wers) / len(wers) if wers else None

        per_file = {}
        for r in results:
            per_file[r["file"]] = r

        short_wer = per_file.get("short", {}).get("wer")
        med_wer = per_file.get("medium", {}).get("wer")
        long_wer = per_file.get("long", {}).get("wer")

        def fmt_wer(w):
            return f"{w:.0%}" if w is not None else "—"

        avg_wer_str = f"{avg_wer:.0%}" if avg_wer is not None else "N/A"
        out(f"{name:<30} {load:>5.1f}s {avg_lat:>7.2f}s {avg_wer_str:>8}  {fmt_wer(short_wer):>6} {fmt_wer(med_wer):>6} {fmt_wer(long_wer):>6}")

    out()
    out("Lower WER = better accuracy. Lower latency = faster.")
    out("Sweet spot: best WER with acceptable latency for your use case.")

    # Full transcription outputs per model
    out(f"\n{'=' * 80}")
    out("FULL TRANSCRIPTION OUTPUTS")
    out(f"{'=' * 80}")

    for entry in all_results:
        name = entry["name"]
        results = entry["results"]
        if not results:
            continue
        out(f"\n--- {name} ---")
        for r in results:
            wer_str = f" (WER: {r['wer']:.0%})" if r["wer"] is not None else ""
            out(f"\n  [{r['file']}] {r['latency']:.2f}s{wer_str}")
            out(f"  {r['text']}")

    if output_path:
        output_path.write_text("\n".join(lines), encoding="utf-8")
        print(f"\nResults saved to {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Benchmark uttr-win STT providers")
    parser.add_argument(
        "--audio-dir", type=Path, default=Path(__file__).parent / "samples",
    )
    parser.add_argument(
        "--providers", type=str, default="fw",
        help="'fw' = faster-whisper sizes, 'nemo' = NeMo, 'onnx' = ONNX, 'all' = everything",
    )
    parser.add_argument(
        "--sizes", type=str, default=None,
        help="Comma-separated faster-whisper sizes to test (default: all)",
    )
    args = parser.parse_args()

    audio_dir = args.audio_dir
    wav_files = sorted(audio_dir.glob("*.wav"))
    if not wav_files:
        print(f"No .wav files in {audio_dir}/")
        print("Run: python benchmarks/record_samples.py")
        sys.exit(1)

    print(f"Audio files: {[w.stem for w in wav_files]}")
    providers = args.providers.lower().split(",")
    all_results = []

    if "fw" in providers or "all" in providers:
        sizes = args.sizes.split(",") if args.sizes else FASTER_WHISPER_SIZES
        print(f"\n{'=' * 60}")
        print(f"FASTER-WHISPER — testing {len(sizes)} model sizes")
        print(f"{'=' * 60}")
        for size in sizes:
            result = benchmark_faster_whisper(size.strip(), wav_files)
            if result:
                all_results.append(result)

    if "nemo" in providers or "all" in providers:
        print(f"\n{'=' * 60}")
        print("NEMO PARAKEET")
        print(f"{'=' * 60}")
        result = benchmark_nemo(wav_files)
        if result:
            all_results.append(result)

    if "onnx" in providers or "all" in providers:
        print(f"\n{'=' * 60}")
        print("ONNX PARAKEET")
        print(f"{'=' * 60}")
        result = benchmark_onnx(wav_files)
        if result:
            all_results.append(result)

    if all_results:
        output_file = audio_dir / "benchmark_results.txt"
        print_summary(all_results, output_path=output_file)


if __name__ == "__main__":
    main()
