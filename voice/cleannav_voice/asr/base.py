"""Offline ASR backend protocol and backend result model."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from ..audio.models import Pcm16Audio


@dataclass(frozen=True)
class AsrResult:
    """Raw result returned by an offline ASR backend."""

    text: str
    confidence: float | None
    is_final: bool = True


class OfflineAsrBackend(Protocol):
    """Interface implemented by a future offline ASR backend."""

    def transcribe(self, audio: Pcm16Audio) -> AsrResult:
        """Transcribe one validated PCM16 audio payload."""
        ...


class AsrConfidenceUnavailableError(ValueError):
    """Raised when a backend cannot provide a reliable confidence value."""


class InvalidAsrConfidenceError(ValueError):
    """Raised when a backend returns a malformed confidence value."""
