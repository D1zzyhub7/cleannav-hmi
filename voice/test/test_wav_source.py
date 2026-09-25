from pathlib import Path
import wave

import pytest

from cleannav_voice.audio.wav_source import WavAudioError, WavAudioSource


def write_wav(
    path: Path,
    *,
    channels=1,
    sample_rate_hz=16000,
    sample_width_bytes=2,
    pcm_bytes=b'\x00\x00' * 160,
):
    with wave.open(str(path), 'wb') as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(sample_width_bytes)
        wav_file.setframerate(sample_rate_hz)
        wav_file.writeframes(pcm_bytes)


def test_valid_pcm16_wav_loads_and_source_id_is_deterministic(tmp_path):
    path = tmp_path / 'sample.wav'
    same_content_path = tmp_path / 'nested' / 'same-content.wav'
    same_content_path.parent.mkdir()
    write_wav(path)
    write_wav(same_content_path)
    source = WavAudioSource()

    first = source.load(path)
    second = source.load(path)
    same_content = source.load(same_content_path)

    assert first == second
    assert first.source_id == same_content.source_id
    assert first.source_id.startswith('wav:')
    assert first.sample_rate_hz == 16000
    assert first.channels == 1
    assert first.sample_width_bytes == 2
    assert first.frame_count == 160
    assert first.pcm_bytes == b'\x00\x00' * 160


@pytest.mark.parametrize(
    ('kwargs', 'message'),
    [
        ({'channels': 2}, 'mono'),
        ({'sample_rate_hz': 8000}, '16000 Hz'),
        ({'sample_width_bytes': 1}, 'PCM16'),
        ({'pcm_bytes': b''}, 'audio frames'),
    ],
)
def test_invalid_wav_profiles_fail_closed(tmp_path, kwargs, message):
    path = tmp_path / 'invalid.wav'
    write_wav(path, **kwargs)

    with pytest.raises(WavAudioError, match=message):
        WavAudioSource().load(path)


def test_missing_or_malformed_wav_fails_closed(tmp_path):
    missing = tmp_path / 'missing.wav'
    with pytest.raises(WavAudioError, match='cannot read WAV'):
        WavAudioSource().load(missing)

    malformed = tmp_path / 'malformed.wav'
    malformed.write_bytes(b'not a wav')
    with pytest.raises(WavAudioError, match='cannot read WAV'):
        WavAudioSource().load(malformed)
