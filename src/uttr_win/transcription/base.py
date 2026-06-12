from abc import ABC, abstractmethod


class TranscriptionProvider(ABC):
    @abstractmethod
    def prepare(self) -> None:
        """Load model into memory. Called once at startup or on provider switch."""

    @abstractmethod
    def transcribe(self, audio_path: str) -> str:
        """Transcribe a WAV file and return the text."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable provider name."""

    @property
    def is_ready(self) -> bool:
        return True
