"""Smoke test for the unload/reload cycle (manual run, not shipped)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from uttr_win.transcription.faster_whisper_provider import (  # noqa: E402
    FasterWhisperProvider,
    get_free_vram_mb,
)

WAV = str(Path(__file__).resolve().parent / "samples" / "short.wav")


def main() -> int:
    p = FasterWhisperProvider(model_size="small.en", device="auto", compute_type="auto")

    print(f"[1] free VRAM before load: {get_free_vram_mb()} MB")
    p.prepare()
    assert p.is_ready, "model not ready after prepare()"
    print(f"    resolved device: {p._resolved_device}, free VRAM after load: {get_free_vram_mb()} MB")

    t1 = p.transcribe(WAV)
    assert t1.strip(), "first transcription empty"
    print(f"[2] transcribe #1: {t1!r}")

    p.unload()
    assert not p.is_ready, "is_ready should be False after unload()"
    print(f"[3] after unload: is_ready={p.is_ready}, free VRAM: {get_free_vram_mb()} MB")

    p.prepare()
    assert p.is_ready, "model not ready after reload"
    t2 = p.transcribe(WAV)
    assert t2.strip(), "second transcription empty"
    print(f"[4] reload + transcribe #2: {t2!r}")

    print("\nPASS: unload -> reload -> transcribe cycle works")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
