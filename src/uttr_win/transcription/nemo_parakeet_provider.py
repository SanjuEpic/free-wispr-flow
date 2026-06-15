from .base import TranscriptionProvider
from ..logger import setup_logger

log = setup_logger("uttr-win.transcription.nemo_parakeet")

SAMPLE_RATE = 16000


class NemoParakeetProvider(TranscriptionProvider):
    """Parakeet TDT via NVIDIA NeMo toolkit."""

    def __init__(self, model_name: str = "nvidia/parakeet-tdt-0.6b-v2"):
        self._model_name = model_name
        self._model = None

    @property
    def name(self) -> str:
        return f"Parakeet (NeMo: {self._model_name})"

    @property
    def is_ready(self) -> bool:
        return self._model is not None

    def unload(self) -> None:
        if self._model is None:
            return
        import gc
        self._model = None
        gc.collect()
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except ImportError:
            pass
        log.info("NeMo model unloaded")

    def prepare(self) -> None:
        try:
            import nemo.collections.asr as nemo_asr
        except ImportError:
            raise ImportError(
                "NeMo toolkit is required. Install with: pip install uttr-win[nemo]"
            )

        log.info("Loading NeMo model: %s", self._model_name)
        self._model = nemo_asr.models.ASRModel.from_pretrained(model_name=self._model_name)

        # Move to GPU if available
        try:
            import torch
            if torch.cuda.is_available():
                self._model = self._model.cuda()
                log.info("NeMo model moved to CUDA")
        except ImportError:
            pass

        log.info("NeMo Parakeet provider ready")

    def transcribe(self, audio_path: str) -> str:
        if not self._model:
            raise RuntimeError("Model not loaded — call prepare() first")

        results = self._model.transcribe([audio_path])

        # NeMo returns different formats depending on version
        if isinstance(results, list):
            if len(results) > 0:
                item = results[0]
                if isinstance(item, str):
                    text = item
                elif hasattr(item, "text"):
                    text = item.text
                else:
                    text = str(item)
            else:
                text = ""
        elif hasattr(results, "text"):
            text = results.text[0] if isinstance(results.text, list) else results.text
        else:
            text = str(results)

        log.info("Transcribed %d chars via NeMo Parakeet", len(text))
        return text
