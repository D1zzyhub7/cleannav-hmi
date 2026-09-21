"""PC HMI gateway relaying APP tasks to J6 and serving ROS map/state."""

from __future__ import annotations

import time

from cleannav_interfaces.msg import RobotStatus, TaskStatus
from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import OccupancyGrid
import rclpy
from rclpy.node import Node
from rclpy.qos import (
    QoSDurabilityPolicy,
    QoSHistoryPolicy,
    QoSProfile,
    QoSReliabilityPolicy,
)

from .hil_state import HilStateProvider
from .http_server import GatewayHttpServer
from .j6_hil_client import AppTaskRelay, DEFAULT_J6_BASE_URL, J6HilClient
from .map_cache import OccupancyMapCache
from .status_cache import StatusCache


TASK_STATUS_TOPIC = '/cleannav/hil_pc/task_status'
ROBOT_STATUS_TOPIC = '/cleannav/robot_status'
RTAB_MAP_TOPIC = '/rtabmap/map'
LOCALIZATION_TOPIC = '/rtabmap/localization_pose'


class GatewayNode(Node):
    """Expose the phone API without bypassing J6 Mission Manager ingress."""

    def __init__(self, **kwargs) -> None:
        super().__init__('cleannav_hmi_gateway', **kwargs)
        host = self.declare_parameter('bind_host', '0.0.0.0').value
        port = self.declare_parameter('port', 18082).value
        access_token = self.declare_parameter('access_token', '').value
        j6_base_url = self.declare_parameter(
            'j6_base_url', DEFAULT_J6_BASE_URL).value
        j6_timeout_sec = self.declare_parameter(
            'j6_timeout_sec', 2.5).value
        task_status_topic = self.declare_parameter(
            'task_status_topic', TASK_STATUS_TOPIC).value
        robot_status_topic = self.declare_parameter(
            'robot_status_topic', ROBOT_STATUS_TOPIC).value
        map_topic = self.declare_parameter(
            'map_topic', RTAB_MAP_TOPIC).value
        localization_topic = self.declare_parameter(
            'localization_topic', LOCALIZATION_TOPIC).value
        self._status_cache = StatusCache()
        self._map_cache = OccupancyMapCache()
        self._j6_client = J6HilClient(
            str(j6_base_url), timeout_sec=float(j6_timeout_sec))
        self._task_relay = AppTaskRelay(
            self._j6_client,
            on_received=self._log_task_received,
            on_forwarded=self._log_task_forwarded,
        )
        self._state_provider = HilStateProvider(
            self._j6_client, self._status_cache)
        task_qos = QoSProfile(
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=10,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.TRANSIENT_LOCAL,
        )
        self._task_status_sub = self.create_subscription(
            TaskStatus, task_status_topic, self._task_status_cb, task_qos)
        self._robot_status_sub = self.create_subscription(
            RobotStatus, robot_status_topic, self._robot_status_cb, 10)
        map_qos = QoSProfile(
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.TRANSIENT_LOCAL,
        )
        pose_qos = QoSProfile(
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.VOLATILE,
        )
        self._map_sub = self.create_subscription(
            OccupancyGrid, map_topic, self._map_cb, map_qos)
        self._localization_sub = self.create_subscription(
            PoseWithCovarianceStamped,
            localization_topic,
            self._localization_cb,
            pose_qos,
        )
        self._last_map_log_monotonic = float('-inf')
        self._http_server = GatewayHttpServer(
            host,
            int(port),
            str(access_token),
            self._task_relay.submit,
            self._state_provider.snapshot,
            self._map_cache.snapshot,
        )
        self._http_server.start()
        self.get_logger().info(
            f'HMI_GATEWAY_READY bind={host}:{int(port)} '
            f'j6={str(j6_base_url).rstrip("/")}')

    def _log_task_received(self, command: dict) -> None:
        self.get_logger().info(
            f'APP_TASK_RECEIVED task_id={command["task_id"]} '
            f'command_id={command["command_id"]}')

    def _log_task_forwarded(self, payload: dict, status: int) -> None:
        self.get_logger().info(
            f'J6_TASK_FORWARDED task_id={payload["task_id"]} '
            f'source={payload["source"]} status={status}')

    def _map_cb(self, message: OccupancyGrid) -> None:
        if not self._map_cache.update_map(message):
            self.get_logger().warning('Rejected invalid RTAB OccupancyGrid')
            return
        now = time.monotonic()
        if now - self._last_map_log_monotonic >= 5.0:
            self._last_map_log_monotonic = now
            self.get_logger().info(
                f'RTAB_MAP_RECEIVED width={message.info.width} '
                f'height={message.info.height} '
                f'resolution={message.info.resolution}')

    def _localization_cb(
        self,
        message: PoseWithCovarianceStamped,
    ) -> None:
        self._map_cache.update_robot_pose(message)

    def _task_status_cb(self, message: TaskStatus) -> None:
        self._status_cache.update_task(message)

    def _robot_status_cb(self, message: RobotStatus) -> None:
        self._status_cache.update_robot(message)

    def destroy_node(self):
        """Stop the HTTP thread before destroying ROS resources."""
        self._http_server.shutdown()
        return super().destroy_node()


def main(args=None) -> None:
    rclpy.init(args=args)
    node = GatewayNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


__all__ = [
    'GatewayNode',
    'LOCALIZATION_TOPIC',
    'ROBOT_STATUS_TOPIC',
    'RTAB_MAP_TOPIC',
    'TASK_STATUS_TOPIC',
    'main',
]
