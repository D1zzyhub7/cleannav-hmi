import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/occupancy_map.dart';
import '../models/static_map.dart';
import '../controllers/app_controller.dart';
import '../theme/app_theme.dart';

class MissionMap extends StatelessWidget {
  const MissionMap({super.key, required this.map});

  final OccupancyMap? map;

  @override
  Widget build(BuildContext context) {
    final currentMap = map;
    return AspectRatio(
      aspectRatio: 1.22,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: currentMap == null
            ? const CustomPaint(
                painter: UnavailableMapPainter(),
                child: SizedBox.expand(),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: RtabMapPainter(currentMap),
                    ),
                  ),
                  if (currentMap.robotPose == null)
                    const Positioned(
                      left: 10,
                      bottom: 10,
                      child: _MapNotice(text: '机器人位姿暂不可用'),
                    ),
                  if (currentMap.ageSec != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _MapNotice(
                        text: '地图 ${currentMap.ageSec!.toStringAsFixed(1)} s',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class RtabMapPainter extends CustomPainter {
  const RtabMapPainter(this.map);

  final OccupancyMap map;

  Rect _mapRect(Size size) {
    final scale = math.min(size.width / map.width, size.height / map.height);
    final width = map.width * scale;
    final height = map.height * scale;
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  Offset worldToPixel(double worldX, double worldY, Size size) {
    final cell = map.worldToCell(worldX, worldY);
    final rect = _mapRect(size);
    return Offset(
      rect.left + cell.x * rect.width / map.width,
      rect.top + (map.height - cell.y) * rect.height / map.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFD3D8D7));
    final rect = _mapRect(size);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFC4CAC9));
    final cellWidth = rect.width / map.width;
    final cellHeight = rect.height / map.height;
    final paint = Paint();
    for (var row = 0; row < map.height; row++) {
      for (var column = 0; column < map.width; column++) {
        final value = map.data[row * map.width + column];
        if (value < 0) {
          paint.color = const Color(0xFFB8BFBD);
        } else if (value == 0) {
          paint.color = Colors.white;
        } else {
          final shade = (255 - value * 2.55).round().clamp(0, 255).toInt();
          paint.color = Color.fromARGB(255, shade, shade, shade);
        }
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + column * cellWidth,
            rect.top + (map.height - 1 - row) * cellHeight,
            cellWidth + .25,
            cellHeight + .25,
          ),
          paint,
        );
      }
    }

    final robot = map.robotPose;
    if (robot == null) return;
    final center = worldToPixel(robot.x, robot.y, size);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-(robot.yaw - map.origin.yaw));
    final arrow = Path()
      ..moveTo(12, 0)
      ..lineTo(-8, -7)
      ..lineTo(-4, 0)
      ..lineTo(-8, 7)
      ..close();
    canvas.drawCircle(
      Offset.zero,
      13,
      Paint()..color = Colors.white.withValues(alpha: .88),
    );
    canvas.drawPath(arrow, Paint()..color = AppColors.greenDark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RtabMapPainter oldDelegate) {
    final oldPose = oldDelegate.map.robotPose;
    final newPose = map.robotPose;
    return oldDelegate.map.seq != map.seq ||
        oldDelegate.map.ageSec != map.ageSec ||
        oldPose?.x != newPose?.x ||
        oldPose?.y != newPose?.y ||
        oldPose?.yaw != newPose?.yaw;
  }
}

class UnavailableMapPainter extends CustomPainter {
  const UnavailableMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEDF1F0));
    final painter = TextPainter(
      text: const TextSpan(
        text: '地图暂不可用',
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
          (size.width - painter.width) / 2, (size.height - painter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant UnavailableMapPainter oldDelegate) => false;
}

class StaticMissionMap extends StatelessWidget {
  const StaticMissionMap({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final map = controller.staticMap;
    if (map == null) {
      return const SizedBox(height: 180, child: Center(child: Text('静态地图加载中')));
    }
    final current = controller.snapshot.mapIdentity;
    final matches = current != null && map.identity.matches(current);
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = map.width / map.height;
        final maxHeight = constraints.hasBoundedHeight
            ? math.max(0.0, constraints.maxHeight - 36)
            : constraints.maxWidth / ratio;
        final contentWidth = math.min(constraints.maxWidth, maxHeight * ratio);
        final decodeWidth =
            (contentWidth * MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(1, map.displayWidth.toInt());
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: contentWidth,
                height: contentWidth / ratio,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Stack(
                    key: const ValueKey('static-map-content'),
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        key: const ValueKey('static-map-image-layer'),
                        child: Image.asset(
                          'assets/map.png',
                          fit: BoxFit.fill,
                          cacheWidth: decodeWidth,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      RepaintBoundary(
                        key: const ValueKey('static-map-overlay-layer'),
                        child: ValueListenableBuilder<MapRobotPose?>(
                          valueListenable: controller.mapPose,
                          builder: (context, pose, _) => CustomPaint(
                            painter: _PosePainter(
                              map,
                              matches &&
                                      controller.snapshot.localizationOk == true
                                  ? pose
                                  : null,
                              matches
                                  ? controller.snapshot.task.activeTargetId
                                  : '',
                              matches,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              !matches
                  ? '离线参考地图 · 车端地图身份未确认，隐藏实时标记'
                  : controller.mapPose.value == null
                      ? '车辆位置暂不可用'
                      : '▲ 车辆 / 朝向 · ● Region · ■ 充电点 · 橙圈 当前目标',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        );
      },
    );
  }
}

class _PosePainter extends CustomPainter {
  _PosePainter(this.map, this.pose, this.target, this.matches);
  final StaticMapData map;
  final MapRobotPose? pose;
  final String target;
  final bool matches;
  @override
  void paint(Canvas canvas, Size size) {
    Offset project(double x, double y) {
      final p = map.projectToViewport(x, y, size.width, size.height);
      return Offset(p.x, p.y);
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final marker in map.markers) {
      final point = project(
          (marker['x'] as num).toDouble(), (marker['y'] as num).toDouble());
      final paint = Paint()
        ..color =
            marker['kind'] == 'charger' ? Colors.purple : AppColors.greenDark;
      if (marker['kind'] == 'charger') {
        canvas.drawRect(
            Rect.fromCenter(center: point, width: 10, height: 10), paint);
      } else {
        canvas.drawCircle(point, 5, paint);
      }
      if (matches && marker['id'] == target) {
        canvas.drawCircle(
            point,
            10,
            Paint()
              ..color = Colors.orange
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
    }
    final p = pose;
    if (p != null) {
      final center = project(p.x, p.y);
      final forward =
          project(p.x + math.cos(p.yaw), p.y + math.sin(p.yaw)) - center;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(math.atan2(forward.dy, forward.dx));
      final arrow = Path()
        ..moveTo(11, 0)
        ..lineTo(-7, -7)
        ..lineTo(-4, 0)
        ..lineTo(-7, 7)
        ..close();
      canvas.drawPath(arrow, Paint()..color = Colors.blue);
      canvas.drawPath(
          arrow,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PosePainter old) =>
      old.map != map ||
      old.pose != pose ||
      old.target != target ||
      old.matches != matches;
}
