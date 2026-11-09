import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cleannav_mobile/controllers/app_controller.dart';
import 'package:cleannav_mobile/models/hil_snapshot.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/models/static_map.dart';
import 'package:cleannav_mobile/theme/app_theme.dart';
import 'package:cleannav_mobile/widgets/mission_map.dart';

Future<Map<String, dynamic>> mapJson() async =>
    jsonDecode(await rootBundle.loadString('assets/map.json'))
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'HD scale, original grid and normalized viewport agree at 512 map points',
    () async {
      final data = await mapJson();
      final native = StaticMapData.fromJson(data);
      final hd = StaticMapData.fromJson(data, displayScale: 4);
      final random = math.Random(5105);
      for (var i = 0; i < 512; i++) {
        final x = native.origin.x +
            random.nextDouble() * native.width * native.resolution;
        final y = native.origin.y +
            random.nextDouble() * native.height * native.resolution;
        final grid = worldToImage(
          x: x,
          y: y,
          origin: native.origin,
          resolution: native.resolution,
          height: native.height,
        );
        for (final size in [
          const Size(240, 310),
          const Size(800, 300),
          const Size(1024, 1320),
        ]) {
          final point = hd.projectToViewport(x, y, size.width, size.height);
          expect(point.x, closeTo(grid.x * size.width / native.width, 1e-10));
          expect(point.y, closeTo(grid.y * size.height / native.height, 1e-10));
        }
      }
      final rotated = Map<String, dynamic>.from(data)
        ..['origin'] = [-10.0, 20.0, .7];
      final map = StaticMapData.fromJson(rotated, displayScale: 4);
      final p = map.projectToViewport(
        -10 + math.cos(.7),
        20 + math.sin(.7),
        511,
        660,
      );
      expect(p.x, closeTo(1 / map.resolution, 1e-9));
      expect(p.y, closeTo(660, 1e-9));
    },
  );

  testWidgets(
    'vehicle heading, Region, Charger and goal align across viewports, zoom and pan',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = await tester.runAsync(mapJson);
      final c = AppController();
      c.staticMap = StaticMapData.fromJson(data!, displayScale: 4);
      c.snapshot = HilSnapshot.fromJson({
        'connection': {'gateway': 'CONNECTED'},
        'map_identity': data['map'],
        'status_health': {
          'robot': {'fresh': true},
        },
        'robot': {'localization_ok': true, 'system_state': 'SYSTEM_READY'},
        'task': {
          'state': 'ACTIVE',
          'task_id': 43,
          'active_target_id': 'charger_sim_01',
        },
      }, gatewayConnected: true);
      c.mapPose.value = const MapRobotPose(x: 5, y: 2, yaw: .7);
      for (final viewport in [
        const Size(320, 420),
        const Size(800, 300),
        const Size(240, 600),
        const Size(1200, 900),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: StaticMissionMap(controller: c),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final imageBox = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('static-map-image-layer')),
        );
        final overlay = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('static-map-overlay-layer')),
        );
        expect(overlay.size, imageBox.size);
        expect(
          imageBox.size.width / imageBox.size.height,
          closeTo(511 / 660, 1e-9),
        );
        final capture = await tester.runAsync(
          () => overlay.toImage(pixelRatio: 1),
        );
        final pixels = await tester.runAsync(
          () => capture!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        bool ink(Offset at, Color color) {
          final rgb = color.toARGB32();
          for (var dy = -2; dy <= 2; dy++) {
            for (var dx = -2; dx <= 2; dx++) {
              final x = at.dx.round() + dx, y = at.dy.round() + dy;
              if (x < 0 ||
                  y < 0 ||
                  x >= capture!.width ||
                  y >= capture.height) {
                continue;
              }
              final offset = 4 * (y * capture.width + x);
              if ((pixels!.getUint8(offset) - ((rgb >> 16) & 255)).abs() < 5 &&
                  (pixels.getUint8(offset + 1) - ((rgb >> 8) & 255)).abs() <
                      5 &&
                  (pixels.getUint8(offset + 2) - (rgb & 255)).abs() < 5) {
                return true;
              }
            }
          }
          return false;
        }

        Offset project(double x, double y) {
          final old = worldToImage(
            x: x,
            y: y,
            origin: c.staticMap!.origin,
            resolution: c.staticMap!.resolution,
            height: c.staticMap!.height,
          );
          return Offset(
            old.x * overlay.size.width / 511,
            old.y * overlay.size.height / 660,
          );
        }

        final vehicle = project(5, 2);
        expect(
          ink(vehicle, Colors.blue),
          true,
          reason: 'vehicle center at $viewport',
        );
        expect(
          ink(
            vehicle + Offset(7 * math.cos(.7), -7 * math.sin(.7)),
            Colors.blue,
          ),
          true,
          reason: 'vehicle heading at $viewport',
        );
        for (final marker in c.staticMap!.markers) {
          final center = project(
            (marker['x'] as num).toDouble(),
            (marker['y'] as num).toDouble(),
          );
          expect(
            ink(
              center,
              marker['kind'] == 'charger' ? Colors.purple : AppColors.greenDark,
            ),
            true,
            reason: '${marker['id']} at $viewport',
          );
          if (marker['kind'] == 'charger') {
            expect(ink(center + const Offset(10, 0), Colors.orange), true);
          }
        }
        capture!.dispose();
        final center = tester.getCenter(
          find.byKey(const ValueKey('static-map-content')),
        );
        final a = await tester.startGesture(
          center - const Offset(25, 0),
          pointer: 1,
        );
        final b = await tester.startGesture(
          center + const Offset(25, 0),
          pointer: 2,
        );
        await tester.pump();
        await a.moveTo(center - const Offset(50, 0));
        await b.moveTo(center + const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 100));
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('static-map-content')),
          const Offset(18, -12),
        );
        await tester.pumpAndSettle();
        final origin = imageBox.localToGlobal(Offset.zero);
        final unit = imageBox.localToGlobal(const Offset(1, 0));
        expect(
          (unit - origin).distance,
          greaterThan(1.1),
          reason: 'pinch actually zoomed',
        );
        for (final point in [
          vehicle,
          project(6.8, -3.2),
          project(13.815102233908052, -6.831575183979148),
        ]) {
          final backdrop = imageBox.localToGlobal(point),
              marker = overlay.localToGlobal(point);
          expect((marker - backdrop).distance, lessThan(1e-6));
        }
        await tester.pumpWidget(const SizedBox());
      }
      c.dispose();
    },
  );
}
