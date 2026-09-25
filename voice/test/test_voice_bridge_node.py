from pathlib import Path

from cleannav_voice.models import RecognizedUtterance
from cleannav_voice.voice_bridge_core import VoiceBridgeCore


ROOT = Path(__file__).parents[1]
CATALOG = Path(
    '/home/d1zzy/code/cleannav_modularization/'
    'cleannav-interfaces-filtered/config/task_catalog.yaml'
)


def test_core_processes_utterance_without_ros_or_microphone():
    core = VoiceBridgeCore.from_paths(
        ROOT / 'config' / 'voice_task_map.yaml',
        CATALOG,
    )
    result = core.process_utterance(
        RecognizedUtterance('runtime-1', '先停一下。', 0.87)
    )
    assert result.accepted
    payload = core.factory.build_payload(result.command)
    assert payload.command_id == 'voice:runtime-1'
    assert payload.task_id == 2
    assert payload.raw_text == '先停一下。'
    assert payload.user_confirmed is False
