"""
Parakeet MLX wrapper for speech-to-text processing.
Handles audio preprocessing and Parakeet model integration optimized for Apple Silicon.
"""

import logging
from typing import Dict, Any
from pathlib import Path
from base_STTProvider import BaseSTTProvider


class ParakeetProvider(BaseSTTProvider):
    """Parakeet MLX STT provider optimized for Apple Silicon."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.model = None
        self.logger = logging.getLogger(__name__)
        self._load_model()
    
    def _load_model(self):
        """Load Parakeet MLX model."""
        try:
            from parakeet_mlx import from_pretrained
            
            model_name = self.config.get("model", "mlx-community/parakeet-tdt-0.6b-v3")
            self.logger.info(f"Loading Parakeet model: {model_name}")
            
            # New API: from_pretrained returns just the model
            self.model = from_pretrained(model_name)
            
            self.logger.info("Parakeet model loaded successfully")
            
        except Exception as e:
            self.logger.error(f"Failed to load Parakeet model: {e}")
            raise
    
    def transcribe(self, audio_path: str) -> str:
        """Transcribe audio file using Parakeet MLX."""
        try:
            self.logger.info(f"Transcribing audio: {audio_path}")
            
            # Validate audio file
            if not Path(audio_path).exists():
                raise FileNotFoundError(f"Audio file not found: {audio_path}")
            
            # New API: transcribe is a method on the model
            result = self.model.transcribe(audio_path)
            
            # Extract transcription text from result
            transcription = result.text.strip() if hasattr(result, 'text') else str(result).strip()
            
            self.logger.info(f"Transcription: {transcription}")
            self.logger.info(f"Transcription completed: {len(transcription)} characters")
            
            return transcription
            
        except Exception as e:
            self.logger.error(f"Transcription failed: {e}")
            raise
    
    def is_available(self) -> bool:
        """Check if Parakeet model is loaded and available."""
        return self.model is not None

