import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/occupancy_map.dart';
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
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFD3D8D7));
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
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEDF1F0));
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
      Offset((size.width - painter.width) / 2, (size.height - painter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant UnavailableMapPainter oldDelegate) => false;
}
