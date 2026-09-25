"""Exact normalized phrase matching against the production voice map."""

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
from typing import Mapping

import yaml

from .models import VoiceIntent
from .text_normalizer import TextNormalizer


class VoiceMapError(ValueError):
    """Raised when a voice map violates its frozen contract."""


@dataclass(frozen=True)
class VoiceTaskMap:
    """Validated voice phrase map and its confidence policy."""

    interface_version: str
    confidence_threshold: float
    mappings: Mapping[int, tuple[str, ...]]


def load_voice_task_map(
    path: str | Path,
    normalizer: TextNormalizer | None = None,
) -> VoiceTaskMap:
    """Load and validate one voice map, including phrase uniqueness."""
    map_path = Path(path)
    if not map_path.is_file():
        raise VoiceMapError(f'voice task map does not exist: {map_path}')

    try:
        raw = yaml.safe_load(map_path.read_text(encoding='utf-8'))
    except (OSError, yaml.YAMLError) as exc:
        raise VoiceMapError(f'cannot load voice task map: {map_path}') from exc

    if not isinstance(raw, dict):
        raise VoiceMapError('voice task map root must be a mapping')
    if raw.get('interface_version') != '1.0':
        raise VoiceMapError('voice task map interface_version must be 1.0')

    threshold = raw.get('confidence_threshold')
    if isinstance(threshold, bool) or not isinstance(threshold, (int, float)):
        raise VoiceMapError('confidence_threshold must be a number')
    threshold = float(threshold)
    if not math.isfinite(threshold) or not 0.0 <= threshold <= 1.0:
        raise VoiceMapError('confidence_threshold must be finite in [0, 1]')

    raw_mappings = raw.get('mappings')
    if not isinstance(raw_mappings, dict):
        raise VoiceMapError('mappings must be a mapping')

    normalizer = normalizer or TextNormalizer()
    mappings: dict[int, tuple[str, ...]] = {}
    phrase_to_task: dict[str, int] = {}
    for raw_task_id, raw_phrases in raw_mappings.items():
        if type(raw_task_id) is not int or raw_task_id < 1:
            raise VoiceMapError('mapping task ids must be positive integers')
        if not isinstance(raw_phrases, list) or not raw_phrases:
            raise VoiceMapError(f'mapping {raw_task_id} must contain phrases')

        phrases: list[str] = []
        for phrase in raw_phrases:
            if not isinstance(phrase, str):
                raise VoiceMapError(
                    f'mapping {raw_task_id} has non-string phrase'
                )
            normalized = normalizer.normalize(phrase)
            if not normalized:
                raise VoiceMapError(f'mapping {raw_task_id} has empty phrase')
            previous = phrase_to_task.get(normalized)
            if previous is not None and previous != raw_task_id:
                raise VoiceMapError(
                    f'phrase {normalized!r} maps to tasks '
                    f'{previous} and {raw_task_id}'
                )
            if normalized in phrases:
                raise VoiceMapError(
                    f'mapping {raw_task_id} repeats phrase {normalized!r}'
                )
            phrase_to_task[normalized] = raw_task_id
            phrases.append(normalized)
        mappings[raw_task_id] = tuple(phrases)

    return VoiceTaskMap(
        interface_version='1.0',
        confidence_threshold=threshold,
        mappings=mappings,
    )


class IntentParser:
    """Parse only exact normalized phrases; unknown text returns ``None``."""

    def __init__(
        self,
        voice_map: VoiceTaskMap,
        normalizer: TextNormalizer | None = None,
    ) -> None:
        """Create a parser from a previously validated voice map."""
        self._normalizer = normalizer or TextNormalizer()
        phrase_to_task = {
            phrase: task_id
            for task_id, phrases in voice_map.mappings.items()
            for phrase in phrases
        }
        self._phrase_to_task = phrase_to_task

    def normalize(self, text: str) -> str:
        """Normalize text using the parser's deterministic normalizer."""
        return self._normalizer.normalize(text)

    def parse(self, text: str) -> VoiceIntent | None:
        """Return an intent only for an exact normalized phrase match."""
        normalized = self.normalize(text)
        task_id = self._phrase_to_task.get(normalized)
        if task_id is None:
            return None
        return VoiceIntent(task_id=task_id, normalized_text=normalized)
