import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cleannav_mobile/models/occupancy_map.dart';
import 'package:cleannav_mobile/models/static_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'B5 HD display PNG preserves B3 projection for 128 seeded map-frame samples',
      () async {
    final oldJson = jsonDecode(
      await File('test/fixtures/b3-map.json').readAsString(),
    ) as Map<String, dynamic>;
    final currentJson = jsonDecode(
      await rootBundle.loadString('assets/map.json'),
    ) as Map<String, dynamic>;
    expect(currentJson, oldJson);
    final old = StaticMapData.fromJson(oldJson);
    final current = StaticMapData.fromJson(currentJson);
    final display = jsonDecode(
      await rootBundle.loadString('assets/map_display_metadata.json'),
    ) as Map<String, dynamic>;
    expect(display['display_only'], true);
    expect(display['displayScale'], 4);
    expect(display['scale'], 4);
    expect(display['width'], old.width);
    expect(display['height'], old.height);
    expect(display['resolution'], old.resolution);
    expect(display['origin'], oldJson['origin']);
    final png = await rootBundle.load('assets/map.png');
    expect(png.getUint32(16, Endian.big), old.width * 4);
    expect(png.getUint32(20, Endian.big), old.height * 4);
    final random = math.Random(4104);
    final displayOrigin = MapOrigin(
      x: (display['origin'][0] as num).toDouble(),
      y: (display['origin'][1] as num).toDouble(),
      yaw: (display['origin'][2] as num).toDouble(),
    );
    for (var i = 0; i < 128; i++) {
      final localX = random.nextDouble() * old.width * old.resolution;
      final localY = random.nextDouble() * old.height * old.resolution;
      final x = old.origin.x +
          math.cos(old.origin.yaw) * localX -
          math.sin(old.origin.yaw) * localY;
      final y = old.origin.y +
          math.sin(old.origin.yaw) * localX +
          math.cos(old.origin.yaw) * localY;
      final before = worldToImage(
        x: x,
        y: y,
        origin: old.origin,
        resolution: old.resolution,
        height: old.height,
      );
      final after = worldToImage(
        x: x,
        y: y,
        origin: displayOrigin,
        resolution: (display['resolution'] as num).toDouble(),
        height: display['height'] as int,
      );
      expect(after.x, closeTo(before.x, 1e-10), reason: 'sample $i x');
      expect(after.y, closeTo(before.y, 1e-10), reason: 'sample $i y');
      expect(current.identity.matches(old.identity), true);
    }
  });
}
