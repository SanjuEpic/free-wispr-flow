from .base import TranscriptionProvider


def get_provider(provider_id: str, settings: dict | None = None) -> TranscriptionProvider:
    settings = settings or {}

    if provider_id == "faster-whisper":
        from .faster_whisper_provider import FasterWhisperProvider
        cfg = settings.get("faster_whisper", {})
        return FasterWhisperProvider(
            model_size=cfg.get("model", "medium.en"),
            device=cfg.get("device", "auto"),
            compute_type=cfg.get("compute_type", "auto"),
        )
    elif provider_id == "onnx-parakeet":
        from .onnx_parakeet_provider import OnnxParakeetProvider
        cfg = settings.get("onnx_parakeet", {})
        return OnnxParakeetProvider(model_path=cfg.get("model_path", ""))
    elif provider_id == "nemo-parakeet":
        from .nemo_parakeet_provider import NemoParakeetProvider
        cfg = settings.get("nemo_parakeet", {})
        return NemoParakeetProvider(model_name=cfg.get("model_name", "nvidia/parakeet-tdt-0.6b-v2"))
    else:
        raise ValueError(f"Unknown provider: {provider_id}")
