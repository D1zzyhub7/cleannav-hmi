import 'dart:math' as math;

class MapOrigin {
  const MapOrigin({required this.x, required this.y, required this.yaw});

  final double x;
  final double y;
  final double yaw;
}

class MapRobotPose {
  const MapRobotPose({required this.x, required this.y, required this.yaw});

  final double x;
  final double y;
  final double yaw;
}

class OccupancyMap {
  const OccupancyMap({
    required this.seq,
    required this.frameId,
    required this.width,
    required this.height,
    required this.resolution,
    required this.origin,
    required this.data,
    this.ageSec,
    this.robotPose,
  });

  final int seq;
  final String frameId;
  final int width;
  final int height;
  final double resolution;
  final MapOrigin origin;
  final List<int> data;
  final double? ageSec;
  final MapRobotPose? robotPose;

  factory OccupancyMap.fromJson(Map<String, dynamic> json) {
    final width = (json['width'] as num).toInt();
    final height = (json['height'] as num).toInt();
    final resolution = (json['resolution'] as num).toDouble();
    final originJson = json['origin'] as Map<String, dynamic>;
    final rawData = json['data'] as List<dynamic>;
    if (
        json['ok'] != true ||
        width <= 0 ||
        height <= 0 ||
        !resolution.isFinite ||
        resolution <= 0 ||
        rawData.length != width * height) {
      throw const FormatException('invalid OccupancyGrid metadata');
    }
    final data = rawData.map((value) => (value as num).toInt()).toList();
    if (data.any((value) => value < -1 || value > 100)) {
      throw const FormatException('invalid OccupancyGrid cell value');
    }
    final robotJson = json['robot_pose'] as Map<String, dynamic>?;
    return OccupancyMap(
      seq: (json['seq'] as num).toInt(),
      frameId: json['frame_id'].toString(),
      width: width,
      height: height,
      resolution: resolution,
      origin: MapOrigin(
        x: (originJson['x'] as num).toDouble(),
        y: (originJson['y'] as num).toDouble(),
        yaw: (originJson['yaw'] as num).toDouble(),
      ),
      data: List.unmodifiable(data),
      ageSec: (json['age_sec'] as num?)?.toDouble(),
      robotPose: robotJson == null
          ? null
          : MapRobotPose(
              x: (robotJson['x'] as num).toDouble(),
              y: (robotJson['y'] as num).toDouble(),
              yaw: (robotJson['yaw'] as num).toDouble(),
            ),
    );
  }

  ({double x, double y}) worldToCell(double worldX, double worldY) {
    final dx = worldX - origin.x;
    final dy = worldY - origin.y;
    final cosine = math.cos(origin.yaw);
    final sine = math.sin(origin.yaw);
    return (
      x: (cosine * dx + sine * dy) / resolution,
      y: (-sine * dx + cosine * dy) / resolution,
    );
  }
}
