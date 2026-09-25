"""WAV to RecognizedUtterance adapter without task or ROS knowledge."""

from __future__ import annotations

import math
from pathlib import Path

from ..audio.wav_source import WavAudioSource
from ..models import RecognizedUtterance
from .base import (
    AsrConfidenceUnavailableError,
    AsrResult,
    InvalidAsrConfidenceError,
    OfflineAsrBackend,
)


class OfflineAsrPipeline:
    """Connect a WAV source and an injected offline ASR backend."""

    def __init__(
        self,
        backend: OfflineAsrBackend,
        audio_source: WavAudioSource | None = None,
    ) -> None:
        """Create a pipeline without loading a backend or model."""
        if not callable(getattr(backend, 'transcribe', None)):
            raise TypeError('backend must provide transcribe(audio)')
        self._backend = backend
        self._audio_source = audio_source or WavAudioSource()

    def transcribe_wav(self, path: str | Path) -> RecognizedUtterance:
        """Load WAV, transcribe it, and validate the raw ASR result."""
        audio = self._audio_source.load(path)
        result = self._backend.transcribe(audio)
        if not isinstance(result, AsrResult):
            raise TypeError('backend must return AsrResult')
        if not isinstance(result.text, str):
            raise TypeError('AsrResult.text must be str')
        confidence = self._validate_confidence(result.confidence)
        return RecognizedUtterance(
            utterance_id=audio.source_id,
            text=result.text,
            confidence=confidence,
            is_final=result.is_final,
        )

    @staticmethod
    def _validate_confidence(confidence: object) -> float:
        if confidence is None:
            raise AsrConfidenceUnavailableError(
                'ASR backend did not provide confidence; refusing to '
                'fabricate one'
            )
        if isinstance(confidence, bool) or not isinstance(
            confidence,
            (int, float),
        ):
            raise InvalidAsrConfidenceError(
                'ASR confidence must be an int or float'
            )
        value = float(confidence)
        if not math.isfinite(value) or not 0.0 <= value <= 1.0:
            raise InvalidAsrConfidenceError(
                'ASR confidence must be finite and in [0, 1]'
            )
        return value
