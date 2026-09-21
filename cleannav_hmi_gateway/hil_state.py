"""Compatibility state view backed by J6 health and real PC ROS status."""

from __future__ import annotations

from copy import deepcopy

from .j6_hil_client import J6HilClient
from .status_cache import StatusCache


class HilStateProvider:
    """Map J6 health into the existing Flutter VehicleState JSON shape."""

    def __init__(self, client: J6HilClient, cache: StatusCache) -> None:
        self._client = client
        self._cache = cache

    def snapshot(self) -> dict:
        state = self._cache.snapshot()
        robot = deepcopy(state['robot'])
        task = deepcopy(state['task'])
        try:
            health = self._client.health()
            if health.get('ok') is not True:
                raise ValueError('J6 health did not report ok=true')
            active = int(health.get('active_navigation_requests', 0))
            if active < 0:
                raise ValueError('active_navigation_requests is invalid')
            task_ingress = health.get('task_ingress') is True
        # Network and malformed health responses are both offline states.
        except Exception as exc:
            robot.update({
                'connection': 'offline',
                'system_state': 'SYSTEM_UNKNOWN',
                'navigation_active': False,
                'message': f'J6 HIL offline: {exc}',
            })
            state.update({
                'ok': False,
                'j6_connected': False,
                'task_ingress': False,
                'active_navigation_requests': 0,
                'message': robot['message'],
                'robot': robot,
                'task': task,
            })
            state['meta']['state_source'] = 'j6_health+pc_ros'
            return state

        navigating = active > 0
        robot.update({
            'connection': 'online',
            'system_state': 'SYSTEM_BUSY' if navigating else 'SYSTEM_READY',
            'navigation_active': navigating,
            'message': (
                f'J6 HIL executing ({active} active request)'
                if navigating
                else 'J6 HIL online, standby'
            ),
        })
        # A real PC execution TaskStatus remains authoritative. Health fills
        # only the state gap before that ROS status arrives.
        if navigating and task.get('state') in {
            None,
            '',
            'UNKNOWN',
            'IDLE',
            'SUCCEEDED',
            'CANCELED',
            'FAILED',
        }:
            task['state'] = 'NAVIGATING'
            task['message'] = robot['message']
        elif not navigating and task.get('state') in {
            None,
            '',
            'UNKNOWN',
            'ACCEPTED',
            'QUEUED',
            'WAITING_TARGET',
            'PREPARING',
            'NAVIGATING',
            'PAUSING',
            'CANCELING',
            'RETURNING_HOME',
            'SAFETY_BLOCKED',
        }:
            task['state'] = 'IDLE'
            task['message'] = robot['message']

        state.update({
            'ok': True,
            'j6_connected': True,
            'task_ingress': task_ingress,
            'active_navigation_requests': active,
            'message': robot['message'],
            'robot': robot,
            'task': task,
        })
        state['meta']['state_source'] = 'j6_health+pc_ros'
        state['meta']['j6_health'] = health
        return state


__all__ = ['HilStateProvider']
