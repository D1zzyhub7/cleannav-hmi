"""Build the frozen CleanNav TaskCommand without inventing voice interfaces."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re

from .models import AcceptedVoiceCommand


_SAFE_ID = re.compile(r'^[A-Za-z0-9._:-]+$')
_COMMAND_PREFIX = 'voice:'


@dataclass(frozen=True)
class TaskCommandPayload:
    """ROS-independent payload for one TaskCommand message."""

    command_id: str
    source: int
    task_id: int
    confidence: float
    raw_text: str
    valid_for_ns: int
    user_confirmed: bool = False
    interface_version: str = '1.0'


def stable_command_id(utterance_id: str) -> str:
    """Derive a deterministic valid command_id from an ASR final identity."""
    if not isinstance(utterance_id, str):
        raise TypeError('utterance_id must be str')
    if (
        utterance_id
        and len(_COMMAND_PREFIX + utterance_id) <= 128
        and _SAFE_ID.fullmatch(utterance_id)
    ):
        return _COMMAND_PREFIX + utterance_id
    digest = hashlib.sha256(utterance_id.encode('utf-8')).hexdigest()
    return _COMMAND_PREFIX + digest


class TaskCommandFactory:
    """Create TaskCommand payloads with fixed Voice semantics."""

    def __init__(self, valid_for_ms: int = 5000) -> None:
        """Create a factory with a positive command validity duration."""
        if isinstance(valid_for_ms, bool) or not isinstance(valid_for_ms, int):
            raise TypeError('valid_for_ms must be int')
        if valid_for_ms <= 0:
            raise ValueError('valid_for_ms must be > 0')
        self._valid_for_ns = valid_for_ms * 1_000_000

    @property
    def valid_for_ns(self) -> int:
        """Return the configured validity duration in nanoseconds."""
        return self._valid_for_ns

    def build_payload(
        self,
        accepted: AcceptedVoiceCommand,
    ) -> TaskCommandPayload:
        """Build a payload from a policy-approved command."""
        utterance = accepted.utterance
        return TaskCommandPayload(
            command_id=stable_command_id(utterance.utterance_id),
            source=1,
            task_id=accepted.intent.task_id,
            confidence=float(utterance.confidence),
            raw_text=utterance.text,
            valid_for_ns=self._valid_for_ns,
            user_confirmed=False,
        )

    def to_ros_message(self, payload: TaskCommandPayload, stamp) -> object:
        """Convert a payload to the existing cleannav_interfaces message."""
        from cleannav_interfaces.msg import TaskCommand

        message = TaskCommand()
        message.header.frame_id = ''
        message.header.stamp = stamp
        message.interface_version = payload.interface_version
        message.command_id = payload.command_id
        message.source = TaskCommand.SOURCE_VOICE
        message.task_id = payload.task_id
        message.confidence = payload.confidence
        message.raw_text = payload.raw_text
        message.valid_for.sec = payload.valid_for_ns // 1_000_000_000
        message.valid_for.nanosec = payload.valid_for_ns % 1_000_000_000
        message.user_confirmed = False
        return message
