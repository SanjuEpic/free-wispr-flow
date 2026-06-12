import numpy as np
from pathlib import Path
from .base import TranscriptionProvider
from ..logger import setup_logger

log = setup_logger("uttr-win.transcription.onnx_parakeet")

HUGGINGFACE_MODEL_ID = "nvidia/parakeet-tdt-0.6b-v2"
ONNX_EXPORT_HELP = (
    "The ONNX Parakeet provider requires a pre-exported ONNX model.\n"
    "The HuggingFace repo 'nvidia/parakeet-tdt-0.6b-v2' contains a NeMo checkpoint, not ONNX.\n"
    "To export:\n"
    "  pip install nemo-toolkit[asr]\n"
    "  python -m nemo.collections.asr.models.asr_model --model_name nvidia/parakeet-tdt-0.6b-v2 --export_to onnx\n"
    "Then set onnx_parakeet.model_path in settings.yaml to the exported directory."
)
SAMPLE_RATE = 16000


def _download_onnx_model(model_id: str) -> Path:
    """Download the Parakeet ONNX model from HuggingFace and return the local path."""
    from huggingface_hub import snapshot_download

    log.info("Downloading ONNX model from %s ...", model_id)
    model_dir = Path(snapshot_download(
        repo_id=model_id,
        allow_patterns=["*.onnx", "*.json", "*.yaml", "tokenizer*", "vocab*"],
    ))
    log.info("Model downloaded to %s", model_dir)
    return model_dir


def _find_onnx_file(model_dir: Path) -> Path:
    onnx_files = list(model_dir.glob("*.onnx"))
    if not onnx_files:
        onnx_files = list(model_dir.rglob("*.onnx"))
    if not onnx_files:
        raise FileNotFoundError(f"No .onnx file found in {model_dir}")
    return onnx_files[0]


def _load_audio(audio_path: str) -> np.ndarray:
    """Load audio file and return float32 numpy array at 16kHz mono."""
    from scipy.io import wavfile

    sr, data = wavfile.read(audio_path)
    if data.dtype == np.int16:
        data = data.astype(np.float32) / 32768.0
    elif data.dtype == np.int32:
        data = data.astype(np.float32) / 2147483648.0
    if len(data.shape) > 1:
        data = data.mean(axis=1)
    if sr != SAMPLE_RATE:
        from scipy.signal import resample
        num_samples = int(len(data) * SAMPLE_RATE / sr)
        data = resample(data, num_samples).astype(np.float32)
    return data


def _compute_mel_spectrogram(audio: np.ndarray, n_mels: int = 80) -> np.ndarray:
    """Compute log-mel spectrogram for Parakeet model input."""
    try:
        import librosa
        mel = librosa.feature.melspectrogram(
            y=audio, sr=SAMPLE_RATE, n_fft=512, hop_length=160,
            win_length=320, n_mels=n_mels, fmin=0, fmax=8000,
        )
        log_mel = 10.0 * np.log10(np.clip(mel, a_min=1e-10, a_max=None))
        return log_mel.astype(np.float32)
    except ImportError:
        raise ImportError(
            "librosa is required for ONNX Parakeet provider. "
            "Install with: pip install uttr-win[onnx]"
        )


class OnnxParakeetProvider(TranscriptionProvider):
    """Parakeet TDT via ONNX Runtime."""

    def __init__(self, model_path: str = ""):
        self._model_path = model_path
        self._session = None
        self._ready = False

    @property
    def name(self) -> str:
        return "Parakeet (ONNX Runtime)"

    @property
    def is_ready(self) -> bool:
        return self._ready

    def prepare(self) -> None:
        try:
            import onnxruntime as ort
        except ImportError:
            raise ImportError(
                "onnxruntime is required. Install with: pip install uttr-win[onnx]"
            )

        if self._model_path:
            model_dir = Path(self._model_path)
        else:
            raise FileNotFoundError(
                "No model_path specified for ONNX Parakeet provider.\n" + ONNX_EXPORT_HELP
            )

        onnx_path = _find_onnx_file(model_dir)
        log.info("Loading ONNX model from %s", onnx_path)

        providers = []
        if "CUDAExecutionProvider" in ort.get_available_providers():
            providers.append("CUDAExecutionProvider")
        if "DmlExecutionProvider" in ort.get_available_providers():
            providers.append("DmlExecutionProvider")
        providers.append("CPUExecutionProvider")

        self._session = ort.InferenceSession(str(onnx_path), providers=providers)
        active = self._session.get_providers()
        log.info("ONNX Runtime providers: %s", active)

        self._load_vocab(model_dir)
        self._ready = True
        log.info("ONNX Parakeet provider ready")

    def _load_vocab(self, model_dir: Path) -> None:
        """Load tokenizer/vocab for decoding output."""
        self._vocab: list[str] = []
        vocab_files = list(model_dir.glob("vocab*")) + list(model_dir.glob("tokenizer*"))
        for vf in vocab_files:
            if vf.suffix == ".json":
                import json
                data = json.loads(vf.read_text(encoding="utf-8"))
                if isinstance(data, list):
                    self._vocab = data
                    break
                elif isinstance(data, dict) and "model" in data:
                    vocab = data.get("model", {}).get("vocab", {})
                    if vocab:
                        self._vocab = [""] * len(vocab)
                        for token, idx in vocab.items():
                            if idx < len(self._vocab):
                                self._vocab[idx] = token
                        break
        if not self._vocab:
            log.warning("Could not load vocab — output will be raw token IDs")

    def transcribe(self, audio_path: str) -> str:
        if not self._session:
            raise RuntimeError("Model not loaded — call prepare() first")

        audio = _load_audio(audio_path)
        mel = _compute_mel_spectrogram(audio)

        # Parakeet expects (batch, n_mels, time)
        mel_input = mel[np.newaxis, :, :]
        length = np.array([mel.shape[1]], dtype=np.int64)

        input_names = [inp.name for inp in self._session.get_inputs()]
        feed = {}
        if len(input_names) >= 2:
            feed[input_names[0]] = mel_input
            feed[input_names[1]] = length
        else:
            feed[input_names[0]] = mel_input

        outputs = self._session.run(None, feed)

        # Decode output tokens
        logits_or_ids = outputs[0]
        if logits_or_ids.ndim == 3:
            token_ids = np.argmax(logits_or_ids, axis=-1)[0]
        else:
            token_ids = logits_or_ids[0]

        text = self._decode_tokens(token_ids)
        log.info("Transcribed %d chars via ONNX Parakeet", len(text))
        return text

    def _decode_tokens(self, token_ids: np.ndarray) -> str:
        if not self._vocab:
            return " ".join(str(t) for t in token_ids)

        tokens = []
        prev_id = -1
        for tid in token_ids:
            tid = int(tid)
            if tid == prev_id:
                continue  # CTC blank/repeat removal
            prev_id = tid
            if tid == 0:
                continue  # blank token
            if tid < len(self._vocab):
                tokens.append(self._vocab[tid])

        # Join and clean up SentencePiece-style tokens
        text = "".join(tokens)
        text = text.replace("▁", " ").strip()
        return text
