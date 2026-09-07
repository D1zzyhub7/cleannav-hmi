"""ROS 2 node owning the HMI HTTP ingress and status cache."""

from __future__ import annotations

from queue import Empty, Full, Queue

from cleannav_interfaces.msg import RobotStatus, TaskCommand, TaskStatus
import rclpy
from rclpy.node import Node

from .http_server import GatewayHttpServer
from .status_cache import StatusCache


TASK_COMMAND_TOPIC = '/cleannav/hmi/task_command'
TASK_STATUS_TOPIC = '/cleannav/task_status'
ROBOT_STATUS_TOPIC = '/cleannav/robot_status'


class GatewayNode(Node):
    """Queue HTTP commands, publish them from a ROS timer, and expose state."""

    def __init__(self, **kwargs) -> None:
        super().__init__('cleannav_hmi_gateway', **kwargs)
        host = self.declare_parameter('bind_host', '127.0.0.1').value
        port = self.declare_parameter('port', 8765).value
        access_token = self.declare_parameter('access_token', '').value
        queue_depth = self.declare_parameter('command_queue_depth', 64).value
        self._command_queue = Queue(maxsize=int(queue_depth))
        self._task_command_pub = self.create_publisher(
            TaskCommand, TASK_COMMAND_TOPIC, 10)
        self._status_cache = StatusCache()
        self._task_status_sub = self.create_subscription(
            TaskStatus, TASK_STATUS_TOPIC, self._task_status_cb, 10)
        self._robot_status_sub = self.create_subscription(
            RobotStatus, ROBOT_STATUS_TOPIC, self._robot_status_cb, 10)
        self._drain_timer = self.create_timer(0.01, self._drain_commands)
        self._http_server = GatewayHttpServer(
            host,
            int(port),
            str(access_token),
            self._enqueue_http_command,
            self._status_cache.snapshot,
        )
        self._http_server.start()

    def _enqueue_http_command(self, command: dict) -> bool:
        try:
            self._command_queue.put_nowait(command)
        except Full:
            return False
        return True

    def _duration_parts(self, valid_for_ms: float) -> tuple[int, int]:
        total_ns = int(round(float(valid_for_ms) * 1_000_000))
        return divmod(total_ns, 1_000_000_000)

    def _to_ros_command(self, command: dict) -> TaskCommand:
        message = TaskCommand()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = ''
        message.interface_version = '1.0'
        message.command_id = command['command_id']
        message.source = TaskCommand.SOURCE_APP
        message.task_id = command['task_id']
        message.confidence = 1.0
        message.user_confirmed = command['user_confirmed']
        message.raw_text = f"http:{command['endpoint']}"
        message.valid_for.sec, message.valid_for.nanosec = (
            self._duration_parts(command['valid_for_ms'])
        )
        return message

    def _drain_commands(self) -> None:
        while True:
            try:
                command = self._command_queue.get_nowait()
            except Empty:
                return
            self._task_command_pub.publish(self._to_ros_command(command))

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
    'ROBOT_STATUS_TOPIC',
    'TASK_COMMAND_TOPIC',
    'TASK_STATUS_TOPIC',
    'main',
]
