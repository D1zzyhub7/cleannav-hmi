"""ROS-independent offline ASR contracts and pipeline."""

from .base import (
    AsrConfidenceUnavailableError,
    AsrResult,
    InvalidAsrConfidenceError,
    OfflineAsrBackend,
)
from .pipeline import OfflineAsrPipeline

__all__ = [
    'AsrConfidenceUnavailableError',
    'AsrResult',
    'InvalidAsrConfidenceError',
    'OfflineAsrBackend',
    'OfflineAsrPipeline',
]
