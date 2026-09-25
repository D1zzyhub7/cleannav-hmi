from cleannav_voice.models import (
    AcceptedVoiceCommand,
    RecognizedUtterance,
    VoiceIntent,
)
from cleannav_voice.task_command_factory import (
    TaskCommandFactory,
    stable_command_id,
)


def accepted(utterance_id='abc123', raw_text='暂停', confidence=0.91):
    return AcceptedVoiceCommand(
        utterance=RecognizedUtterance(utterance_id, raw_text, confidence),
        intent=VoiceIntent(2, '暂停'),
    )


def test_command_id_is_stable_and_semantics_are_frozen():
    factory = TaskCommandFactory(5000)
    first = factory.build_payload(accepted())
    retry = factory.build_payload(accepted(raw_text='暂停。'))
    different = factory.build_payload(accepted('different'))
    assert first.command_id == retry.command_id == 'voice:abc123'
    assert first.command_id != different.command_id
    assert first.source == 1
    assert first.user_confirmed is False
    assert first.raw_text == '暂停'
    assert first.valid_for_ns == 5_000_000_000


def test_invalid_or_long_utterance_id_uses_hash():
    command_id = stable_command_id('not valid/for command id')
    assert command_id.startswith('voice:')
    assert len(command_id) <= 128
    assert stable_command_id('not valid/for command id') == command_id
    assert stable_command_id('a' * 123).startswith('voice:')
