"""Thread-safe JSON cache for RTAB-Map OccupancyGrid visualization."""

from __future__ import annotations

from copy import deepcopy
import math
from threading import RLock
import time

from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import OccupancyGrid


MAX_ACCEPTED_CELL_COUNT = 1_000_000


def _finite(*values: float) -> bool:
    return all(math.isfinite(float(value)) for value in values)


def _yaw(x: float, y: float, z: float, w: float) -> float:
    return math.atan2(
        2.0 * (w * z + x * y),
        1.0 - 2.0 * (y * y + z * z),
    )


class OccupancyMapCache:
    """Keep only the latest map and map-frame robot pose."""

    def __init__(self, *, max_cell_count: int = MAX_ACCEPTED_CELL_COUNT) -> None:
        if (
            isinstance(max_cell_count, bool)
            or not isinstance(max_cell_count, int)
            or max_cell_count <= 0
        ):
            raise ValueError('max_cell_count must be > 0')
        self._lock = RLock()
        self._seq = 0
        self._map: dict | None = None
        self._robot_pose: dict | None = None
        self._map_received_monotonic: float | None = None
        self._max_cell_count = int(max_cell_count)

    def update_map(self, message: OccupancyGrid) -> bool:
        if not isinstance(message, OccupancyGrid):
            raise TypeError('message must be OccupancyGrid')
        width = int(message.info.width)
        height = int(message.info.height)
        resolution = float(message.info.resolution)
        frame_id = str(message.header.frame_id).strip()
        origin = message.info.origin
        quaternion = origin.orientation
        cell_count = width * height
        if cell_count > self._max_cell_count:
            return False
        values = [int(value) for value in message.data]
        if (
            width <= 0
            or height <= 0
            or not frame_id
            or len(values) != width * height
            or not _finite(
                resolution,
                origin.position.x,
                origin.position.y,
                quaternion.x,
                quaternion.y,
                quaternion.z,
                quaternion.w,
            )
            or resolution <= 0.0
            or sum(value * value for value in (
                quaternion.x,
                quaternion.y,
                quaternion.z,
                quaternion.w,
            )) <= 0.0
            or any(value < -1 or value > 100 for value in values)
        ):
            return False
        with self._lock:
            self._seq += 1
            self._map_received_monotonic = time.monotonic()
            self._map = {
                'ok': True,
                'seq': self._seq,
                'stamp': {
                    'sec': int(message.header.stamp.sec),
                    'nanosec': int(message.header.stamp.nanosec),
                },
                'frame_id': frame_id,
                'width': width,
                'height': height,
                'resolution': resolution,
                'origin': {
                    'x': float(origin.position.x),
                    'y': float(origin.position.y),
                    'yaw': _yaw(
                        float(quaternion.x),
                        float(quaternion.y),
                        float(quaternion.z),
                        float(quaternion.w),
                    ),
                },
                'data': values,
            }
        return True

    def update_robot_pose(self, message: PoseWithCovarianceStamped) -> bool:
        if not isinstance(message, PoseWithCovarianceStamped):
            raise TypeError('message must be PoseWithCovarianceStamped')
        pose = message.pose.pose
        quaternion = pose.orientation
        if (
            message.header.frame_id != 'map'
            or not _finite(
                pose.position.x,
                pose.position.y,
                quaternion.x,
                quaternion.y,
                quaternion.z,
                quaternion.w,
            )
            or sum(value * value for value in (
                quaternion.x,
                quaternion.y,
                quaternion.z,
                quaternion.w,
            )) <= 0.0
        ):
            return False
        robot_pose = {
            'x': float(pose.position.x),
            'y': float(pose.position.y),
            'yaw': _yaw(
                float(quaternion.x),
                float(quaternion.y),
                float(quaternion.z),
                float(quaternion.w),
            ),
        }
        with self._lock:
            self._robot_pose = robot_pose
        return True

    def snapshot(self) -> dict | None:
        with self._lock:
            if self._map is None:
                return None
            result = deepcopy(self._map)
            result['robot_pose'] = deepcopy(self._robot_pose)
            result['age_sec'] = max(
                0.0,
                time.monotonic() - self._map_received_monotonic,
            )
            return result


__all__ = ['MAX_ACCEPTED_CELL_COUNT', 'OccupancyMapCache']
