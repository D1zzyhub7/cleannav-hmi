import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/models/static_map.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/services/http_transport.dart';
import 'package:cleannav_mobile/screens/home_shell.dart';

http.Response state() => http.Response(
    jsonEncode({
      'connection': {'gateway': 'CONNECTED'},
      'robot': {},
      'safety': {},
      'status_health': {}
    }),
    200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('map projection accounts for origin, image height and rotated origin',
      () {
    final p = worldToImage(
        x: 12,
        y: 23,
        origin: const MapOrigin(x: 10, y: 20, yaw: 0),
        resolution: 0.5,
        height: 100);
    expect(p.x, 4);
    expect(p.y, 94);
    final r = worldToImage(
        x: 10,
        y: 22,
        origin: MapOrigin(x: 10, y: 20, yaw: math.pi / 2),
        resolution: 0.5,
        height: 100);
    expect(r.x, closeTo(4, 1e-9));
    expect(r.y, closeTo(100, 1e-9));
  });
  test('default assets load and admin override persists across controllers',
      () async {
    final c = AppController();
    await c.initialize();
    expect(c.selectedRegionId, 'pillar_v1');
    expect(c.selectedChargerId, 'charger_sim_01');
    expect(c.staticMap!.width, greaterThan(0));
    final data =
        jsonDecode(await rootBundle.loadString('assets/app_targets.json'))
            as Map<String, dynamic>;
    data['chargers'] = [
      {'charger_id': 'admin_charger', 'display_name': 'Admin'}
    ];
    await c.importTargets(jsonEncode(data));
    c.dispose();
    final next = AppController();
    await next.initialize();
    expect(next.selectedChargerId, 'admin_charger');
    next.dispose();
  });
  testWidgets(
      'state is single-flight; map never fetched; dispose stops timer and late response',
      (tester) async {
    var count = 0;
    final paths = <String>[];
    final pending = Completer<http.Response>();
    final t = HttpTransport(
        baseUrl: 'http://test',
        client: MockClient((r) {
          paths.add(r.url.path);
          count++;
          return count == 1 ? Future.value(state()) : pending.future;
        }));
    var events = 0;
    t.snapshots.listen((_) => events++);
    await t.connect();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(count, 2);
    expect(paths.every((p) => p == '/api/v1/state'), true);
    await t.dispose();
    final before = events;
    pending.complete(state());
    await tester.pump(const Duration(seconds: 5));
    expect(count, 2);
    expect(events, before);
  });
  testWidgets(
      'dispose during initial connection cannot create timer or notify controller',
      (tester) async {
    final pending = Completer<http.Response>();
    var count = 0;
    final c = AppController(client: MockClient((r) {
      count++;
      return pending.future;
    }));
    final connecting = c.testConnection('http://test', save: false);
    await tester.pump();
    expect(count, 1);
    c.dispose();
    pending.complete(state());
    await connecting;
    await tester.pump(const Duration(seconds: 6));
    expect(count, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('timeout and unknown state recover without another transport',
      (tester) async {
    var count = 0;
    final t = HttpTransport(
        baseUrl: 'http://test',
        requestTimeout: const Duration(milliseconds: 200),
        client: MockClient((r) {
          count++;
          return count == 2
              ? Completer<http.Response>().future
              : Future.value(state());
        }));
    final states = <bool>[];
    t.snapshots.listen((s) => states.add(s.gatewayConnected));
    await t.connect();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(states.last, false);
    await tester.pump(const Duration(seconds: 1));
    expect(states.last, true);
    await t.dispose();
  });
  testWidgets(
      '30 overview/task/connection cycles keep one state poller and no live map requests',
      (tester) async {
    var count = 0;
    final paths = <String>[];
    final c = AppController(client: MockClient((r) async {
      paths.add(r.url.path);
      count++;
      return state();
    }));
    await tester.runAsync(() => c.initialize());
    await c.testConnection('http://test', save: false);
    await tester.pumpWidget(MaterialApp(home: HomeShell(controller: c)));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      for (final label in ['任务', '连接', '总览']) {
        await tester.tap(find.text(label).last);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(paths.every((p) => p == '/api/v1/state'), true);
    expect(count, inInclusiveRange(9, 11));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    final before = count;
    await tester.pump(const Duration(seconds: 3));
    expect(count, before);
  });
}
