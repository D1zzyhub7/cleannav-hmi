import 'dart:math' as math;
import 'occupancy_map.dart';
import 'task_definition.dart';

/// Continuous image coordinates: ROS lower-left origin, PNG top-left origin.
({double x, double y}) worldToImage(
    {required double x,
    required double y,
    required MapOrigin origin,
    required double resolution,
    required int height}) {
  final dx = x - origin.x, dy = y - origin.y;
  final c = math.cos(origin.yaw), s = math.sin(origin.yaw);
  return (
    x: (c * dx + s * dy) / resolution,
    y: height - (-s * dx + c * dy) / resolution
  );
}

class StaticMapData {
  StaticMapData.fromJson(Map<String, dynamic> json, {this.displayScale = 1})
      : identity = MapIdentity.fromJson(json['map'] as Map<String, dynamic>),
        width = json['width'] as int,
        height = json['height'] as int,
        resolution = (json['resolution'] as num).toDouble(),
        origin = MapOrigin(
          x: (json['origin'][0] as num).toDouble(),
          y: (json['origin'][1] as num).toDouble(),
          yaw: (json['origin'][2] as num).toDouble(),
        ),
        markers = (json['markers'] as List).cast<Map<String, dynamic>>();

  /// PNG pixels per original grid cell; origin/resolution remain native.
  final double displayScale;
  double get displayWidth => width * displayScale;
  double get displayHeight => height * displayScale;

  ({double x, double y}) projectToViewport(
    double x,
    double y,
    double viewportWidth,
    double viewportHeight,
  ) {
    final native = worldToImage(
      x: x,
      y: y,
      origin: origin,
      resolution: resolution,
      height: height,
    );
    final displayX = native.x * displayScale;
    final displayY = native.y * displayScale;
    return (
      x: displayX * viewportWidth / displayWidth,
      y: displayY * viewportHeight / displayHeight,
    );
  }

  final MapIdentity identity;
  final int width, height;
  final double resolution;
  final MapOrigin origin;
  final List<Map<String, dynamic>> markers;
}
