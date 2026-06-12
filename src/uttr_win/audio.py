import tempfile
import threading
import time
import numpy as np
import sounddevice as sd
from scipy.io import wavfile
from .logger import setup_logger

log = setup_logger("uttr-win.audio")

SAMPLE_RATE = 16000
CHANNELS = 1
TAIL_BUFFER_S = 0.6


class AudioRecorder:
    def __init__(self):
        self._frames: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._stream: sd.InputStream | None = None

    def start(self) -> None:
        with self._lock:
            if self._stream is not None:
                try:
                    self._stream.stop()
                    self._stream.close()
                except Exception:
                    pass
            self._frames.clear()
            self._stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=CHANNELS,
                dtype="int16",
                callback=self._callback,
            )
            self._stream.start()
        log.info("Recording started")

    def stop(self) -> str:
        """Stop recording and return path to the temp WAV file.

        Keeps recording for TAIL_BUFFER_S after being called to capture
        trailing speech that may still be in-flight when the user presses
        the hotkey.
        """
        log.info("Capturing %.1fs audio tail buffer...", TAIL_BUFFER_S)
        time.sleep(TAIL_BUFFER_S)

        with self._lock:
            stream = self._stream
            self._stream = None

        if stream:
            stream.stop()
            stream.close()

        with self._lock:
            if not self._frames:
                log.warning("No audio frames captured")
                return ""
            audio = np.concatenate(self._frames, axis=0)
            self._frames.clear()

        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        wavfile.write(tmp.name, SAMPLE_RATE, audio)
        tmp.close()
        duration = len(audio) / SAMPLE_RATE
        log.info("Recording stopped — %.1fs, saved to %s", duration, tmp.name)
        return tmp.name

    @property
    def is_recording(self) -> bool:
        with self._lock:
            return self._stream is not None

    def _callback(self, indata: np.ndarray, frames: int, time_info, status):
        if status:
            log.warning("Audio callback status: %s", status)
        with self._lock:
            self._frames.append(indata.copy())
