"""ROS-independent value objects used by the voice pipeline."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


@dataclass(frozen=True)
class RecognizedUtterance:
    """One final result emitted by an ASR backend."""

    utterance_id: str
    text: str
    confidence: float
    is_final: bool = True


@dataclass(frozen=True)
class VoiceIntent:
    """Exact-match result from the production voice task map."""

    task_id: int
    normalized_text: str


class RejectionReason(str, Enum):
    """Internal, non-ROS rejection reasons for diagnostics and tests."""

    EMPTY_TEXT = 'EMPTY_TEXT'
    UNKNOWN_INTENT = 'UNKNOWN_INTENT'
    CONFIDENCE_TOO_LOW = 'CONFIDENCE_TOO_LOW'
    CONFIDENCE_INVALID = 'CONFIDENCE_INVALID'
    TASK_UNKNOWN = 'TASK_UNKNOWN'
    TASK_DISABLED = 'TASK_DISABLED'
    VOICE_NOT_ALLOWED = 'VOICE_NOT_ALLOWED'
    CONFIRMATION_TASK_FORBIDDEN = 'CONFIRMATION_TASK_FORBIDDEN'
    FORBIDDEN_TASK = 'FORBIDDEN_TASK'
    NOT_FINAL = 'NOT_FINAL'


@dataclass(frozen=True)
class VoiceTaskMetadata:
    """Task Catalog fields needed by VoicePolicy."""

    task_id: int
    enabled: bool
    allowed_sources: frozenset[str]
    requires_confirmation: bool


@dataclass(frozen=True)
class AcceptedVoiceCommand:
    """A policy-approved utterance ready for TaskCommand construction."""

    utterance: RecognizedUtterance
    intent: VoiceIntent


@dataclass(frozen=True)
class VoiceRejection:
    """A rejected utterance and the reason it was not published."""

    reason: RejectionReason
    normalized_text: str = ''


@dataclass(frozen=True)
class VoiceProcessResult:
    """Result of one VoiceBridgeCore processing attempt."""

    accepted: bool
    command: AcceptedVoiceCommand | None = None
    rejection: VoiceRejection | None = None
