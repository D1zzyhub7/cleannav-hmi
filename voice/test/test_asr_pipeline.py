import math

import pytest

from cleannav_voice.asr.base import (
    AsrConfidenceUnavailableError,
    AsrResult,
    InvalidAsrConfidenceError,
)
from cleannav_voice.asr.pipeline import OfflineAsrPipeline
from cleannav_voice.models import RecognizedUtterance
from cleannav_voice.voice_bridge_core import VoiceBridgeCore

from test_wav_source import write_wav


class FakeAsrBackend:
    def __init__(self, result):
        self.result = result
        self.audio = None

    def transcribe(self, audio):
        self.audio = audio
        return self.result


def make_pipeline(tmp_path, result):
    path = tmp_path / 'input.wav'
    write_wav(path)
    backend = FakeAsrBackend(result)
    return OfflineAsrPipeline(backend), path, backend


def write_minimal_task_catalog(tmp_path):
    """Create the smallest valid catalog needed by task 2 integration tests."""
    catalog_path = tmp_path / 'task_catalog.yaml'
    catalog_path.write_text(
        'interface_version: "1.0"\n'
        'tasks:\n'
        '  - id: 2\n'
        '    name: PAUSE_CURRENT_TASK\n'
        '    task_kind: CONTROL\n'
        '    enabled: true\n'
        '    allowed_sources: [VOICE]\n'
        '    requires_confirmation: false\n'
        '    description: "Pause the current task."\n',
        encoding='utf-8',
    )
    return catalog_path


def write_minimal_voice_map(tmp_path):
    """Create a task-2-only map for portable VoiceBridge integration tests."""
    voice_map_path = tmp_path / 'voice_task_map.yaml'
    voice_map_path.write_text(
        'interface_version: "1.0"\n'
        'confidence_threshold: 0.80\n'
        'mappings:\n'
        '  2: ["暂停"]\n',
        encoding='utf-8',
    )
    return voice_map_path


def test_valid_asr_result_becomes_recognized_utterance(tmp_path):
    pipeline, path, backend = make_pipeline(
        tmp_path,
        AsrResult(text='暂停', confidence=0.91),
    )

    utterance = pipeline.transcribe_wav(path)

    assert isinstance(utterance, RecognizedUtterance)
    assert utterance.utterance_id.startswith('wav:')
    assert utterance.text == '暂停'
    assert utterance.confidence == 0.91
    assert utterance.is_final is True
    assert backend.audio is not None


def test_raw_asr_text_and_final_flag_are_preserved(tmp_path):
    pipeline, path, _ = make_pipeline(
        tmp_path,
        AsrResult(text=' 暂停。 ', confidence=0.91, is_final=False),
    )

    utterance = pipeline.transcribe_wav(path)

    assert utterance.text == ' 暂停。 '
    assert utterance.is_final is False


def test_missing_confidence_fails_closed_without_default_value(tmp_path):
    pipeline, path, _ = make_pipeline(
        tmp_path,
        AsrResult(text='暂停', confidence=None),
    )

    with pytest.raises(AsrConfidenceUnavailableError, match='fabricate'):
        pipeline.transcribe_wav(path)


@pytest.mark.parametrize(
    'confidence',
    [float('nan'), float('inf'), -0.1, 1.1, True, '0.9'],
)
def test_invalid_confidence_fails_closed(tmp_path, confidence):
    pipeline, path, _ = make_pipeline(
        tmp_path,
        AsrResult(text='暂停', confidence=confidence),
    )

    with pytest.raises(InvalidAsrConfidenceError):
        pipeline.transcribe_wav(path)


def test_confidence_079_is_valid_asr_data_but_rejected_by_voice_policy(
    tmp_path,
):
    pipeline, path, _ = make_pipeline(
        tmp_path,
        AsrResult(text='暂停', confidence=0.79),
    )
    utterance = pipeline.transcribe_wav(path)
    core = VoiceBridgeCore.from_paths(
        write_minimal_voice_map(tmp_path),
        write_minimal_task_catalog(tmp_path),
    )

    result = core.process_utterance(utterance)

    assert utterance.confidence == 0.79
    assert not result.accepted
    assert result.rejection.reason.value == 'CONFIDENCE_TOO_LOW'


def test_confidence_080_crosses_voice_policy_boundary(tmp_path):
    pipeline, path, _ = make_pipeline(
        tmp_path,
        AsrResult(text='暂停', confidence=0.80),
    )
    utterance = pipeline.transcribe_wav(path)
    core = VoiceBridgeCore.from_paths(
        write_minimal_voice_map(tmp_path),
        write_minimal_task_catalog(tmp_path),
    )

    result = core.process_utterance(utterance)

    assert result.accepted
    assert result.command.intent.task_id == 2


def test_pipeline_does_not_apply_confidence_threshold():
    assert OfflineAsrPipeline._validate_confidence(0.79) == 0.79
    assert math.isclose(OfflineAsrPipeline._validate_confidence(0.80), 0.80)
    normalized = OfflineAsrPipeline._validate_confidence(1)
    assert normalized == 1.0
    assert type(normalized) is float
