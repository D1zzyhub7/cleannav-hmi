"""Unit tests for HMI gateway validation, cache and aggregation semantics."""

import json
from io import BytesIO
import math
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest
from cleannav_interfaces.msg import RobotStatus, SafetyStatus, TaskStatus
from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import OccupancyGrid, Odometry
import rclpy
from rclpy.parameter import Parameter
from rclpy.qos import QoSDurabilityPolicy, QoSReliabilityPolicy

from cleannav_hmi_gateway.http_server import (
    GatewayHttpServer,
    HttpValidationError,
    validate_task_payload,
)
from cleannav_hmi_gateway.gateway_node import (
    GatewayNode,
    LOCALIZATION_TOPIC,
    RTAB_MAP_TOPIC,
    TASK_STATUS_TOPIC,
)
from cleannav_hmi_gateway.hil_state import HilStateProvider
from cleannav_hmi_gateway.j6_hil_client import (
    AppTaskRelay,
    J6HilClient,
    SOURCE_APP,
)
from cleannav_hmi_gateway.map_cache import OccupancyMapCache
from cleannav_hmi_gateway.map_cache import MAX_ACCEPTED_CELL_COUNT
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


class _FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = json.dumps(body).encode()

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self._body


def _grid(data=(-1, 0, 50, 100)):
    message = OccupancyGrid()
    message.header.frame_id = 'map'
    message.header.stamp.sec = 12
    message.header.stamp.nanosec = 34
    message.info.width = 2
    message.info.height = 2
    message.info.resolution = 0.05
    message.info.origin.position.x = -1.0
    message.info.origin.position.y = -2.0
    message.info.origin.orientation.w = 1.0
    message.data = list(data)
    return message


def test_map_cache_rejects_oversized_grids_and_reports_age():
    cache = OccupancyMapCache()
    oversized = OccupancyGrid()
    oversized.header.frame_id = 'map'
    oversized.info.width = MAX_ACCEPTED_CELL_COUNT + 1
    oversized.info.height = 1
    assert cache.update_map(oversized) is False

    assert cache.update_map(_grid()) is True
    snapshot = cache.snapshot()
    assert snapshot['frame_id'] == 'map'
    assert snapshot['age_sec'] >= 0.0


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


def test_app_task_relay_forces_source_and_waits_for_j6_202():
    requests = []

    def opener(request, timeout):
        requests.append((request, timeout))
        return _FakeResponse(202, {'accepted_for_delivery': True})

    relay = AppTaskRelay(J6HilClient(
        'http://j6.test:18081/', timeout_sec=2.5, opener=opener))
    result = relay.submit({
        'command_id': 'app-task30-1',
        'task_id': 30,
        'valid_for_ms': 60_000.0,
        'user_confirmed': False,
        'endpoint': '/api/tasks',
        'source': 1,
    })

    assert result.status_code == 202
    assert result.body['accepted_for_delivery'] is True
    assert len(requests) == 1
    request, timeout = requests[0]
    assert request.full_url == 'http://j6.test:18081/task'
    assert timeout == 2.5
    payload = json.loads(request.data)
    assert payload == {
        'task_id': 30,
        'source': SOURCE_APP,
        'command_id': 'app-task30-1',
        'confidence': 1.0,
        'raw_text': '清扫最近的落叶',
        'user_confirmed': False,
        'valid_for_sec': 60.0,
    }


def test_duplicate_app_request_is_not_forwarded_twice():
    calls = []

    def opener(_request, timeout):
        assert timeout == 2.5
        calls.append(True)
        return _FakeResponse(202, {})

    relay = AppTaskRelay(J6HilClient('http://j6.test', opener=opener))
    command = {
        'command_id': 'same-command',
        'task_id': 30,
        'valid_for_ms': 60_000.0,
        'user_confirmed': False,
        'endpoint': '/api/tasks',
    }

    assert relay.submit(command).status_code == 202
    duplicate = relay.submit(command)

    assert duplicate.status_code == 202
    assert duplicate.body['duplicate'] is True
    assert len(calls) == 1


def test_j6_rejection_and_offline_are_clear_app_errors():
    def rejected(_request, timeout):
        assert timeout == 2.5
        raise HTTPError('http://j6/task', 400, 'bad task', {}, BytesIO())

    def offline(_request, timeout):
        assert timeout == 2.5
        raise OSError('network unreachable')

    command = {
        'command_id': 'j6-error',
        'task_id': 30,
        'valid_for_ms': 60_000.0,
        'user_confirmed': False,
        'endpoint': '/api/tasks',
    }
    rejected_result = AppTaskRelay(J6HilClient(
        'http://j6.test', opener=rejected)).submit(command)
    offline_result = AppTaskRelay(J6HilClient(
        'http://j6.test', opener=offline)).submit(command)

    assert rejected_result.status_code == 502
    assert rejected_result.body['upstream_status'] == 400
    assert offline_result.status_code == 503
    assert 'unavailable' in offline_result.body['error']


def test_hil_state_maps_j6_health_to_standby_navigating_and_offline():
    cache = StatusCache()

    class Client:
        health_value = {
            'ok': True,
            'task_ingress': True,
            'active_navigation_requests': 0,
        }

        def health(self):
            value = self.health_value
            if isinstance(value, Exception):
                raise value
            return value

    client = Client()
    provider = HilStateProvider(client, cache)
    standby = provider.snapshot()
    assert standby['j6_connected'] is True
    assert standby['robot']['system_state'] == 'SYSTEM_READY'
    assert standby['task']['state'] == 'IDLE'

    client.health_value = {
        'ok': True,
        'task_ingress': True,
        'active_navigation_requests': 1,
    }
    navigating = provider.snapshot()
    assert navigating['robot']['navigation_active'] is True
    assert navigating['task']['state'] == 'NAVIGATING'

    cache.update_task(_task(
        TaskStatus.SCOPE_EXECUTION,
        TaskStatus.STATE_NAVIGATING,
    ))
    client.health_value = {
        'ok': True,
        'task_ingress': True,
        'active_navigation_requests': 0,
    }
    assert provider.snapshot()['task']['state'] == 'IDLE'

    client.health_value = OSError('down')
    offline = provider.snapshot()
    assert offline['j6_connected'] is False
    assert offline['robot']['connection'] == 'offline'


def test_occupancy_grid_and_robot_pose_are_cached_without_reencoding():
    cache = OccupancyMapCache()
    assert cache.snapshot() is None
    assert cache.update_map(_grid()) is True
    pose = _localization(x=0.25)
    pose.pose.pose.position.y = -0.5
    pose.pose.pose.orientation.z = math.sin(math.pi / 4)
    pose.pose.pose.orientation.w = math.cos(math.pi / 4)
    assert cache.update_robot_pose(pose) is True

    snapshot = cache.snapshot()
    assert snapshot['seq'] == 1
    assert snapshot['stamp'] == {'sec': 12, 'nanosec': 34}
    assert snapshot['frame_id'] == 'map'
    assert snapshot['width'] == 2
    assert snapshot['height'] == 2
    assert snapshot['resolution'] == pytest.approx(0.05)
    assert snapshot['origin'] == {
        'x': -1.0,
        'y': -2.0,
        'yaw': 0.0,
    }
    assert snapshot['data'] == [-1, 0, 50, 100]
    assert snapshot['robot_pose']['x'] == pytest.approx(0.25)
    assert snapshot['robot_pose']['yaw'] == pytest.approx(math.pi / 2)


def test_invalid_occupancy_values_are_not_exposed():
    cache = OccupancyMapCache()
    assert cache.update_map(_grid(data=(-2, 0, 50, 100))) is False
    assert cache.snapshot() is None


def test_map_endpoint_returns_metadata_and_explicit_unavailable():
    current_map = None
    server = GatewayHttpServer(
        '127.0.0.1',
        0,
        '',
        lambda _command: True,
        lambda: {'robot': {}, 'task': {}, 'meta': {}},
        lambda: current_map,
    )
    server.start()
    try:
        port = server._server.server_address[1]
        with pytest.raises(HTTPError) as error:
            urlopen(f'http://127.0.0.1:{port}/api/map', timeout=2)
        assert error.value.code == 503
        unavailable = json.loads(error.value.read())
        assert unavailable['available'] is False

        current_map = {
            'ok': True,
            'seq': 9,
            'frame_id': 'map',
            'width': 2,
            'height': 2,
            'resolution': 0.05,
            'origin': {'x': 0, 'y': 0, 'yaw': 0},
            'data': [-1, 0, 50, 100],
            'robot_pose': None,
        }
        with urlopen(
            f'http://127.0.0.1:{port}/api/map', timeout=2
        ) as response:
            body = json.loads(response.read())
        assert response.status == 200
        assert body['seq'] == 9
        assert body['data'] == [-1, 0, 50, 100]
    finally:
        server.shutdown()


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


def test_gateway_defaults_allow_lan_and_use_real_hil_topics():
    node = GatewayNode(
        parameter_overrides=[Parameter('port', value=0)],
    )
    try:
        assert node._http_server.host == '0.0.0.0'
        assert node._http_server.port == 0
        assert node._task_status_sub.topic_name == TASK_STATUS_TOPIC
        assert (
            node._task_status_sub.qos_profile.reliability
            == QoSReliabilityPolicy.RELIABLE
        )
        assert (
            node._task_status_sub.qos_profile.durability
            == QoSDurabilityPolicy.TRANSIENT_LOCAL
        )
        assert node._task_status_sub.qos_profile.depth == 10
        assert node._map_sub.topic_name == RTAB_MAP_TOPIC
        assert node._localization_sub.topic_name == LOCALIZATION_TOPIC
        assert not hasattr(node, '_task_command_pub')
    finally:
        node.destroy_node()
