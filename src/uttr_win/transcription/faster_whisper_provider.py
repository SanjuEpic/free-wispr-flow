import subprocess
from .base import TranscriptionProvider
from ..logger import setup_logger

log = setup_logger("uttr-win.transcription.faster_whisper")

# Approximate VRAM needed per model (MB) — includes overhead for inference
MODEL_VRAM_MB = {
    "tiny.en": 200,
    "base.en": 300,
    "small.en": 600,
    "medium.en": 1200,
    "distil-medium.en": 900,
    "distil-large-v3": 1500,
    "large-v3-turbo": 1800,
}


def get_free_vram_mb() -> int | None:
    """Query free GPU memory via nvidia-smi. Returns None if no NVIDIA GPU."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return int(result.stdout.strip().splitlines()[0])
    except (FileNotFoundError, ValueError, subprocess.TimeoutExpired):
        pass
    return None


def has_cuda_libs() -> bool:
    """Check if CTranslate2 has CUDA support available."""
    try:
        import ctranslate2
        return "float16" in ctranslate2.get_supported_compute_types("cuda")
    except Exception:
        return False


def has_nvidia_gpu() -> bool:
    """Check if an NVIDIA GPU is present (even without CUDA libs installed)."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0 and bool(result.stdout.strip())
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


class FasterWhisperProvider(TranscriptionProvider):
    # beam_size=5: live use showed beam 3 (the v0.1.2 tune) gave noticeably worse
    # output quality than beam 5 despite a small in-sample WER edge, so we reverted.
    # Batching left off by default — it only speeds long audio and costs ~5 WER.
    def __init__(self, model_size: str = "medium.en", device: str = "auto", compute_type: str = "auto",
                 beam_size: int = 5, use_batched: bool = False, batch_size: int = 8):
        self._model_size = model_size
        self._device = device
        self._compute_type = compute_type
        self._beam_size = beam_size
        self._use_batched = use_batched
        self._batch_size = batch_size
        self._model = None
        self._batched = None
        self._resolved_device = "cpu"

    @property
    def name(self) -> str:
        return f"faster-whisper ({self._model_size}, {self._resolved_device})"

    @property
    def is_ready(self) -> bool:
        return self._model is not None

    @staticmethod
    def _add_cuda_dll_paths():
        import os
        for pkg in ("nvidia.cublas", "nvidia.cudnn", "nvidia.cuda_nvrtc"):
            try:
                mod = __import__(pkg, fromlist=[""])
                for base in mod.__path__:
                    bin_dir = os.path.join(base, "bin")
                    if os.path.isdir(bin_dir) and bin_dir not in os.environ.get("PATH", ""):
                        os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
            except ImportError:
                pass

    def _resolve_device(self) -> str:
        """Pick the best device based on CUDA availability and free VRAM."""
        if self._device != "auto":
            return self._device

        if not has_cuda_libs():
            log.info("CUDA libs not available, using CPU")
            return "cpu"

        free_vram = get_free_vram_mb()
        if free_vram is None:
            log.info("No NVIDIA GPU detected, using CPU")
            return "cpu"

        needed = MODEL_VRAM_MB.get(self._model_size, 1000)
        if free_vram >= needed:
            log.info("GPU has %dMB free (need %dMB for %s) — using CUDA",
                     free_vram, needed, self._model_size)
            return "cuda"
        else:
            log.warning("GPU has only %dMB free (need %dMB for %s) — falling back to CPU",
                        free_vram, needed, self._model_size)
            return "cpu"

    def _resolve_model_source(self) -> str:
        """Return a path/name WhisperModel can load.

        The HuggingFace cache stores model.bin as a symlink into a blobs dir.
        The bundled ctranslate2 in the frozen exe cannot follow those Windows
        symlinks, so in frozen mode we download a flat, symlink-free copy via
        faster_whisper.download_model(output_dir=...) and load from there.
        """
        import os
        import sys
        if not getattr(sys, "frozen", False):
            return self._model_size

        from faster_whisper import download_model
        target = os.path.join(
            os.environ.get("LOCALAPPDATA", ""), "uttr-win", "models-local", self._model_size
        )
        model_bin = os.path.join(target, "model.bin")
        if os.path.isfile(model_bin) and not os.path.islink(model_bin):
            log.info("Using local model copy at %s", target)
            return target

        log.info("Preparing flat (symlink-free) model copy at %s", target)
        return download_model(self._model_size, output_dir=target)

    def prepare(self) -> None:
        import os
        from faster_whisper import WhisperModel

        source = self._resolve_model_source()

        device = self._resolve_device()
        self._resolved_device = device
        compute_type = self._compute_type

        if device == "cuda":
            self._add_cuda_dll_paths()
        if compute_type == "auto":
            compute_type = "float16" if device == "cuda" else "int8"

        cpu_threads = min(os.cpu_count() or 4, 8)

        log.info("Loading model %s on %s (%s, %d threads)",
                 self._model_size, device, compute_type, cpu_threads)
        try:
            self._model = WhisperModel(
                source,
                device=device,
                compute_type=compute_type,
                cpu_threads=cpu_threads,
            )
        except Exception as e:
            if device == "cuda":
                log.warning("CUDA load failed (%s), falling back to CPU", e)
                self._resolved_device = "cpu"
                self._model = WhisperModel(
                    source,
                    device="cpu",
                    compute_type="int8",
                    cpu_threads=cpu_threads,
                )
            else:
                raise
        log.info("Model loaded on %s", self._resolved_device)

        if self._use_batched:
            try:
                from faster_whisper import BatchedInferencePipeline
                self._batched = BatchedInferencePipeline(model=self._model)
                log.info("Batched inference pipeline enabled (batch_size=%d)", self._batch_size)
            except Exception as e:
                log.warning("BatchedInferencePipeline unavailable (%s) — using plain model", e)
                self._batched = None

    def unload(self) -> None:
        """Drop the model so CUDA/ctranslate2 can release its VRAM.

        ctranslate2 has no explicit free() — releasing the last reference and
        forcing a GC pass is what lets the allocator hand memory back. A small
        allocator cache may remain resident, so VRAM may not drop all the way
        to zero. prepare() reloads it on demand.
        """
        if self._model is None:
            return
        import gc
        before = get_free_vram_mb()
        self._batched = None
        self._model = None
        gc.collect()
        after = get_free_vram_mb()
        if before is not None and after is not None:
            log.info("Model unloaded — free VRAM %dMB -> %dMB", before, after)
        else:
            log.info("Model unloaded")

    def transcribe(self, audio_path: str) -> str:
        if not self._model:
            raise RuntimeError("Model not loaded — call prepare() first")
        if self._batched is not None:
            segments, _info = self._batched.transcribe(
                audio_path,
                language="en",
                beam_size=self._beam_size,
                batch_size=self._batch_size,
                vad_filter=True,
            )
        else:
            segments, _info = self._model.transcribe(
                audio_path,
                language="en",
                beam_size=self._beam_size,
                vad_filter=True,
                condition_on_previous_text=False,
            )
        text = " ".join(seg.text.strip() for seg in segments)
        log.info("Transcribed %d chars", len(text))
        return text
