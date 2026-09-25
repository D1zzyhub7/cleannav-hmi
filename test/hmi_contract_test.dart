import 'dart:convert';

import 'package:cleannav_mobile/models/hil_snapshot.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/services/http_transport.dart';
import 'package:cleannav_mobile/services/vehicle_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _jsonResponse(Object body, int statusCode) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _state({
  bool j6Connected = false,
  Map<String, dynamic>? task,
}) => {
      'j6_connected': j6Connected,
      'robot': {
        'system_state': 'SYSTEM_READY',
        'localization_ok': true,
        'autonomous_enabled': false,
        'emergency_stop': false,
        'message': 'J6 状态已收到',
      },
      'task': task ?? {
        'execution_id': '',
        'command_id': '',
        'task_id': 0,
        'state': 'UNKNOWN',
        'progress': 0,
        'active_target_id': '',
        'remaining_distance_m': 0,
        'message': '尚未收到 TaskStatus',
      },
    };

void main() {
  test('Task 30 payload never contains source', () {
    final payload = buildHttpTaskPayload(
      taskId: 30,
      commandId: 'app-task30-1',
      timestampMs: 123,
    );

    expect(payload['task_id'], 30);
    expect(payload['user_confirmed'], false);
    expect(payload['valid_for_ms'], 60000);
    expect(payload.containsKey('source'), isFalse);
  });

  test('HTTP 200 means Gateway connected even when J6 is offline', () {
    final snapshot = HilSnapshot.fromJson(
      _state(j6Connected: false),
      gatewayConnected: true,
    );

    expect(snapshot.gatewayConnected, isTrue);
    expect(snapshot.j6Connected, isFalse);
    expect(snapshot.task.taskStatusPresent, isFalse);
  });

  test('HTTP 200 with j6_connected=true keeps both statuses separate', () {
    final snapshot = HilSnapshot.fromJson(
      _state(j6Connected: true),
      gatewayConnected: true,
    );

    expect(snapshot.gatewayConnected, isTrue);
    expect(snapshot.j6Connected, isTrue);
  });

  test('TaskStatus presence follows the local inference contract', () {
    final absent = TaskStatusSnapshot.fromJson({
      'execution_id': '',
      'command_id': '',
      'task_id': 0,
      'state': 'UNKNOWN',
    });
    final present = TaskStatusSnapshot.fromJson({
      'execution_id': 'execution-30',
      'command_id': 'app-task30-1',
      'task_id': 30,
      'state': 'NAVIGATING',
      'progress': 0.4,
      'active_target_id': 'leaf-1',
      'remaining_distance_m': 2.5,
      'message': '正在导航至目标',
    });

    expect(absent.taskStatusPresent, isFalse);
    expect(present.taskStatusPresent, isTrue);
    expect(present.taskId, 30);
    expect(present.taskState, 'NAVIGATING');
    expect(present.taskProgress, 0.4);
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
      'age_sec': 0.2,
      'robot_pose': {'x': 1.5, 'y': 2.5, 'yaw': 0.2},
    });

    expect(map.data, [-1, 0, 50, 100]);
    expect(map.ageSec, 0.2);
    expect(map.worldToCell(1.5, 2.5).x, 1.0);
    expect(map.worldToCell(1.5, 2.5).y, 1.0);
  });

  test('HTTP transport polls map and sends Task 30 without source', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/state') {
        return _jsonResponse(_state(j6Connected: true), 200);
      }
      if (request.url.path == '/api/map') {
        return _jsonResponse({
          'ok': true,
          'seq': 1,
          'frame_id': 'map',
          'width': 1,
          'height': 1,
          'resolution': 0.05,
          'origin': {'x': 0, 'y': 0, 'yaw': 0},
          'data': [100],
          'robot_pose': null,
        }, 200);
      }
      if (request.url.path == '/api/tasks') {
        return _jsonResponse({'submitted': true}, 202);
      }
      return _jsonResponse({}, 404);
    });
    final transport = HttpTransport(
      baseUrl: 'http://pc-gateway:18082',
      client: client,
    );
    final snapshotFuture = transport.snapshots.first;
    final mapFuture = transport.maps.first;
    await transport.connect();
    expect((await snapshotFuture).gatewayConnected, isTrue);
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
    expect(payload.containsKey('source'), isFalse);
    expect(requests.any((request) => request.url.path == '/api/map'), isTrue);
  });

  test('HTTP failure emits Gateway disconnected without inventing J6 state', () async {
    final transport = HttpTransport(
      baseUrl: 'http://pc-gateway:18082',
      client: MockClient((request) async => http.Response('offline', 503)),
    );
    final snapshotFuture = transport.snapshots.first;

    await expectLater(transport.connect(), throwsA(isA<TransportException>()));
    final snapshot = await snapshotFuture;
    expect(snapshot.gatewayConnected, isFalse);
    expect(snapshot.j6Connected, isNull);
    await transport.dispose();
  });
}
