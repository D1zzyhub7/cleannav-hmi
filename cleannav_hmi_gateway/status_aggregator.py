"""Structured RobotStatus aggregation from fresh ROS inputs."""

from __future__ import annotations

from dataclasses import dataclass
import math

from cleannav_interfaces.msg import RobotStatus, SafetyStatus, TaskStatus
from geometry_msgs.msg import Pose, PoseWithCovarianceStamped
from nav_msgs.msg import Odometry
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data


LOCALIZATION_TOPIC = '/rtabmap/localization_pose'
ODOM_TOPIC = '/odom'
SAFETY_STATUS_TOPIC = '/cleannav/safety_status'
ROBOT_STATUS_TOPIC = '/cleannav/robot_status'


def _finite(*values: float) -> bool:
    return all(math.isfinite(float(value)) for value in values)


@dataclass(frozen=True)
class _Localization:
    pose: Pose
    received_ns: int


@dataclass(frozen=True)
class _Odometry:
    linear_x: float
    angular_z: float
    received_ns: int


@dataclass(frozen=True)
class _Safety:
    emergency_stop_active: bool
    autonomous_enabled: bool
    received_ns: int


@dataclass(frozen=True)
class _Task:
    state: int
    message: str


class RobotStatusAggregator:
    """ROS-independent freshness and system-state aggregation."""

    def __init__(
        self,
        *,
        localization_timeout_sec: float = 1.0,
        odom_timeout_sec: float = 1.0,
        safety_timeout_sec: float = 1.0,
    ) -> None:
        for name, value in (
            ('localization_timeout_sec', localization_timeout_sec),
            ('odom_timeout_sec', odom_timeout_sec),
            ('safety_timeout_sec', safety_timeout_sec),
        ):
            if not math.isfinite(float(value)) or float(value) <= 0.0:
                raise ValueError(f'{name} must be finite and > 0')
        self._localization_timeout_ns = int(
            round(float(localization_timeout_sec) * 1_000_000_000))
        self._odom_timeout_ns = int(
            round(float(odom_timeout_sec) * 1_000_000_000))
        self._safety_timeout_ns = int(
            round(float(safety_timeout_sec) * 1_000_000_000))
        self._localization: _Localization | None = None
        self._odom: _Odometry | None = None
        self._safety: _Safety | None = None
        self._latest_execution: _Task | None = None
        self._latest_command: _Task | None = None

    def on_localization(
        self,
        message: PoseWithCovarianceStamped,
        received_ns: int,
    ) -> bool:
        """Accept only finite, non-zero-quaternion map-frame localization."""
        if not isinstance(message, PoseWithCovarianceStamped):
            raise TypeError('message must be PoseWithCovarianceStamped')
        pose = message.pose.pose
        quaternion = (
            pose.orientation.x,
            pose.orientation.y,
            pose.orientation.z,
            pose.orientation.w,
        )
        if (
            message.header.frame_id != 'map'
            or not _finite(
                pose.position.x,
                pose.position.y,
                pose.position.z,
                *quaternion,
            )
            or sum(value * value for value in quaternion) <= 0.0
        ):
            return False
        copied = Pose()
        copied.position.x = pose.position.x
        copied.position.y = pose.position.y
        copied.position.z = pose.position.z
        copied.orientation.x = pose.orientation.x
        copied.orientation.y = pose.orientation.y
        copied.orientation.z = pose.orientation.z
        copied.orientation.w = pose.orientation.w
        self._localization = _Localization(copied, int(received_ns))
        return True

    def on_odom(self, message: Odometry, received_ns: int) -> bool:
        """Accept finite velocity measurements from odometry."""
        if not isinstance(message, Odometry):
            raise TypeError('message must be Odometry')
        linear_x = message.twist.twist.linear.x
        angular_z = message.twist.twist.angular.z
        if not _finite(linear_x, angular_z):
            return False
        self._odom = _Odometry(
            float(linear_x),
            float(angular_z),
            int(received_ns),
        )
        return True

    def on_safety_status(
        self,
        message: SafetyStatus,
        received_ns: int,
    ) -> bool:
        """Accept structured SafetyStatus, never legacy human-readable text."""
        if not isinstance(message, SafetyStatus):
            raise TypeError('message must be SafetyStatus')
        if (
            message.header.frame_id != ''
            or message.interface_version != '1.0'
        ):
            return False
        self._safety = _Safety(
            bool(message.emergency_stop_active),
            bool(message.autonomous_enabled),
            int(received_ns),
        )
        return True

    def on_task_status(self, message: TaskStatus, received_ns: int) -> bool:
        """Keep command and execution scopes separate."""
        if not isinstance(message, TaskStatus):
            raise TypeError('message must be TaskStatus')
        task = _Task(int(message.state), message.message)
        if message.status_scope == TaskStatus.SCOPE_EXECUTION:
            self._latest_execution = task
            return True
        if message.status_scope == TaskStatus.SCOPE_COMMAND:
            self._latest_command = task
            return True
        return False

    def build(self, now_ns: int) -> RobotStatus:
        """Build a conservative RobotStatus from fresh stored inputs."""
        now_ns = int(now_ns)
        localization = self._localization
        localization_ok = (
            localization is not None
            and 0 <= now_ns - localization.received_ns
            <= self._localization_timeout_ns
        )
        odom = self._odom
        odom_fresh = (
            odom is not None
            and 0 <= now_ns - odom.received_ns <= self._odom_timeout_ns
        )
        safety = self._safety
        safety_fresh = (
            safety is not None
            and 0 <= now_ns - safety.received_ns <= self._safety_timeout_ns
        )
        execution = self._latest_execution
        execution_state = execution.state if execution is not None else None
        navigation_active = execution_state in {
            TaskStatus.STATE_NAVIGATING,
            TaskStatus.STATE_PAUSING,
            TaskStatus.STATE_CANCELING,
            TaskStatus.STATE_RETURNING_HOME,
            TaskStatus.STATE_SAFETY_BLOCKED,
        }

        if safety_fresh and safety.emergency_stop_active:
            system_state = RobotStatus.SYSTEM_EMERGENCY_STOP
            message = 'Safety emergency stop active'
        elif not safety_fresh:
            system_state = RobotStatus.SYSTEM_ERROR
            message = 'SafetyStatus stale or unavailable'
        elif not localization_ok:
            system_state = RobotStatus.SYSTEM_ERROR
            message = 'localization stale or unavailable'
        elif execution_state == TaskStatus.STATE_PAUSED:
            system_state = RobotStatus.SYSTEM_PAUSED
            message = execution.message if execution else '任务已暂停'
        elif execution_state == TaskStatus.STATE_SAFETY_BLOCKED:
            system_state = RobotStatus.SYSTEM_BLOCKED
            message = execution.message if execution else 'Safety blocked'
        elif execution is not None and execution_state not in (
            TaskStatus.STATE_WAITING_TARGET,
            TaskStatus.STATE_SUCCEEDED,
            TaskStatus.STATE_CANCELED,
            TaskStatus.STATE_FAILED,
            TaskStatus.STATE_EMERGENCY_STOPPED,
        ):
            system_state = RobotStatus.SYSTEM_BUSY
            message = execution.message or '任务执行中'
        else:
            system_state = RobotStatus.SYSTEM_READY
            message = execution.message if execution else '系统就绪'

        result = RobotStatus()
        result.header.stamp.sec, result.header.stamp.nanosec = divmod(
            max(0, now_ns), 1_000_000_000)
        result.header.frame_id = 'map' if localization_ok else ''
        result.interface_version = '1.0'
        result.system_state = system_state
        result.localization_ok = localization_ok
        if localization is not None and localization_ok:
            result.pose = localization.pose
        else:
            result.pose.orientation.w = 1.0
        result.navigation_active = bool(navigation_active)
        result.emergency_stop_active = (
            safety.emergency_stop_active if safety_fresh else False
        )
        result.autonomous_enabled = (
            safety.autonomous_enabled if safety_fresh else False
        )
        result.linear_velocity_mps = odom.linear_x if odom_fresh else 0.0
        result.angular_velocity_rps = odom.angular_z if odom_fresh else 0.0
        messages = [message]
        if not odom_fresh:
            messages.append('odometry stale')
        result.message = '; '.join(messages)[:256]
        return result


class StatusAggregatorNode(Node):
    """ROS node publishing the structured RobotStatus contract."""

    def __init__(self, **kwargs) -> None:
        super().__init__('cleannav_status_aggregator', **kwargs)
        localization_topic = self.declare_parameter(
            'localization_topic', LOCALIZATION_TOPIC).value
        odom_topic = self.declare_parameter('odom_topic', ODOM_TOPIC).value
        safety_topic = self.declare_parameter(
            'safety_status_topic', SAFETY_STATUS_TOPIC).value
        robot_topic = self.declare_parameter(
            'robot_status_topic', ROBOT_STATUS_TOPIC).value
        publish_rate_hz = self.declare_parameter(
            'publish_rate_hz', 10.0).value
        localization_timeout = self.declare_parameter(
            'localization_timeout_sec', 1.0).value
        odom_timeout = self.declare_parameter(
            'odom_timeout_sec', 1.0).value
        safety_timeout = self.declare_parameter(
            'safety_timeout_sec', 1.0).value
        self._aggregator = RobotStatusAggregator(
            localization_timeout_sec=localization_timeout,
            odom_timeout_sec=odom_timeout,
            safety_timeout_sec=safety_timeout,
        )
        self._robot_status_pub = self.create_publisher(
            RobotStatus, robot_topic, 10)
        self._task_status_sub = self.create_subscription(
            TaskStatus, '/cleannav/task_status', self._task_cb, 10)
        self._safety_status_sub = self.create_subscription(
            SafetyStatus, safety_topic, self._safety_cb, 10)
        self._localization_sub = self.create_subscription(
            PoseWithCovarianceStamped,
            localization_topic,
            self._localization_cb,
            qos_profile_sensor_data,
        )
        self._odom_sub = self.create_subscription(
            Odometry, odom_topic, self._odom_cb, qos_profile_sensor_data)
        self._timer = self.create_timer(
            1.0 / float(publish_rate_hz), self._publish_cb)

    def _now_ns(self) -> int:
        return int(self.get_clock().now().nanoseconds)

    def _task_cb(self, message: TaskStatus) -> None:
        self._aggregator.on_task_status(message, self._now_ns())

    def _safety_cb(self, message: SafetyStatus) -> None:
        self._aggregator.on_safety_status(message, self._now_ns())

    def _localization_cb(self, message: PoseWithCovarianceStamped) -> None:
        self._aggregator.on_localization(message, self._now_ns())

    def _odom_cb(self, message: Odometry) -> None:
        self._aggregator.on_odom(message, self._now_ns())

    def _publish_cb(self) -> None:
        self._robot_status_pub.publish(self._aggregator.build(self._now_ns()))


def main(args=None) -> None:
    rclpy.init(args=args)
    node = StatusAggregatorNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


__all__ = [
    'LOCALIZATION_TOPIC',
    'ODOM_TOPIC',
    'ROBOT_STATUS_TOPIC',
    'SAFETY_STATUS_TOPIC',
    'RobotStatusAggregator',
    'StatusAggregatorNode',
    'main',
]
