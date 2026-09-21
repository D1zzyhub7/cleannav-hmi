"""Thread-safe RobotStatus and TaskStatus snapshots for the HTTP API."""

from __future__ import annotations

from copy import deepcopy
from threading import RLock

from cleannav_interfaces.msg import RobotStatus, TaskStatus


SYSTEM_STATE_NAMES = {
    RobotStatus.SYSTEM_UNKNOWN: 'SYSTEM_UNKNOWN',
    RobotStatus.SYSTEM_READY: 'SYSTEM_READY',
    RobotStatus.SYSTEM_BUSY: 'SYSTEM_BUSY',
    RobotStatus.SYSTEM_PAUSED: 'SYSTEM_PAUSED',
    RobotStatus.SYSTEM_BLOCKED: 'SYSTEM_BLOCKED',
    RobotStatus.SYSTEM_ERROR: 'SYSTEM_ERROR',
    RobotStatus.SYSTEM_EMERGENCY_STOP: 'SYSTEM_EMERGENCY_STOP',
}

TASK_STATE_NAMES = {
    TaskStatus.STATE_UNKNOWN: 'UNKNOWN',
    TaskStatus.STATE_IDLE: 'IDLE',
    TaskStatus.STATE_ACCEPTED: 'ACCEPTED',
    TaskStatus.STATE_REJECTED: 'REJECTED',
    TaskStatus.STATE_QUEUED: 'QUEUED',
    TaskStatus.STATE_WAITING_TARGET: 'WAITING_TARGET',
    TaskStatus.STATE_PREPARING: 'PREPARING',
    TaskStatus.STATE_NAVIGATING: 'NAVIGATING',
    TaskStatus.STATE_PAUSING: 'PAUSING',
    TaskStatus.STATE_PAUSED: 'PAUSED',
    TaskStatus.STATE_CANCELING: 'CANCELING',
    TaskStatus.STATE_RETURNING_HOME: 'RETURNING_HOME',
    TaskStatus.STATE_SAFETY_BLOCKED: 'SAFETY_BLOCKED',
    TaskStatus.STATE_SUCCEEDED: 'SUCCEEDED',
    TaskStatus.STATE_CANCELED: 'CANCELED',
    TaskStatus.STATE_FAILED: 'FAILED',
    TaskStatus.STATE_EMERGENCY_STOPPED: 'EMERGENCY_STOPPED',
}


def _task_dict(message: TaskStatus) -> dict:
    """Convert one TaskStatus while preserving its numeric contract."""
    return {
        'execution_id': message.execution_id,
        'command_id': message.command_id,
        'task_id': int(message.task_id),
        'status_scope': int(message.status_scope),
        'status_scope_name': (
            'EXECUTION'
            if message.status_scope == TaskStatus.SCOPE_EXECUTION
            else 'COMMAND'
        ),
        'state': TASK_STATE_NAMES.get(int(message.state), 'UNKNOWN'),
        'state_code': int(message.state),
        'progress': float(message.progress),
        'active_target_id': message.active_target_id,
        'remaining_distance_m': float(message.remaining_distance_m),
        'reason_code': int(message.reason_code),
        'message': message.message,
    }


def _default_robot() -> dict:
    return {
        'system_state': 'SYSTEM_UNKNOWN',
        'system_state_code': RobotStatus.SYSTEM_UNKNOWN,
        'localization_ok': False,
        'navigation_active': False,
        'emergency_stop': False,
        'autonomous_enabled': False,
        'message': '尚未收到 RobotStatus',
    }


def _default_task() -> dict:
    return {
        'execution_id': '',
        'command_id': '',
        'task_id': 0,
        'status_scope': TaskStatus.SCOPE_UNKNOWN,
        'status_scope_name': 'UNKNOWN',
        'state': 'UNKNOWN',
        'state_code': TaskStatus.STATE_UNKNOWN,
        'progress': 0.0,
        'active_target_id': '',
        'remaining_distance_m': 0.0,
        'reason_code': 0,
        'message': '尚未收到 TaskStatus',
    }


class StatusCache:
    """Keep separate command and execution status scopes for HMI reads."""

    def __init__(self) -> None:
        self._lock = RLock()
        self._robot: dict | None = None
        self._latest_command_status: dict | None = None
        self._latest_execution_status: dict | None = None

    def update_robot(self, message: RobotStatus) -> None:
        """Store one RobotStatus message as canonical JSON fields."""
        if not isinstance(message, RobotStatus):
            raise TypeError('message must be RobotStatus')
        robot = {
            'system_state': SYSTEM_STATE_NAMES.get(
                int(message.system_state), 'SYSTEM_UNKNOWN'),
            'system_state_code': int(message.system_state),
            'localization_ok': bool(message.localization_ok),
            'navigation_active': bool(message.navigation_active),
            'emergency_stop': bool(message.emergency_stop_active),
            'emergency_stop_active': bool(message.emergency_stop_active),
            'autonomous_enabled': bool(message.autonomous_enabled),
            'linear_velocity_mps': float(message.linear_velocity_mps),
            'angular_velocity_rps': float(message.angular_velocity_rps),
            'speed': float(message.linear_velocity_mps),
            'message': message.message,
        }
        with self._lock:
            self._robot = robot

    def update_task(self, message: TaskStatus) -> None:
        """Store command and execution scopes independently."""
        if not isinstance(message, TaskStatus):
            raise TypeError('message must be TaskStatus')
        task = _task_dict(message)
        with self._lock:
            if message.status_scope == TaskStatus.SCOPE_EXECUTION:
                self._latest_execution_status = task
            elif message.status_scope == TaskStatus.SCOPE_COMMAND:
                self._latest_command_status = task

    def snapshot(self) -> dict:
        """Return a detached JSON-serializable state snapshot."""
        with self._lock:
            robot = deepcopy(self._robot or _default_robot())
            execution = deepcopy(self._latest_execution_status)
            command = deepcopy(self._latest_command_status)
        return {
            'robot': robot,
            'task': execution or command or _default_task(),
            'last_command': command or _default_task(),
            'meta': {
                'task_status_priority': (
                    'execution' if execution is not None else 'command'
                ),
            },
        }


__all__ = ['StatusCache', 'SYSTEM_STATE_NAMES', 'TASK_STATE_NAMES']
