from pathlib import Path

import pytest

from cleannav_voice.intent_parser import IntentParser, load_voice_task_map
from cleannav_voice.models import RecognizedUtterance, RejectionReason
from cleannav_voice.voice_policy import (
    TaskCatalogError,
    VoicePolicy,
    load_task_catalog,
    validate_voice_mappings,
)


ROOT = Path(__file__).parents[1]
CATALOG = Path(
    '/home/d1zzy/code/cleannav_modularization/'
    'cleannav-interfaces-filtered/config/task_catalog.yaml'
)


def make_policy():
    voice_map = load_voice_task_map(ROOT / 'config' / 'voice_task_map.yaml')
    catalog = load_task_catalog(CATALOG)
    validate_voice_mappings(voice_map, catalog)
    return IntentParser(voice_map), VoicePolicy(catalog, 0.8)


@pytest.mark.parametrize(
    ('text', 'task_id'),
    [
        ('暂停', 2),
        ('继续', 3),
        ('停止任务', 4),
        ('紧急停止', 6),
        ('清扫最近的落叶', 30),
        ('清扫最近的落叶堆', 31),
        ('清扫最近的积水', 32),
    ],
)
def test_allowed_voice_commands_are_accepted(text, task_id):
    parser, policy = make_policy()
    utterance = RecognizedUtterance('id-' + str(task_id), text, 0.8)
    result = policy.evaluate(
        utterance,
        parser.parse(text),
        parser.normalize(text),
    )
    assert result.accepted
    assert result.command.intent.task_id == task_id
    assert result.command.utterance.confidence == 0.8


@pytest.mark.parametrize(
    'text',
    [
        '解除急停',
        '恢复急停',
        '清扫最重要的目标',
        '开始清扫',
        '返回',
        '前方五米',
        '未知文本',
    ],
)
def test_unknown_or_disabled_voice_commands_are_rejected(text):
    parser, policy = make_policy()
    result = policy.evaluate(
        RecognizedUtterance('unknown-' + text, text, 1.0),
        parser.parse(text),
        parser.normalize(text),
    )
    assert not result.accepted
    assert result.rejection.reason == RejectionReason.UNKNOWN_INTENT


@pytest.mark.parametrize(
    ('confidence', 'reason'),
    [
        (0.79, RejectionReason.CONFIDENCE_TOO_LOW),
        (float('nan'), RejectionReason.CONFIDENCE_INVALID),
        (float('inf'), RejectionReason.CONFIDENCE_INVALID),
        (-0.1, RejectionReason.CONFIDENCE_INVALID),
        (1.1, RejectionReason.CONFIDENCE_INVALID),
    ],
)
def test_confidence_policy(confidence, reason):
    parser, policy = make_policy()
    result = policy.evaluate(
        RecognizedUtterance('confidence', '暂停', confidence),
        parser.parse('暂停'),
        '暂停',
    )
    assert not result.accepted
    assert result.rejection.reason == reason


def test_non_final_result_is_rejected():
    parser, policy = make_policy()
    result = policy.evaluate(
        RecognizedUtterance('partial', '暂停', 1.0, is_final=False),
        parser.parse('暂停'),
        '暂停',
    )
    assert result.rejection.reason == RejectionReason.NOT_FINAL


def test_task_catalog_mapping_validation_fails_closed_forbidden_and_invalid(
    tmp_path,
):
    catalog = load_task_catalog(CATALOG)
    for task_id in (7, 33, 99):
        voice_map_path = tmp_path / f'map-{task_id}.yaml'
        voice_map_path.write_text(
            'interface_version: "1.0"\nconfidence_threshold: 0.8\n'
            f'mappings:\n  {task_id}: ["测试"]\n',
            encoding='utf-8',
        )
        candidate = load_voice_task_map(voice_map_path)
        with pytest.raises(TaskCatalogError):
            validate_voice_mappings(candidate, catalog)
