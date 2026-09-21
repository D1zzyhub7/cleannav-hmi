import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/main.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/models/vehicle_state.dart';
import 'package:cleannav_mobile/screens/connection_page.dart';
import 'package:cleannav_mobile/widgets/mission_map.dart';

void main() {
  testWidgets(
    'CleanNav app renders its HMI shell',
    (WidgetTester tester) async {
      await tester.pumpWidget(const CleanNavApp());
      await tester.pump();

      expect(find.text('CleanNav'), findsOneWidget);
      expect(find.byType(CleanNavApp), findsOneWidget);
    },
  );

  testWidgets('RTAB map painter renders grid and robot pose without crashing', (
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
      'robot_pose': {'x': 0.5, 'y': 0.5, 'yaw': 0.0},
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MissionMap(
          state: VehicleState.initial().copyWith(
            connection: ConnectionKind.network,
          ),
          map: map,
        ),
      ),
    ));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connection page targets a configurable PC gateway URL', (
    WidgetTester tester,
  ) async {
    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ConnectionPage(controller: controller)),
    ));

    expect(find.text('CleanNav PC Gateway'), findsWidgets);
    final urlField = tester.widget<TextField>(find.byType(TextField).first);
    expect(urlField.decoration?.hintText, 'http://<PC Wi-Fi IP>:18082');
    controller.dispose();
  });
}
