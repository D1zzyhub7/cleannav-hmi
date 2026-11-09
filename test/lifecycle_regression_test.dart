import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cleannav_mobile/controllers/app_controller.dart';

void main() {
  testWidgets(
      'fixed connection completing after dispose must not notify or leave timer',
      (tester) async {
    final pending = Completer<http.Response>();
    final c = AppController(client: MockClient((_) => pending.future));
    final connection = c.testConnection('http://test', save: false);
    await tester.pump();
    c.dispose();
    pending.complete(http.Response('{}', 200));
    await connection;
  }, timeout: const Timeout(Duration(seconds: 20)));
}
