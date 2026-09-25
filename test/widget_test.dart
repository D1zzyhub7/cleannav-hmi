import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/main.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/screens/connection_page.dart';
import 'package:cleannav_mobile/widgets/mission_map.dart';

void main() {
  testWidgets('CleanNav app renders its competition HMI shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CleanNavApp());
    await tester.pump();

    expect(find.text('CleanNav'), findsOneWidget);
    expect(find.byType(CleanNavApp), findsOneWidget);
  });

  testWidgets('real RTAB map renders pose and unavailable pose notice', (
    WidgetTester tester,
  ) async {
    final map = OccupancyMap.fromJson({
      'ok': true,
      'seq': 1,
      'frame_id': 'map',
      'width': 2,
      'height': 2,
      'resolution': 0.5,
      'origin': {'x': 0, 'y': 0, 'yaw': 0},
      'data': [-1, 0, 50, 100],
      'robot_pose': null,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MissionMap(map: map)),
    ));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('机器人位姿暂不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map unavailable does not render a simulated route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MissionMap(map: null)),
    ));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('进入演示'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection page has only Gateway settings', (
    WidgetTester tester,
  ) async {
    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ConnectionPage(controller: controller)),
    ));

    expect(find.text('网络网关'), findsOneWidget);
    final urlField = tester.widget<TextField>(find.byType(TextField).first);
    expect(urlField.decoration?.hintText, '例如：http://10.218.39.57:18082');
    expect(find.text('蓝牙连接'), findsNothing);
    expect(find.text('进入演示'), findsNothing);
    expect(find.text('访问令牌'), findsNothing);
    controller.dispose();
  });
}
