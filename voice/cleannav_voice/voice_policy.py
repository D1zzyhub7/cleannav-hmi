"""ROS-independent voice acceptance policy and Task Catalog validation."""

from __future__ import annotations

import math
from pathlib import Path
from typing import Mapping

import yaml

from .intent_parser import VoiceTaskMap
from .models import (
    AcceptedVoiceCommand,
    RecognizedUtterance,
    RejectionReason,
    VoiceIntent,
    VoiceProcessResult,
    VoiceRejection,
    VoiceTaskMetadata,
)


FORBIDDEN_VOICE_TASK_IDS = frozenset({7})


class TaskCatalogError(ValueError):
    """Raised when the installed Task Catalog is unavailable or invalid."""


def load_task_catalog(path: str | Path) -> dict[int, VoiceTaskMetadata]:
    """Load the installed Task Catalog fields needed by VoicePolicy."""
    catalog_path = Path(path)
    if not catalog_path.is_file():
        raise TaskCatalogError(f'task catalog does not exist: {catalog_path}')
    try:
        raw = yaml.safe_load(catalog_path.read_text(encoding='utf-8'))
    except (OSError, yaml.YAMLError) as exc:
        raise TaskCatalogError(
            f'cannot load task catalog: {catalog_path}'
        ) from exc

    if not isinstance(raw, dict) or raw.get('interface_version') != '1.0':
        raise TaskCatalogError('task catalog interface_version must be 1.0')
    raw_tasks = raw.get('tasks')
    if not isinstance(raw_tasks, list):
        raise TaskCatalogError('task catalog tasks must be a list')

    catalog: dict[int, VoiceTaskMetadata] = {}
    for raw_task in raw_tasks:
        if not isinstance(raw_task, dict):
            raise TaskCatalogError('each task catalog entry must be a mapping')
        task_id = raw_task.get('id')
        if type(task_id) is not int:
            raise TaskCatalogError('task catalog id must be an integer')
        if task_id in catalog:
            raise TaskCatalogError(f'duplicate task catalog id: {task_id}')
        allowed = raw_task.get('allowed_sources')
        if not isinstance(allowed, list) or not all(
            isinstance(source, str) for source in allowed
        ):
            raise TaskCatalogError(
                f'task {task_id} allowed_sources is invalid'
            )
        enabled = raw_task.get('enabled')
        requires_confirmation = raw_task.get('requires_confirmation')
        if not isinstance(enabled, bool) or not isinstance(
            requires_confirmation, bool
        ):
            raise TaskCatalogError(f'task {task_id} flags are invalid')
        catalog[task_id] = VoiceTaskMetadata(
            task_id=task_id,
            enabled=enabled,
            allowed_sources=frozenset(allowed),
            requires_confirmation=requires_confirmation,
        )
    return catalog


def validate_voice_mappings(
    voice_map: VoiceTaskMap,
    catalog: Mapping[int, VoiceTaskMetadata],
) -> None:
    """Fail closed if any production mapping lacks Task Catalog authority."""
    for task_id in voice_map.mappings:
        if task_id in FORBIDDEN_VOICE_TASK_IDS:
            raise TaskCatalogError(
                f'task {task_id} is permanently voice-forbidden'
            )
        task = catalog.get(task_id)
        if task is None:
            raise TaskCatalogError(f'mapped task {task_id} is unknown')
        if not task.enabled:
            raise TaskCatalogError(f'mapped task {task_id} is disabled')
        if 'VOICE' not in task.allowed_sources:
            raise TaskCatalogError(f'task {task_id} does not allow VOICE')
        if task.requires_confirmation:
            raise TaskCatalogError(
                f'task {task_id} requires confirmation and cannot be '
                'voice-mapped'
            )


class VoicePolicy:
    """Apply final-only, confidence and Task Catalog policy checks."""

    def __init__(
        self,
        catalog: Mapping[int, VoiceTaskMetadata],
        confidence_threshold: float,
        forbidden_task_ids: frozenset[int] = FORBIDDEN_VOICE_TASK_IDS,
    ) -> None:
        """Create a policy bound to one validated Task Catalog snapshot."""
        if (
            not math.isfinite(confidence_threshold)
            or not 0.0 <= confidence_threshold <= 1.0
        ):
            raise ValueError('confidence_threshold must be finite in [0, 1]')
        self._catalog = catalog
        self._confidence_threshold = confidence_threshold
        self._forbidden_task_ids = forbidden_task_ids

    def evaluate(
        self,
        utterance: RecognizedUtterance,
        intent: VoiceIntent | None,
        normalized_text: str,
    ) -> VoiceProcessResult:
        """Return an accepted command or an explicit internal rejection."""
        if not utterance.is_final:
            return self._reject(RejectionReason.NOT_FINAL, normalized_text)
        if not normalized_text:
            return self._reject(RejectionReason.EMPTY_TEXT, normalized_text)
        if not self._valid_confidence(utterance.confidence):
            return self._reject(
                RejectionReason.CONFIDENCE_INVALID,
                normalized_text,
            )
        if utterance.confidence < self._confidence_threshold:
            return self._reject(
                RejectionReason.CONFIDENCE_TOO_LOW,
                normalized_text,
            )
        if intent is None:
            return self._reject(
                RejectionReason.UNKNOWN_INTENT,
                normalized_text,
            )

        task = self._catalog.get(intent.task_id)
        if task is None:
            return self._reject(RejectionReason.TASK_UNKNOWN, normalized_text)
        if not task.enabled:
            return self._reject(RejectionReason.TASK_DISABLED, normalized_text)
        if 'VOICE' not in task.allowed_sources:
            return self._reject(
                RejectionReason.VOICE_NOT_ALLOWED,
                normalized_text,
            )
        if task.requires_confirmation:
            return self._reject(
                RejectionReason.CONFIRMATION_TASK_FORBIDDEN,
                normalized_text,
            )
        if task.task_id in self._forbidden_task_ids:
            return self._reject(
                RejectionReason.FORBIDDEN_TASK,
                normalized_text,
            )
        return VoiceProcessResult(
            accepted=True,
            command=AcceptedVoiceCommand(utterance=utterance, intent=intent),
        )

    @staticmethod
    def _valid_confidence(confidence: object) -> bool:
        if isinstance(confidence, bool) or not isinstance(
            confidence,
            (int, float),
        ):
            return False
        value = float(confidence)
        return math.isfinite(value) and 0.0 <= value <= 1.0

    @staticmethod
    def _reject(
        reason: RejectionReason,
        normalized_text: str,
    ) -> VoiceProcessResult:
        return VoiceProcessResult(
            accepted=False,
            rejection=VoiceRejection(
                reason=reason,
                normalized_text=normalized_text,
            ),
        )
