import 'dart:convert';

import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/models/vehicle_state.dart';
import 'package:cleannav_mobile/services/http_transport.dart';
import 'package:cleannav_mobile/services/vehicle_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP task payload uses generic user_confirmed', () {
    final payload = buildHttpTaskPayload(
      taskId: 7,
      commandId: 'reset-1',
      timestampMs: 123,
      userConfirmed: true,
    );

    expect(payload['user_confirmed'], isTrue);
    expect(payload.containsKey('safety_confirmed'), isFalse);
    expect(payload['valid_for_ms'], 60000);
  });

  test('missing localization_ok is unsafe by default', () {
    final state = VehicleState.fromJson({
      'robot': {'system_state': 'SYSTEM_READY'},
      'task': {'state': 'IDLE'},
    }, ConnectionKind.network);

    expect(state.localizationOk, isFalse);
  });

  test('canonical RobotStatus and TaskStatus fields are parsed', () {
    final state = VehicleState.fromJson({
      'robot': {
        'system_state': 'SYSTEM_BUSY',
        'localization_ok': true,
        'linear_velocity_mps': 0.25,
        'emergency_stop': false,
      },
      'task': {
        'task_id': 30,
        'state': 'NAVIGATING',
        'progress': 0.4,
        'message': 'running',
      },
    }, ConnectionKind.network);

    expect(state.localizationOk, isTrue);
    expect(state.speed, 0.25);
    expect(state.task?.id, 30);
    expect(state.progress, 0.4);
  });

  test('missing physical telemetry remains unknown', () {
    final state = VehicleState.fromJson({
      'robot': {'system_state': 'SYSTEM_READY'},
      'task': {'state': 'IDLE'},
    }, ConnectionKind.network);

    expect(state.battery, -1);
    expect(state.speed, -1);
    expect(state.brushKnown, isFalse);
    expect(state.waterPumpKnown, isFalse);
  });

  test('OccupancyGrid contract preserves cells and transforms world pose', () {
    final map = OccupancyMap.fromJson({
      'ok': true,
      'seq': 4,
      'frame_id': 'map',
      'width': 2,
      'height': 2,
      'resolution': 0.5,
      'origin': {'x': 1.0, 'y': 2.0, 'yaw': 0.0},
      'data': [-1, 0, 50, 100],
      'robot_pose': {'x': 1.5, 'y': 2.5, 'yaw': 0.2},
    });

    expect(map.data, [-1, 0, 50, 100]);
    expect(map.worldToCell(1.5, 2.5).x, 1.0);
    expect(map.worldToCell(1.5, 2.5).y, 1.0);
  });

  test('HTTP transport polls map and sends task30 to PC gateway', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/state') {
        return http.Response(jsonEncode({
          'robot': {'system_state': 'SYSTEM_READY'},
          'task': {'state': 'IDLE'},
        }), 200);
      }
      if (request.url.path == '/api/map') {
        return http.Response(jsonEncode({
          'ok': true,
          'seq': 1,
          'frame_id': 'map',
          'width': 1,
          'height': 1,
          'resolution': 0.05,
          'origin': {'x': 0, 'y': 0, 'yaw': 0},
          'data': [100],
          'robot_pose': null,
        }), 200);
      }
      if (request.url.path == '/api/tasks') {
        return http.Response(jsonEncode({'submitted': true}), 202);
      }
      return http.Response('{}', 404);
    });
    final transport = HttpTransport(
      baseUrl: 'http://pc-gateway:18082',
      client: client,
    );
    final mapFuture = transport.maps.first;
    await transport.connect();
    expect((await mapFuture)?.data, [100]);
    await transport.sendTask(30);
    await transport.disconnect();
    await transport.dispose();

    final taskRequest = requests.firstWhere(
      (request) => request.url.path == '/api/tasks',
    );
    final payload = jsonDecode(taskRequest.body) as Map<String, dynamic>;
    expect(payload['task_id'], 30);
    expect(payload['valid_for_ms'], 60000);
    expect(requests.any((request) => request.url.path == '/api/map'), isTrue);
  });

  test('HTTP transport exposes PC gateway task errors', () async {
    final transport = HttpTransport(
      baseUrl: 'http://pc-gateway:18082',
      client: MockClient((request) async => http.Response('J6 offline', 503)),
    );

    await expectLater(
      transport.sendTask(30),
      throwsA(isA<TransportException>()),
    );
    await transport.dispose();
  });
}
