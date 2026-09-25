"""ROS-independent composition of the offline voice pipeline."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .intent_parser import IntentParser, load_voice_task_map
from .models import RecognizedUtterance, VoiceProcessResult
from .task_command_factory import TaskCommandFactory
from .text_normalizer import TextNormalizer
from .voice_policy import (
    VoicePolicy,
    load_task_catalog,
    validate_voice_mappings,
)


@dataclass(frozen=True)
class VoiceBridgeCore:
    """ROS-independent composition of normalization, parsing and policy."""

    parser: IntentParser
    policy: VoicePolicy
    factory: TaskCommandFactory

    @classmethod
    def from_paths(
        cls,
        voice_map_path: str | Path,
        task_catalog_path: str | Path,
        command_valid_for_ms: int = 5000,
    ) -> 'VoiceBridgeCore':
        """Load and validate both production configuration sources."""
        normalizer = TextNormalizer()
        voice_map = load_voice_task_map(voice_map_path, normalizer)
        catalog = load_task_catalog(task_catalog_path)
        validate_voice_mappings(voice_map, catalog)
        return cls(
            parser=IntentParser(voice_map, normalizer),
            policy=VoicePolicy(catalog, voice_map.confidence_threshold),
            factory=TaskCommandFactory(command_valid_for_ms),
        )

    def process_utterance(
        self,
        utterance: RecognizedUtterance,
    ) -> VoiceProcessResult:
        """Process one final ASR result through the domain pipeline."""
        if not isinstance(utterance, RecognizedUtterance):
            raise TypeError('utterance must be RecognizedUtterance')
        normalized = self.parser.normalize(utterance.text)
        intent = self.parser.parse(utterance.text)
        return self.policy.evaluate(utterance, intent, normalized)
