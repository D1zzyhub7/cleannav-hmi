import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/screens/tasks_page.dart';
import 'package:cleannav_mobile/services/http_transport.dart';

class _ReceiptController extends AppController {
  _ReceiptController(this.entries);
  final List<TaskSubmission> entries;
  @override
  List<TaskSubmission> get submissions => entries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'lost response',
    'POST timeout',
    '202',
    'GET unavailable',
    'restored'
  ]) {
    testWidgets('$scenario UI preserves identity without claiming success',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final receipt = TaskSubmission(41, 'original-command',
          'original-sequence', '/api/v1/sequences/original-sequence', const {});
      receipt.state = scenario == '202' ? 'ACCEPTED' : 'UNKNOWN';
      receipt.outcomeUnknown = scenario != '202';
      receipt.trackingUnavailable = scenario == 'GET unavailable';
      final controller = _ReceiptController([receipt]);
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TasksPage(controller: controller))));
      expect(find.text('original-command'), findsOneWidget);
      expect(find.text('Status URL: /api/v1/sequences/original-sequence'),
          findsOneWidget);
      expect(find.textContaining('SUCCEEDED'), findsNothing);
      expect(find.textContaining('回执丢失或损坏时，须人工核对车端任务'), findsOneWidget);
      expect(find.text(scenario == '202' ? 'ACCEPTED' : 'UNKNOWN'),
          findsOneWidget);
      if (scenario != '202') {
        expect(find.textContaining('结果未知 / 待核对'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
  test(
      'receipt without recoverable identity is retained; navigation POST remains blocked',
      () async {
    const corrupted = '[{"task_id":41,"command_id":"original-command"}]';
    SharedPreferences.setMockInitialValues({
      'api_base': 'http://mock.invalid',
      'task_receipts:http://mock.invalid': corrupted,
    });
    var posts = 0;
    final client = MockClient((r) async {
      if (r.method == 'POST') posts++;
      return http.Response('{}', 200);
    });
    final controller = AppController(client: client);
    await controller.initialize();
    expect(controller.error, contains('回执损坏'));
    await expectLater(controller.sendTask(41), throwsException);
    expect(posts, 0);
    expect(
        (await SharedPreferences.getInstance())
            .getString('task_receipts:http://mock.invalid'),
        corrupted);
    controller.dispose();
    client.close();
  });
}
