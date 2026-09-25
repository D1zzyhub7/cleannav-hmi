from pathlib import Path

import pytest

from cleannav_voice.intent_parser import (
    IntentParser,
    VoiceMapError,
    load_voice_task_map,
)


ROOT = Path(__file__).parents[1]


def test_production_map_parses_exact_phrases():
    voice_map = load_voice_task_map(ROOT / 'config' / 'voice_task_map.yaml')
    parser = IntentParser(voice_map)
    assert parser.parse('先停一下。').task_id == 2
    assert parser.parse('清扫最近的积水').task_id == 32
    assert parser.parse('前方五米') is None


def test_duplicate_normalized_phrase_fails(tmp_path):
    path = tmp_path / 'map.yaml'
    path.write_text(
        'interface_version: "1.0"\n'
        'confidence_threshold: 0.8\n'
        'mappings:\n'
        '  2: ["暂停"]\n'
        '  3: ["暂停。"]\n',
        encoding='utf-8',
    )
    with pytest.raises(VoiceMapError, match='maps to tasks'):
        load_voice_task_map(path)
