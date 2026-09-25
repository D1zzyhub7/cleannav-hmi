"""ROS glue for the offline Voice -> TaskCommand bridge."""

from __future__ import annotations

from pathlib import Path

from ament_index_python.packages import get_package_share_directory
from cleannav_interfaces.msg import TaskCommand
import rclpy
from rclpy.node import Node
from rclpy.qos import (
    DurabilityPolicy,
    HistoryPolicy,
    QoSProfile,
    ReliabilityPolicy,
)

from .voice_bridge_core import VoiceBridgeCore
from .models import RecognizedUtterance, VoiceProcessResult


TASK_COMMAND_TOPIC = '/cleannav/hmi/task_command'


class VoiceBridgeNode(Node):
    """Publish policy-approved commands to the frozen HMI topic."""

    def __init__(
        self,
        *,
        core: VoiceBridgeCore | None = None,
        **kwargs,
    ) -> None:
        """Create the publisher and either load or inject the domain core."""
        super().__init__('voice_bridge_node', **kwargs)
        self.declare_parameter('command_valid_for_ms', 5000)
        valid_for_ms = self.get_parameter('command_valid_for_ms').value
        if isinstance(valid_for_ms, bool) or not isinstance(valid_for_ms, int):
            raise ValueError('command_valid_for_ms must be an integer')
        if valid_for_ms <= 0:
            raise ValueError('command_valid_for_ms must be > 0')

        self._core = core or self._load_production_core(valid_for_ms)
        self._task_command_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.VOLATILE,
        )
        self._publisher = self.create_publisher(
            TaskCommand,
            TASK_COMMAND_TOPIC,
            self._task_command_qos,
        )
        self.get_logger().info(
            'CleanNav Voice Bridge ready; no microphone/ASR backend is active'
        )

    @staticmethod
    def _load_production_core(command_valid_for_ms: int) -> VoiceBridgeCore:
        voice_share = Path(get_package_share_directory('cleannav_voice'))
        interfaces_share = Path(
            get_package_share_directory('cleannav_interfaces')
        )
        return VoiceBridgeCore.from_paths(
            voice_share / 'config' / 'voice_task_map.yaml',
            interfaces_share / 'config' / 'task_catalog.yaml',
            command_valid_for_ms,
        )

    @property
    def task_command_topic(self) -> str:
        """Return the frozen TaskCommand topic."""
        return TASK_COMMAND_TOPIC

    def process_utterance(
        self,
        utterance: RecognizedUtterance,
    ) -> VoiceProcessResult:
        """Process and publish one approved utterance."""
        result = self._core.process_utterance(utterance)
        if not result.accepted or result.command is None:
            reason = (
                result.rejection.reason.value
                if result.rejection
                else 'UNKNOWN'
            )
            self.get_logger().warning(
                f'voice utterance rejected: reason={reason!r}, '
                f'utterance_id={utterance.utterance_id!r}'
            )
            return result

        payload = self._core.factory.build_payload(result.command)
        message = self._core.factory.to_ros_message(
            payload,
            self.get_clock().now().to_msg(),
        )
        self._publisher.publish(message)
        self.get_logger().info(
            f'published voice TaskCommand: command_id={payload.command_id!r}, '
            f'task_id={payload.task_id}'
        )
        return result


def main(args=None) -> None:
    """Run the ROS node; ASR integration is intentionally deferred."""
    rclpy.init(args=args)
    node = VoiceBridgeNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()
