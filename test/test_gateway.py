"""Unit tests for HMI gateway validation, cache and aggregation semantics."""

import json
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest
from cleannav_interfaces.msg import RobotStatus, SafetyStatus, TaskStatus
from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import Odometry
import rclpy
from rclpy.parameter import Parameter

from cleannav_hmi_gateway.http_server import (
    GatewayHttpServer,
    HttpValidationError,
    validate_task_payload,
)
from cleannav_hmi_gateway.gateway_node import GatewayNode
from cleannav_hmi_gateway.status_aggregator import RobotStatusAggregator
from cleannav_hmi_gateway.status_cache import StatusCache


@pytest.fixture(scope='module', autouse=True)
def ros_context():
    if not rclpy.ok():
        rclpy.init(args=None)
    yield
    if rclpy.ok():
        rclpy.shutdown()


def _localization(frame='map', x=1.0):
    message = PoseWithCovarianceStamped()
    message.header.frame_id = frame
    message.pose.pose.position.x = x
    message.pose.pose.orientation.w = 1.0
    return message


def _safety(*, estop=False, autonomous=False):
    message = SafetyStatus()
    message.interface_version = '1.0'
    message.header.frame_id = ''
    message.emergency_stop_active = estop
    message.autonomous_enabled = autonomous
    return message


def _task(scope, state, message='task'):
    result = TaskStatus()
    result.status_scope = scope
    result.state = state
    result.command_id = 'command-1'
    result.execution_id = (
        'execution-1'
        if scope == TaskStatus.SCOPE_EXECUTION
        else ''
    )
    result.task_id = 30
    result.message = message
    return result


def _odom(linear=0.25, angular=0.1):
    message = Odometry()
    message.twist.twist.linear.x = linear
    message.twist.twist.angular.z = angular
    return message


def test_http_payload_uses_canonical_confirmation_and_legacy_alias():
    canonical = validate_task_payload({
        'command_id': 'app-1',
        'task_id': 30,
        'valid_for_ms': 1500,
        'user_confirmed': True,
    })
    legacy = validate_task_payload({
        'command_id': 'app-2',
        'task_id': 30,
        'safety_confirmed': True,
    })

    assert canonical['user_confirmed'] is True
    assert legacy['user_confirmed'] is True


def test_conflicting_confirmation_aliases_are_rejected():
    with pytest.raises(HttpValidationError):
        validate_task_payload({
            'command_id': 'app-1',
            'task_id': 30,
            'user_confirmed': True,
            'safety_confirmed': False,
        })


def test_reset_requires_confirmation_and_forces_task_seven():
    with pytest.raises(HttpValidationError):
        validate_task_payload(
            {'command_id': 'reset-1', 'user_confirmed': False},
            reset=True,
        )

    command = validate_task_payload(
        {'command_id': 'reset-1', 'user_confirmed': True},
        reset=True,
    )
    assert command['task_id'] == 7
    assert command['user_confirmed'] is True


def test_status_cache_keeps_execution_scope_over_command_scope():
    cache = StatusCache()
    robot = RobotStatus()
    robot.system_state = RobotStatus.SYSTEM_READY
    robot.localization_ok = True
    cache.update_robot(robot)
    cache.update_task(_task(
        TaskStatus.SCOPE_EXECUTION,
        TaskStatus.STATE_NAVIGATING,
    ))
    cache.update_task(_task(
        TaskStatus.SCOPE_COMMAND,
        TaskStatus.STATE_ACCEPTED,
    ))

    state = cache.snapshot()
    assert state['robot']['localization_ok'] is True
    assert state['task']['status_scope_name'] == 'EXECUTION'
    assert state['task']['state'] == 'NAVIGATING'
    assert state['last_command']['state'] == 'ACCEPTED'


def test_aggregator_ready_and_fresh_measurements():
    aggregator = RobotStatusAggregator()
    aggregator.on_localization(_localization(), 0)
    aggregator.on_odom(_odom(), 0)
    aggregator.on_safety_status(_safety(), 0)

    status = aggregator.build(500_000_000)

    assert status.system_state == RobotStatus.SYSTEM_READY
    assert status.localization_ok is True
    assert status.header.frame_id == 'map'
    assert status.linear_velocity_mps == pytest.approx(0.25)


def test_aggregator_rejects_wrong_frame_and_marks_stale_localization():
    aggregator = RobotStatusAggregator()
    assert not aggregator.on_localization(_localization(frame='odom'), 0)
    aggregator.on_safety_status(_safety(), 0)

    status = aggregator.build(1_100_000_000)

    assert status.localization_ok is False
    assert status.header.frame_id == ''
    assert status.system_state == RobotStatus.SYSTEM_ERROR


def test_aggregator_stale_odom_is_zero_and_explicit():
    aggregator = RobotStatusAggregator()
    aggregator.on_localization(_localization(), 0)
    aggregator.on_safety_status(_safety(), 0)
    aggregator.on_odom(_odom(), 0)

    status = aggregator.build(1_100_000_000)

    assert status.linear_velocity_mps == 0.0
    assert 'odometry stale' in status.message


def test_aggregator_safety_and_task_priorities():
    aggregator = RobotStatusAggregator()
    aggregator.on_localization(_localization(), 0)
    aggregator.on_safety_status(_safety(estop=True), 0)
    aggregator.on_task_status(
        _task(TaskStatus.SCOPE_EXECUTION, TaskStatus.STATE_NAVIGATING),
        0,
    )

    status = aggregator.build(0)

    assert status.system_state == RobotStatus.SYSTEM_EMERGENCY_STOP
    assert status.navigation_active is True
    assert status.emergency_stop_active is True


def test_gateway_http_returns_202_and_shutdowns_cleanly():
    submitted = []
    server = GatewayHttpServer(
        '127.0.0.1',
        0,
        '',
        lambda command: submitted.append(command) or True,
        lambda: {'robot': {}, 'task': {}, 'meta': {}},
    )
    server.start()
    try:
        port = server._server.server_address[1]
        request = Request(
            f'http://127.0.0.1:{port}/api/tasks',
            data=json.dumps({
                'command_id': 'http-1',
                'task_id': 30,
                'valid_for_ms': 1000,
                'user_confirmed': True,
                'timestamp_ms': 123,
            }).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST',
        )
        with urlopen(request, timeout=2) as response:
            body = json.loads(response.read())
            assert response.status == 202
            assert body['submitted'] is True
        assert submitted[0]['command_id'] == 'http-1'
    finally:
        server.shutdown()
    assert not server.running


def test_gateway_http_auth_and_queue_failure():
    server = GatewayHttpServer(
        '127.0.0.1',
        0,
        'secret',
        lambda command: False,
        lambda: {'robot': {}, 'task': {}, 'meta': {}},
    )
    server.start()
    try:
        port = server._server.server_address[1]
        request = Request(f'http://127.0.0.1:{port}/api/state')
        with pytest.raises(HTTPError) as error:
            urlopen(request, timeout=2)
        assert error.value.code == 401

        request = Request(
            f'http://127.0.0.1:{port}/api/tasks',
            data=json.dumps({
                'command_id': 'http-2',
                'task_id': 30,
            }).encode(),
            headers={
                'Authorization': 'Bearer secret',
                'Content-Type': 'application/json',
            },
            method='POST',
        )
        with pytest.raises(HTTPError) as error:
            urlopen(request, timeout=2)
        assert error.value.code == 503
    finally:
        server.shutdown()


def test_gateway_builds_ros_command_from_ros_clock_and_duration():
    node = GatewayNode(
        parameter_overrides=[Parameter('port', value=0)],
    )
    try:
        message = node._to_ros_command({
            'command_id': 'clock-1',
            'task_id': 30,
            'valid_for_ms': 1500.5,
            'user_confirmed': True,
            'endpoint': '/api/tasks',
        })
        assert message.command_id == 'clock-1'
        assert message.source == message.SOURCE_APP
        assert message.confidence == 1.0
        assert message.user_confirmed is True
        assert message.header.frame_id == ''
        assert message.header.stamp.sec > 0
        assert (
            message.valid_for.sec * 1_000_000_000
            + message.valid_for.nanosec
        ) == 1_500_500_000
    finally:
        node.destroy_node()
