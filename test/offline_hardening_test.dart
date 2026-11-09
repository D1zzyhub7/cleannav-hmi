import 'dart:async';
import 'dart:convert';
import 'package:cleannav_mobile/controllers/agent_demo_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/models/hil_snapshot.dart';
import 'package:cleannav_mobile/services/http_transport.dart';
import 'package:cleannav_mobile/screens/home_shell.dart';
import 'hmi_contract_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final task in [41, 43]) {
    test('Task$task process recreation and reconnect only GET original receipt',
        () async {
      List<dynamic> disk = [];
      var posts = 0;
      var status = 'RUNNING';
      var offline = false;
      String? original;
      final queries = <String>[];
      final client = MockClient((r) async {
        if (r.url.path == '/api/v1/state') {
          return fixture.reply(fixture.state());
        }
        if (r.method == 'POST') {
          posts++;
          final receipt = fixture.receipt(r);
          original = receipt['status_url'] as String;
          return fixture.reply(receipt, 202);
        }
        queries.add(r.url.path);
        if (offline) throw TimeoutException('GET timed out');
        return fixture.reply({
          'sequence': {
            'sequence_id': r.url.path.split('/').last,
            'state': status
          }
        });
      });
      HttpTransport create() => HttpTransport(
          baseUrl: 'http://mock.invalid',
          client: client,
          pollInterval: const Duration(days: 1),
          loadReceipts: () async =>
              jsonDecode(jsonEncode(disk)) as List<dynamic>,
          saveReceipts: (r) async =>
              disk = jsonDecode(jsonEncode(r)) as List<dynamic>);
      var t = create();
      await t.connect();
      await t.sendTask(task,
          regionId: 'region-test', chargerId: 'charger-test');
      expect(t.requests.values.single.state, 'ACCEPTED');
      expect(disk.single['status_url'], original);
      // Discard every in-memory object, retain only serialized storage (process death model).
      await t.dispose();
      t = create();
      await t.connect();
      expect(t.requests.values.single.state, 'RUNNING');
      offline = true;
      await t.pollSubmissions();
      expect(t.requests.values.single.trackingUnavailable, true);
      expect(disk, isNotEmpty);
      offline = false;
      await t.pollSubmissions();
      expect(t.requests.values.single.trackingUnavailable, false);
      await t.setForeground(false);
      await t.setForeground(true);
      expect(posts, 1);
      expect(queries.every((q) => q == original), true);
      for (final terminal in ['SUCCEEDED', 'CANCELED', 'EMERGENCY_STOPPED']) {
        status = terminal;
        await t.pollSubmissions();
        expect(t.requests.values.single.state, terminal);
        expect(disk, isEmpty);
        final count = queries.length;
        await t.pollSubmissions();
        expect(queries.length, count);
        // Next terminal scenario restores the same prior receipt, never POST.
        if (terminal != 'EMERGENCY_STOPPED') {
          final r = t.requests.values.single;
          disk = [
            {
              'task_id': task,
              'command_id': r.commandId,
              'sequence_id': r.sequenceId,
              'status_url': r.statusUrl
            }
          ];
          await t.dispose();
          status = 'RUNNING';
          t = create();
          await t.connect();
        }
      }
      await t.dispose();
      expect(posts, 1);
      client.close();
    });
  }
  test(
      'intent is durable before POST; ambiguous POST restored with zero retries',
      () async {
    List<dynamic> disk = [];
    var posts = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/state') return fixture.reply(fixture.state());
      if (r.method == 'POST') {
        expect(disk, hasLength(1));
        posts++;
        throw TimeoutException('POST uncertain');
      }
      return fixture.reply({}, 404);
    });
    HttpTransport create() => HttpTransport(
        baseUrl: 'http://mock.invalid',
        client: client,
        pollInterval: const Duration(days: 1),
        loadReceipts: () async => disk,
        saveReceipts: (r) async => disk = r);
    final first = create();
    await first.connect();
    await expectLater(first.sendTask(41, regionId: 'r'), throwsException);
    await first.dispose();
    final next = create();
    await next.connect();
    await expectLater(next.sendTask(43, chargerId: 'c'), throwsException);
    expect(posts, 1);
    expect(next.requests.values.single.trackingUnavailable, true);
    await next.dispose();
  });
  test('failed durable write prevents POST', () async {
    var posts = 0;
    final t = HttpTransport(
        baseUrl: 'http://mock.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return fixture.reply(fixture.state());
        }),
        saveReceipts: (_) async => throw StateError('disk unavailable'));
    await t.connect();
    await expectLater(t.sendTask(41, regionId: 'r'), throwsA(anything));
    expect(posts, 0);
    await t.dispose();
  });
  test('server errors and state messages redact Bearer token', () async {
    const secret = 'secret-token-for-test';
    final t = HttpTransport(
        baseUrl: 'http://mock.invalid',
        token: secret,
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer $secret');
          if (r.method == 'POST') {
            return fixture.reply({'message': secret}, 401);
          }
          final body = fixture.state();
          (body['robot'] as Map)['message'] = secret;
          return fixture.reply(body);
        }));
    final states = <HilSnapshot>[];
    t.snapshots.listen(states.add);
    await t.connect();
    await expectLater(t.sendTask(6),
        throwsA(predicate((e) => !e.toString().contains(secret))));
    expect(t.requests.values.single.message, isNot(contains(secret)));
    expect(
        t.requests.values.single.response.toString(), isNot(contains(secret)));
    await Future<void>.delayed(Duration.zero);
    expect(states.last.systemMessage, '[REDACTED]');
    await t.dispose();
  });
  for (final version in ['1.0', '1.1']) {
    test('SafetyStatus $version stale and malformed values remain UNKNOWN', () {
      final body = fixture.state();
      final safety = body['safety'] as Map;
      safety['interface_version'] = version;
      expect(HilSnapshot.fromJson(body, gatewayConnected: true).emergencyStop,
          false);
      safety['fresh'] = false;
      final stale = HilSnapshot.fromJson(body, gatewayConnected: true);
      expect(stale.emergencyStop, null);
      expect(stale.blockAll, null);
      safety['fresh'] = true;
      safety['emergency_stop_active'] = 'false';
      expect(HilSnapshot.fromJson(body, gatewayConnected: true).emergencyStop,
          null);
    });
  }
  testWidgets(
      'stalled GET expires cached Safety; background clears and resumes GET only',
      (tester) async {
    final pending = Completer<http.Response>();
    var gets = 0;
    final states = <HilSnapshot>[];
    final t = HttpTransport(
        baseUrl: 'http://mock.invalid',
        requestTimeout: const Duration(seconds: 2),
        client: MockClient((r) {
          gets++;
          return gets == 1
              ? Future.value(fixture.reply(fixture.state()))
              : pending.future;
        }));
    t.snapshots.listen(states.add);
    await t.connect();
    await tester.pump();
    expect(states.last.emergencyStop, false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(states.last.emergencyStop, null);
    expect(states.last.gatewayConnected, false);
    await t.setForeground(false);
    final count = gets;
    await tester.pump(const Duration(seconds: 5));
    expect(gets, count);
    pending.complete(fixture.reply(fixture.state()));
    await tester.pump();
    expect(states.last.emergencyStop, null);
    await t.setForeground(true);
    await tester.pump();
    expect(states.last.emergencyStop, false);
    await t.dispose();
  });
  test(
      'invalid admin JSON leaves valid in-memory and persistent configuration intact',
      () async {
    final c = AppController();
    await c.initialize();
    final original = c.registry;
    final text = c.registryJson;
    for (final bad in ['{', '[]', '{"map":42}', '{"map":{}}']) {
      await expectLater(c.importTargets(bad), throwsA(anything));
      expect(c.registry, same(original));
      expect(c.registryJson, text);
      expect(
          (await SharedPreferences.getInstance())
              .getString('target_registry_json'),
          null);
    }
    c.dispose();
  });
  test(
      'controller reconnect/restart retains receipt and session token is not persisted',
      () async {
    var posts = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/state') {
        final body = fixture.state();
        body['map_identity'] = jsonDecode(
            await rootBundle.loadString('assets/app_targets.json'))['map'];
        return fixture.reply(body);
      }
      if (r.method == 'POST') {
        posts++;
        return fixture.reply(fixture.receipt(r), 202);
      }
      return fixture.reply({
        'sequence': {
          'sequence_id': r.url.path.split('/').last,
          'state': 'RUNNING'
        }
      });
    });
    var c = AppController(client: client);
    await c.initialize();
    await c.testConnection('http://mock.invalid',
        accessToken: 'session-secret');
    await Future<void>.delayed(Duration.zero);
    await c.sendTask(41);
    final url = c.submissions.single.statusUrl;
    await c.testConnection('http://mock.invalid');
    expect(c.submissions.single.statusUrl, url);
    expect(posts, 1);
    c.dispose();
    c = AppController(client: client);
    await c.initialize();
    expect(c.token, '');
    expect((await SharedPreferences.getInstance()).getString('gateway_token'),
        null);
    expect(c.submissions.single.statusUrl, url);
    expect(posts, 1);
    c.dispose();
  });
  test(
      'ESTOP blocks navigation; RESET never resumes old tasks and STOP remains distinct',
      () async {
    var emergency = true;
    final paths = <String>[];
    final c = AppController(client: MockClient((r) async {
      if (r.method == 'POST') {
        paths.add(r.url.path);
        return fixture.reply(fixture.receipt(r), 202);
      }
      final body = fixture.state();
      (body['safety'] as Map)['emergency_stop_active'] = emergency;
      body['map_identity'] = jsonDecode(
          await rootBundle.loadString('assets/app_targets.json'))['map'];
      return fixture.reply(body);
    }));
    await c.initialize();
    await c.testConnection('http://mock.invalid');
    await Future<void>.delayed(Duration.zero);
    await expectLater(c.sendTask(41), throwsException);
    await c.sendTask(6);
    await c.sendTask(4);
    await expectLater(c.sendTask(7), throwsException);
    await c.emergencyReset();
    emergency = false;
    await c.setForeground(false);
    await c.setForeground(true);
    expect(paths, ['/api/v1/estop', '/api/v1/stop', '/api/v1/estop/reset']);
    c.dispose();
  });
  for (final size in [
    const Size(320, 640),
    const Size(800, 480),
    const Size(1024, 1366)
  ]) {
    testWidgets(
        'repeated page transitions at $size keep layout and dispose resources',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController();
      await tester.runAsync(() => c.initialize());
      await tester.pumpWidget(MaterialApp(home: HomeShell(controller: c)));
      for (var i = 0; i < 3; i++) {
        for (final label in ['任务', '连接', 'Demo 演示', '总览']) {
          await tester.tap(find.text(label).last);
          await tester.pump();
          expect(tester.takeException(), null);
        }
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), null);
    });
  }
  test(
      'actual status GET timeout keeps original receipt and later GET succeeds',
      () async {
    var delayed = true;
    var posts = 0;
    String? sequence;
    final pending = Completer<http.Response>();
    final t = HttpTransport(
        baseUrl: 'http://mock.invalid',
        requestTimeout: const Duration(milliseconds: 30),
        pollInterval: const Duration(days: 1),
        client: MockClient((r) async {
          if (r.url.path == '/api/v1/state') {
            return fixture.reply(fixture.state());
          }
          if (r.method == 'POST') {
            posts++;
            sequence = jsonDecode(r.body)['sequence_id'] as String;
            return fixture.reply(fixture.receipt(r), 202);
          }
          if (delayed) return pending.future;
          return fixture.reply({
            'sequence': {'sequence_id': sequence, 'state': 'SUCCEEDED'}
          });
        }));
    await t.connect();
    await t.sendTask(41, regionId: 'r');
    final original = t.requests.values.single.statusUrl;
    await t.pollSubmissions();
    expect(t.requests.values.single.trackingUnavailable, true);
    pending.complete(fixture.reply({}, 404));
    delayed = false;
    await t.pollSubmissions();
    expect(t.requests.values.single.state, 'SUCCEEDED');
    expect(t.requests.values.single.statusUrl, original);
    expect(posts, 1);
    await t.dispose();
  });
  testWidgets('inactive Demo pauses its existing timer and resumes only GET',
      (tester) async {
    var gets = 0;
    var posts = 0;
    final plan = {
      'plan_id': 'demo-plan',
      'text': 'demo',
      'state': 'RUNNING',
      'parser_mode': 'rules',
      'execution_mode': 'simulation',
      'steps': <dynamic>[]
    };
    final c = AgentDemoController(client: MockClient((r) async {
      if (r.url.path.endsWith('/info')) {
        return fixture
            .reply({'execution_mode': 'simulation', 'service_id': 'test'});
      }
      if (r.method == 'POST') {
        posts++;
      } else {
        gets++;
      }
      return fixture.reply(plan, r.method == 'POST' ? 202 : 200);
    }));
    await c.submitInput(baseUrl: 'http://demo.invalid', text: 'demo');
    c.setActive(false);
    await tester.pump(const Duration(seconds: 5));
    expect(gets, 0);
    c.setActive(true);
    await tester.pump();
    expect(gets, 1);
    await tester.pump(c.pollInterval);
    expect(gets, 2);
    expect(posts, 1);
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
    expect(gets, 2);
  });
  test('storage failure never prevents explicit STOP or ESTOP', () async {
    final paths = <String>[];
    final t = HttpTransport(
        baseUrl: 'http://mock.invalid',
        saveReceipts: (_) async => throw StateError('storage unavailable'),
        client: MockClient((r) async {
          if (r.method == 'POST') {
            paths.add(r.url.path);
            return fixture.reply(fixture.receipt(r), 202);
          }
          return fixture.reply(fixture.state());
        }));
    await t.connect();
    await t.sendTask(6);
    await t.sendTask(4);
    expect(paths, ['/api/v1/estop', '/api/v1/stop']);
    expect(t.requests.values.every((r) => r.state == 'ACCEPTED'), true);
    expect(t.requests.values.every((r) => r.message.contains('未能保存')), true);
    await t.dispose();
  });
  test(
      'background connection restores storage without polling until foreground',
      () async {
    var gets = 0;
    final t = HttpTransport(
        baseUrl: 'http://mock.invalid',
        client: MockClient((r) async {
          gets++;
          return fixture.reply(fixture.state());
        }));
    await t.setForeground(false);
    await t.connect();
    expect(gets, 0);
    await t.setForeground(true);
    expect(gets, 1);
    await t.dispose();
  });
}
