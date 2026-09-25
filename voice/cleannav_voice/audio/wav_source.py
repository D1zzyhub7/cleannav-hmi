"""Strict standard-library WAV input for the offline ASR boundary."""

from __future__ import annotations

import hashlib
from pathlib import Path
import wave

from .models import Pcm16Audio


class WavAudioError(ValueError):
    """Raised when a WAV file is outside the production PCM16 profile."""


class WavAudioSource:
    """Load only non-empty mono 16 kHz PCM16 WAV files."""

    def load(self, path: str | Path) -> Pcm16Audio:
        """Read and validate one WAV file without resampling or conversion."""
        wav_path = Path(path)
        try:
            with wave.open(str(wav_path), 'rb') as wav_file:
                channels = wav_file.getnchannels()
                sample_rate_hz = wav_file.getframerate()
                sample_width_bytes = wav_file.getsampwidth()
                frame_count = wav_file.getnframes()
                compression = wav_file.getcomptype()
                self._validate_header(
                    wav_path,
                    channels=channels,
                    sample_rate_hz=sample_rate_hz,
                    sample_width_bytes=sample_width_bytes,
                    frame_count=frame_count,
                    compression=compression,
                )
                pcm_bytes = wav_file.readframes(frame_count)
        except WavAudioError:
            raise
        except (OSError, EOFError, wave.Error) as exc:
            raise WavAudioError(
                f'cannot read WAV file {wav_path}: {exc}'
            ) from exc

        expected_size = frame_count * channels * sample_width_bytes
        if len(pcm_bytes) != expected_size or not pcm_bytes:
            raise WavAudioError(
                f'WAV file {wav_path} has empty or truncated PCM data'
            )

        source_id = self._source_id(
            sample_rate_hz=sample_rate_hz,
            channels=channels,
            sample_width_bytes=sample_width_bytes,
            frame_count=frame_count,
            pcm_bytes=pcm_bytes,
        )
        try:
            return Pcm16Audio(
                source_id=source_id,
                sample_rate_hz=sample_rate_hz,
                channels=channels,
                sample_width_bytes=sample_width_bytes,
                frame_count=frame_count,
                pcm_bytes=pcm_bytes,
            )
        except ValueError as exc:
            raise WavAudioError(
                f'WAV file {wav_path} does not match PCM16 profile: {exc}'
            ) from exc

    @staticmethod
    def _validate_header(
        path: Path,
        *,
        channels: int,
        sample_rate_hz: int,
        sample_width_bytes: int,
        frame_count: int,
        compression: str,
    ) -> None:
        if channels != 1:
            raise WavAudioError(
                f'WAV file {path} must be mono, got channels={channels}'
            )
        if sample_rate_hz != 16000:
            raise WavAudioError(
                f'WAV file {path} must be 16000 Hz, '
                f'got {sample_rate_hz} Hz'
            )
        if sample_width_bytes != 2:
            raise WavAudioError(
                f'WAV file {path} must be PCM16, '
                f'got sample_width_bytes={sample_width_bytes}'
            )
        if compression != 'NONE':
            raise WavAudioError(
                f'WAV file {path} must be uncompressed PCM, '
                f'got compression={compression!r}'
            )
        if frame_count <= 0:
            raise WavAudioError(f'WAV file {path} must contain audio frames')

    @staticmethod
    def _source_id(
        *,
        sample_rate_hz: int,
        channels: int,
        sample_width_bytes: int,
        frame_count: int,
        pcm_bytes: bytes,
    ) -> str:
        """Return a deterministic identity from format and PCM content."""
        digest = hashlib.sha256()
        digest.update(
            f'pcm16:{sample_rate_hz}:{channels}:{sample_width_bytes}:'
            f'{frame_count}:'.encode('ascii')
        )
        digest.update(pcm_bytes)
        return f'wav:{digest.hexdigest()}'
