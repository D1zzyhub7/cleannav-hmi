"""Immutable PCM audio data objects for the offline ASR boundary."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Pcm16Audio:
    """Validated mono 16 kHz signed PCM16 audio payload."""

    source_id: str
    sample_rate_hz: int
    channels: int
    sample_width_bytes: int
    frame_count: int
    pcm_bytes: bytes

    def __post_init__(self) -> None:
        """Reject malformed audio objects at the domain boundary."""
        if not isinstance(self.source_id, str) or not self.source_id:
            raise ValueError('source_id must be a non-empty string')
        if self.sample_rate_hz != 16000:
            raise ValueError('sample_rate_hz must be 16000')
        if self.channels != 1:
            raise ValueError('channels must be 1')
        if self.sample_width_bytes != 2:
            raise ValueError('sample_width_bytes must be 2')
        if not isinstance(self.frame_count, int) or self.frame_count <= 0:
            raise ValueError('frame_count must be a positive integer')
        if not isinstance(self.pcm_bytes, bytes) or not self.pcm_bytes:
            raise ValueError('pcm_bytes must be non-empty bytes')
        expected_size = (
            self.frame_count * self.channels * self.sample_width_bytes
        )
        if len(self.pcm_bytes) != expected_size:
            raise ValueError(
                'pcm_bytes length does not match frame_count and format'
            )
