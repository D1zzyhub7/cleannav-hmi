import 'dart:convert';

import 'package:cleannav_mobile/controllers/agent_demo_controller.dart';
import 'package:cleannav_mobile/models/agent_plan.dart';
import 'package:cleannav_mobile/screens/agent_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _plan({String state = 'RUNNING', int completed = 0}) => {
      'plan_id': 'a' * 32,
      'text': '去A区巡航3轮，然后返回充电',
      'state': state,
      'parser_mode': 'rules',
      'execution_mode': 'simulation',
      'error': null,
      'steps': [
        {'action': 'go_to_area', 'area_id': 'A', 'state': 'SUCCEEDED'},
        {'action': 'patrol_clean', 'area_id': 'A', 'rounds': 3,
          'state': state == 'SUCCEEDED' ? 'SUCCEEDED' : 'RUNNING',
          'current_round': completed == 0 ? 1 : completed,
          'completed_rounds': completed},
        {'action': 'return_to_charge', 'state': state == 'SUCCEEDED' ? 'SUCCEEDED' : 'PENDING'},
      ],
    };

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode(body)), status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

bool _isInfo(http.Request request) => request.url.path == '/api/agent/info';
http.Response _info() => _json({'execution_mode': 'simulation', 'service_id': 'test-instance'});

void main() {
  test('demo models preserve completed lap count and business actions', () {
    final plan = AgentPlan.fromJson(_plan(state: 'SUCCEEDED', completed: 3));
    expect(plan.steps.map((step) => step.action), ['go_to_area', 'patrol_clean', 'return_to_charge']);
    expect(plan.steps[1].completedRounds, 3);
    expect(plan.running, isFalse);
    expect(() => AgentPlan.fromJson({..._plan(), 'execution_mode': 'real'}), throwsFormatException);
  });

  test('controller polls the same plan to completion without vehicle tasks', () async {
    final requests = <http.Request>[];
    final controller = AgentDemoController(
      pollInterval: const Duration(days: 1),
      client: MockClient((request) async {
        if (_isInfo(request)) return _info();
        requests.add(request);
        return request.method == 'POST' ? _json(_plan(), status: 202)
            : _json(_plan(state: 'SUCCEEDED', completed: 3));
      }),
    );
    await controller.submitInput(baseUrl: 'http://demo:18083', text: '去A区巡航3轮，然后返回充电');
    await controller.refresh();
    expect(controller.plan?.state, 'SUCCEEDED');
    expect(controller.plan?.steps[1].completedRounds, 3);
    expect(requests.every((request) => request.url.path.startsWith('/api/agent/plans')), isTrue);
    expect(jsonDecode(requests.first.body)['source'], 'text');
    controller.dispose();
  });

  test('unknown delivery retries with the original input identity', () async {
    final bodies = <Map<String, dynamic>>[];
    final controller = AgentDemoController(
      client: MockClient((request) async {
        if (_isInfo(request)) return _info();
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (bodies.length == 1) throw http.ClientException('connection lost');
        return _json(_plan(state: 'SUCCEEDED', completed: 3));
      }),
    );
    await controller.submitInput(baseUrl: 'http://demo:18083', text: '去A区巡航3轮，然后返回充电');
    expect(controller.canRetry, isTrue);
    await controller.retryPending();
    expect(bodies[1]['input_id'], bodies[0]['input_id']);
    expect(controller.canRetry, isFalse);
    expect(controller.plan?.state, 'SUCCEEDED');
    controller.dispose();
  });

  test('definite clarification never creates a plan or retry job', () async {
    final controller = AgentDemoController(client: MockClient((request) async =>
      _isInfo(request) ? _info() : _json({'error': '请说明巡航轮数'}, status: 422)));
    await controller.submitInput(baseUrl: 'http://demo:18083', text: '去A区巡航');
    expect(controller.plan, isNull);
    expect(controller.canRetry, isFalse);
    expect(controller.error, '请说明巡航轮数');
    controller.dispose();
  });

  test('loss of status preserves the last snapshot without claiming completion', () async {
    final controller = AgentDemoController(
      pollInterval: const Duration(days: 1),
      client: MockClient((request) async => _isInfo(request) ? _info() : request.method == 'POST'
          ? _json(_plan(), status: 202) : _json({'error': '服务已重启'}, status: 404)),
    );
    await controller.submitInput(baseUrl: 'http://demo:18083', text: '去A区巡航3轮，然后返回充电');
    await controller.refresh();
    expect(controller.trackingUnavailable, isTrue);
    expect(controller.plan?.state, 'RUNNING');
    expect(controller.trackingError, contains('上次状态不代表当前结果'));
    controller.dispose();
  });

  testWidgets('assistant submits the example and renders all three completed steps', (tester) async {
    final controller = AgentDemoController(
      client: MockClient((request) async => _isInfo(request) ? _info() : _json(_plan(state: 'SUCCEEDED', completed: 3))),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AgentPage(controller: controller))));
    await tester.ensureVisible(find.byKey(const Key('agent-submit')));
    await tester.tap(find.byKey(const Key('agent-submit')));
    await tester.pumpAndSettle();
    expect(find.text('本地规则解析'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('2. A 区巡航清扫 3 轮'), 160, scrollable: find.byType(Scrollable).first);
    expect(find.text('2. A 区巡航清扫 3 轮'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('3. 返回充电处'), 160, scrollable: find.byType(Scrollable).first);
    expect(find.text('3. 返回充电处'), findsOneWidget);
    expect(find.text('已模拟到达充电处；未模拟自动对接或开始充电。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
