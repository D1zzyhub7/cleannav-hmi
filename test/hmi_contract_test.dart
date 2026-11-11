import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/models/hil_snapshot.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/models/task_definition.dart';
import 'package:cleannav_mobile/services/http_transport.dart';
import 'package:cleannav_mobile/services/vehicle_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Synthetic HTTP fixtures. Never addresses a vehicle or declares real targets.
final identity = {'map_id': 'test-map', 'revision': 'r1', 'sha256': 'a' * 64};
Map<String, dynamic> targets() => {
      'schema_version': 1,
      'map': identity,
      'regions': [
        {'region_id': 'region-test', 'display_name': '测试区域'}
      ],
      'chargers': []
    };
Map<String, dynamic> state() => {
      'api_version': '1.0',
      'j6_connected': false,
      'connection': {'gateway': 'CONNECTED', 'task_command_subscribers': 1},
      'status_health': {
        'robot': {'available': true, 'fresh': true}
      },
      'robot': {
        'system_state': 'SYSTEM_READY',
        'localization_ok': true,
        'linear_velocity_mps': 0.2
      },
      'safety': {
        'available': true,
        'fresh': true,
        'emergency_stop_active': false,
        'autonomous_enabled': false,
        'block_all': false,
        'lease_owner_execution_id': ''
      },
      'map_identity': identity,
      'task': {'state': 'UNKNOWN', 'progress': -1},
    };
Map<String, dynamic> mapBody() => {
      'ok': true,
      'map': {
        'seq': 1,
        'width': 2,
        'height': 2,
        'resolution': 0.5,
        'frame_id': 'map',
        'origin': {'x': 1, 'y': 2, 'yaw': 0},
        'data': [-1, 0, 50, 100],
        'robot_pose': {'x': 1.5, 'y': 2.5, 'yaw': 0.2},
      }
    };
http.Response reply(Object value, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
http.Response initial(http.Request request) =>
    request.url.path == '/api/v1/state'
        ? reply(state())
        : request.url.path == '/api/v1/map'
            ? reply(mapBody())
            : reply({}, 404);
HttpTransport transport(http.Client client,
    {String token = '', Duration timeout = const Duration(seconds: 1)}) {
  final result = HttpTransport(
      baseUrl: 'http://mock.invalid:18082',
      client: client,
      token: token,
      pollInterval: const Duration(days: 1),
      requestTimeout: timeout);
  addTearDown(result.dispose);
  addTearDown(client.close);
  return result;
}

Map<String, dynamic> receipt(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final spatial = request.url.path == '/api/v1/tasks';
  return {
    if (spatial) 'accepted': true else 'accepted_for_delivery': true,
    'command_id': body['command_id'],
    if (spatial) 'sequence_id': body['sequence_id'],
    'status_url': spatial
        ? '/api/v1/sequences/${body['sequence_id']}'
        : '/api/v1/commands/${body['command_id']}',
    'mission_accepted': null
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('V1 state uses connection and fresh robot/Safety instead of legacy J6',
      () {
    final snapshot = HilSnapshot.fromJson(state(), gatewayConnected: true);
    expect(snapshot.gatewayConnected, isTrue);
    expect(snapshot.missionConnected, isTrue);
    expect(snapshot.localizationOk, isTrue);
    expect(snapshot.emergencyStop, isFalse);
    expect(snapshot.task.taskProgress, -1);
    expect(snapshot.mapIdentity!.toJson(), identity);
  });
  test('missing or stale Safety remains UNKNOWN even with robot legacy false',
      () {
    final body = state();
    body['safety'] = {
      'available': true,
      'fresh': false,
      'emergency_stop_active': false
    };
    body['status_health'] = {};
    final snapshot = HilSnapshot.fromJson(body, gatewayConnected: true);
    expect(snapshot.emergencyStop, isNull);
    expect(snapshot.blockAll, isNull);
    expect(snapshot.localizationOk, isNull);
    expect(snapshot.systemState, 'STATUS_STALE');
  });
  test('battery and IMU stay visible when robot status is stale', () {
    final body = state();
    body['status_health'] = {};
    body['battery'] = {'soc': 72.0, 'age_sec': 1.5};
    body['imu'] = {
      'age_sec': 1.5,
      'orientation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
      'angular_velocity': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      'linear_acceleration': {'x': -1.51, 'y': 0.0, 'z': 9.72},
    };
    final snapshot = HilSnapshot.fromJson(body, gatewayConnected: true);
    expect(snapshot.localizationOk, isNull);
    expect(snapshot.battery!.known, isTrue);
    expect(snapshot.battery!.label, '72%');
    expect(snapshot.imu!.known, isTrue);
    expect(snapshot.imu!.label, contains('9.72'));
    body['battery'] = {'soc': 72.0, 'age_sec': 30};
    expect(
      HilSnapshot.fromJson(body, gatewayConnected: true).battery!.label,
      '未知',
    );
    body.remove('battery');
    expect(HilSnapshot.fromJson(body, gatewayConnected: true).battery, isNull);
  });
  test('V1 map wrapper preserves cells, pose and coordinate conversion', () {
    final map = OccupancyMap.fromJson(mapBody());
    expect(map.data, [-1, 0, 50, 100]);
    expect(map.worldToCell(1.5, 2.5).x, 1);
    expect(map.worldToCell(1.5, 2.5).y, 1);
    expect(() => OccupancyMap.fromJson({'ok': false, 'map': {}}),
        throwsFormatException);
  });
  test(
      'admin Registry imports Region IDs and leaves unconfigured Charger empty',
      () {
    final registry = TargetRegistry.fromJson(targets());
    expect(registry.regions.single.id, 'region-test');
    expect(registry.regions.single.name, '测试区域');
    expect(registry.chargers, isEmpty);
    final body = targets();
    body['chargers'] = [
      {'charger_id': 'test-charger'}
    ];
    expect(() => TargetRegistry.fromJson(body), throwsFormatException);
  });
  test(
      'payload limits valid_for_ms, carries exactly map three fields, omits V0 fields',
      () {
    for (final value in [0, 10000, 60000]) {
      final body = buildHttpTaskPayload(
          taskId: 41,
          commandId: 'c1',
          sequenceId: 's1',
          regionId: 'region-test',
          map: MapIdentity.fromJson(identity),
          validForMs: value);
      expect(body['valid_for_ms'], value.clamp(100, 30000));
      expect(body['map'], identity);
      expect(body['api_version'], '1.0');
      expect(body.containsKey('source'), isFalse);
      expect(body.containsKey('timestamp_ms'), isFalse);
    }
    expect(buildHttpTaskPayload(taskId: 4, commandId: 'stop')['valid_for_ms'],
        10000);
    expect(() => buildHttpTaskPayload(taskId: 41, commandId: 'c'),
        throwsA(isA<TransportException>()));
    expect(() => buildHttpTaskPayload(taskId: 30, commandId: 'c'),
        throwsA(isA<TransportException>()));
    expect(() => buildHttpTaskPayload(taskId: 7, commandId: 'c'),
        throwsA(isA<TransportException>()));
  });
  test('GET V1 state authenticates without fetching a live grid', () async {
    final seen = <http.Request>[];
    final t = transport(MockClient((request) async {
      seen.add(request);
      return initial(request);
    }), token: 'test-only-token');
    final snapshot = t.snapshots.first;
    await t.connect();
    expect((await snapshot).gatewayConnected, isTrue);
    expect(seen.map((r) => r.url.path), ['/api/v1/state']);
    expect(
        seen.every(
            (r) => r.headers['Authorization'] == 'Bearer test-only-token'),
        isTrue);
    expect(seen.every((r) => r.url.query.isEmpty), isTrue);
  });
  test(
      'empty token is not hardcoded; 401 remains an explicit connection failure',
      () async {
    final t = transport(MockClient((request) async {
      expect(request.headers.containsKey('Authorization'), isFalse);
      return reply({'message': 'unauthorized'}, 401);
    }));
    await expectLater(
        t.connect(), throwsA(predicate((e) => e.toString().contains('401'))));
  });
  test(
      'Task41 202 preserves receipt then polls returned sequence status_url to success',
      () async {
    String? sequenceId;
    var polls = 0;
    var posts = 0;
    final t = transport(MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        expect(request.url.path, '/api/v1/tasks');
        final body = jsonDecode(request.body);
        expect(body['parameters'], {'region_id': 'region-test'});
        expect(body['map'], identity);
        sequenceId = body['sequence_id'];
        return reply({
          ...receipt(request),
          'status_url': '/api/v1/sequences/returned-status'
        }, 202);
      }
      if (request.url.path == '/api/v1/sequences/returned-status') {
        return reply({
          'sequence': {
            'sequence_id': sequenceId,
            'state': ++polls == 1 ? 'RUNNING' : 'SUCCEEDED',
            'completed_steps': polls == 1 ? 0 : 1,
            'step_count': 1,
            'message': '测试状态'
          }
        });
      }
      expect(request.url.path.startsWith('/api/v1/commands/'), isFalse);
      return initial(request);
    }));
    await t.connect();
    await t.sendTask(41, regionId: 'region-test');
    final r = t.requests.values.single;
    expect(r.state, 'ACCEPTED');
    expect(r.terminal, isFalse);
    expect(r.response['accepted'], isTrue);
    await t.pollSubmissions();
    expect(r.state, 'RUNNING');
    await t.pollSubmissions();
    expect(r.state, 'SUCCEEDED');
    expect(r.completedSteps, 1);
    expect(posts, 1);
  });
  for (final terminal in [
    'FAILED',
    'CANCELED',
    'REJECTED',
    'EMERGENCY_STOPPED'
  ]) {
    test('sequence terminal $terminal is displayed without claiming success',
        () async {
      String? sequence;
      final t = transport(MockClient((r) async {
        if (r.method == 'POST') {
          sequence = jsonDecode(r.body)['sequence_id'];
          return reply(receipt(r), 202);
        }
        if (r.url.path.startsWith('/api/v1/sequences/')) {
          return reply({
            'sequence': {
              'sequence_id': sequence,
              'state': terminal,
              'reason_code': 101,
              'message': 'test reason'
            }
          });
        }
        return initial(r);
      }));
      await t.connect();
      await t.sendTask(41, regionId: 'region-test');
      await t.pollSubmissions();
      expect(t.requests.values.single.state, terminal);
      expect(t.requests.values.single.terminal, isTrue);
      expect(t.requests.values.single.reasonCode, 101);
    });
  }
  for (final code in [409, 422]) {
    test('HTTP $code preserves rejection reason and never reports completed',
        () async {
      final t = transport(MockClient((r) async => r.method == 'POST'
          ? reply({
              'error': 'invalid_target',
              'message': '目标不可用',
              'reason_code': 23
            }, code)
          : initial(r)));
      await t.connect();
      await expectLater(t.sendTask(41, regionId: 'region-test'),
          throwsA(predicate((e) => e.toString().contains('目标不可用'))));
      expect(t.requests.values.single.state, 'REJECTED');
      expect(t.requests.values.single.reasonCode, 23);
    });
  }
  for (final pair in {
    4: '/api/v1/stop',
    6: '/api/v1/estop',
    7: '/api/v1/estop/reset'
  }.entries) {
    test('Task${pair.key} uses formal control endpoint and delivery-only 202',
        () async {
      final t = transport(MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, pair.value);
          final body = jsonDecode(r.body);
          expect(body.containsKey('task_id'), isFalse);
          expect(body['api_version'], '1.0');
          expect(body['user_confirmed'], pair.key == 7);
          return reply(receipt(r), 202);
        }
        return initial(r);
      }));
      await t.connect();
      await t.sendTask(pair.key, userConfirmed: pair.key == 7);
      expect(t.requests.values.single.state, 'ACCEPTED');
      expect(t.requests.values.single.terminal, isFalse);
    });
  }
  test(
      'Reset failure stays on original ID and missing backend reason is not invented',
      () async {
    String? command;
    final t = transport(MockClient((r) async {
      if (r.method == 'POST') {
        command = jsonDecode(r.body)['command_id'];
        return reply(receipt(r), 202);
      }
      if (r.url.path.startsWith('/api/v1/commands/')) {
        return reply({
          'command': {
            'command_id': command,
            'state': 'FAILED',
            'reason_code': 0,
            'message': ''
          }
        });
      }
      return initial(r);
    }));
    await t.connect();
    await t.sendTask(7, userConfirmed: true);
    await t.pollSubmissions();
    expect(t.requests.values.single.commandId, command);
    expect(t.requests.values.single.state, 'FAILED');
    expect(t.requests.values.single.message, contains('未提供详细原因'));
  });
  test('Task43 uses configured charger_id and same sequence tracking mechanism',
      () async {
    final t = transport(MockClient((r) async {
      if (r.method == 'POST') {
        expect(jsonDecode(r.body)['parameters'],
            {'charger_id': 'configured-test-charger'});
        return reply(receipt(r), 202);
      }
      return initial(r);
    }));
    await t.connect();
    await t.sendTask(43, chargerId: 'configured-test-charger');
    expect(t.requests.values.single.sequenceId, isNotNull);
  });
  test(
      'POST timeout retains original IDs, query 404 stays unknown, no automatic resubmission',
      () async {
    var posts = 0;
    final t = transport(MockClient((r) async {
      if (r.method == 'POST') {
        posts++;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return reply({}, 202);
      }
      return initial(r);
    }), timeout: const Duration(milliseconds: 10));
    await t.connect();
    await expectLater(t.sendTask(41, regionId: 'region-test'),
        throwsA(isA<TimeoutException>()));
    final r = t.requests.values.single;
    final originalId = r.commandId;
    expect(r.state, 'UNKNOWN');
    expect(r.outcomeUnknown, isTrue);
    await t.pollSubmissions();
    expect(r.trackingUnavailable, isTrue);
    expect(r.commandId, originalId);
    await expectLater(t.sendTask(41, regionId: 'region-test'),
        throwsA(isA<TransportException>()));
    expect(posts, 1);
    await Future<void>.delayed(const Duration(milliseconds: 90));
  });
  test('offline GET and request timeout remain explicit failures', () async {
    final t = transport(
        MockClient((r) async => throw http.ClientException('offline')));
    final event = t.snapshots.first;
    await expectLater(t.connect(), throwsA(isA<http.ClientException>()));
    expect((await event).gatewayConnected, isFalse);
    final slow = transport(MockClient((r) async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return reply(state());
    }), timeout: const Duration(milliseconds: 5));
    await expectLater(slow.connect(), throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  test(
      'malformed 202 remains UNKNOWN and foreign status_url never receives token',
      () async {
    final urls = <String>[];
    final t = transport(MockClient((r) async {
      urls.add(r.url.host);
      return r.method == 'POST'
          ? reply({
              'accepted': true,
              'status_url': 'https://foreign.invalid/api/v1/commands/c'
            }, 202)
          : initial(r);
    }), token: 'test-only-token');
    await t.connect();
    await expectLater(t.sendTask(6), throwsA(isA<TransportException>()));
    expect(t.requests.values.single.outcomeUnknown, isTrue);
    expect(urls.every((host) => host == 'mock.invalid'), isTrue);
  });
  test(
      'controller checks Registry map identity and rejects empty Charger before POST',
      () async {
    var posts = 0;
    const token = 'test-only-token';
    final authorization = <String?>[];
    final client = MockClient((r) async {
      authorization.add(r.headers['Authorization']);
      if (r.method == 'POST') {
        posts++;
        return reply(
            {'error': 'rejected $token', 'message': 'error $token'}, 401);
      }
      return initial(r);
    });
    final controller = AppController(client: client);
    addTearDown(controller.dispose);
    addTearDown(client.close);
    await controller.testConnection('http://mock.invalid',
        accessToken: 'test-only-token');
    await Future<void>.delayed(Duration.zero);
    await controller.importTargets(jsonEncode(targets()));
    expect(controller.selectedRegionId, 'region-test');
    await expectLater(controller.sendTask(43),
        throwsA(predicate((e) => e.toString().contains('尚未配置'))));
    final mismatch = targets();
    mismatch['map'] = {...identity, 'revision': 'r2'};
    await controller.importTargets(jsonEncode(mismatch));
    await expectLater(controller.sendTask(41),
        throwsA(predicate((e) => e.toString().contains('身份不一致'))));
    expect(posts, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gateway_token'), isNull);
    expect(controller.token, token);
    expect(authorization, isNotEmpty);
    expect(authorization.every((value) => value == 'Bearer $token'), isTrue);
    expect(prefs.getString('target_registry_json'), isNotEmpty);
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      await runZoned(() async {
        await expectLater(controller.sendTask(6),
            throwsA(predicate((e) => !e.toString().contains(token))));
      }, zoneSpecification:
          ZoneSpecification(print: (self, parent, zone, message) {
        logs.add(message);
      }));
    } finally {
      debugPrint = previousDebugPrint;
    }
    expect(controller.error, isNot(contains(token)));
    expect(controller.submissions.single.message, isNot(contains(token)));
    expect(controller.submissions.single.response.toString(),
        isNot(contains(token)));
    expect(logs.join('\n'), isNot(contains(token)));
    expect(authorization.last, 'Bearer $token');
    final restartedClient = MockClient((r) async {
      expect(r.headers.containsKey('Authorization'), isFalse);
      return initial(r);
    });
    final restarted = AppController(client: restartedClient);
    addTearDown(restarted.dispose);
    addTearDown(restartedClient.close);
    await restarted.initialize();
    expect(restarted.token, isEmpty);
    expect(prefs.getString('gateway_token'), isNull);
    expect(restarted.selectedRegionId, 'region-test');
    expect(restarted.registry!.map.revision, 'r2');
    expect(restarted.registry!.chargers, isEmpty);
  });
  test('ordinary HTTP request pending does not block STOP or ESTOP', () async {
    final pending = Completer<http.Response>();
    final posted = <int>[];
    final client = MockClient((r) async {
      if (r.method != 'POST') return initial(r);
      if (r.url.path == '/api/v1/tasks') {
        posted.add(41);
        return pending.future;
      }
      posted.add(r.url.path == '/api/v1/stop' ? 4 : 6);
      return reply(receipt(r), 202);
    });
    final controller = AppController(client: client);
    addTearDown(controller.dispose);
    addTearDown(client.close);
    await controller.testConnection('http://mock.invalid');
    await Future<void>.delayed(Duration.zero);
    await controller.importTargets(jsonEncode(targets()));
    final navigation = controller.sendTask(41);
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    await controller.sendTask(4);
    await controller.sendTask(6);
    expect(posted, [41, 4, 6]);
    final request = controller.submissions.firstWhere((r) => r.taskId == 41);
    pending.complete(reply({
      'accepted': true,
      'sequence_id': request.sequenceId,
      'status_url': '/api/v1/sequences/${request.sequenceId}'
    }, 202));
    await navigation;
  });
}
