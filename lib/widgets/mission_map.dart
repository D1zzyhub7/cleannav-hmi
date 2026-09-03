import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/task_definition.dart';
import '../models/vehicle_state.dart';
import '../theme/app_theme.dart';

class MissionMap extends StatelessWidget {
  const MissionMap({super.key, required this.state});
  final VehicleState state;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.22,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: CustomPaint(painter: MissionMapPainter(state), child: const SizedBox.expand()),
    ),
  );
}

class MissionMapPainter extends CustomPainter {
  MissionMapPainter(this.state);
  final VehicleState state;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEDF4F2));
    _grid(canvas, size);
    _zone(canvas, size, const Rect.fromLTWH(.06,.09,.30,.37), '设备停放区', const Color(0xFF9FB4BC));
    _zone(canvas, size, const Rect.fromLTWH(.67,.08,.27,.36), '重点清扫区', const Color(0xFF67B892));

    final normalized = routePoints(state.route);
    final points = normalized.map((point) => Offset(point.dx * size.width, point.dy * size.height)).toList();
    _route(canvas, points, state.progress);
    _targets(canvas, size, state.route);
    _vehicle(canvas, points, state.progress, state.brushOn, state.waterPumpOn);
    _labels(canvas, size);
  }

  void _grid(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x13718B91)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) canvas.drawLine(Offset(x,0), Offset(x,size.height), paint);
    for (double y = 0; y < size.height; y += 24) canvas.drawLine(Offset(0,y), Offset(size.width,y), paint);
  }

  void _zone(Canvas canvas, Size size, Rect unit, String text, Color color) {
    final rect = Rect.fromLTWH(unit.left * size.width, unit.top * size.height, unit.width * size.width, unit.height * size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = color.withValues(alpha: .07));
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    _dashed(canvas, path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.2, 6, 5);
    _text(canvas, text, Offset(rect.left + 9, rect.top + 8), color: AppColors.muted, size: 9);
  }

  void _route(Canvas canvas, List<Offset> points, double progress) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) path.lineTo(point.dx, point.dy);
    _dashed(canvas, path, Paint()..color = const Color(0xFFB6C8C8)..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round, 3, 8);

    final metric = path.computeMetrics().first;
    final active = metric.extractPath(0, metric.length * progress.clamp(.0, 1.0).toDouble());
    canvas.drawPath(active, Paint()..color = AppColors.green..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }

  void _targets(Canvas canvas, Size size, RouteKind route) {
    final targets = <({Offset point, String label, Color color})>[
      (point: const Offset(.70,.34), label: '落叶', color: AppColors.green),
      (point: const Offset(.67,.28), label: '落叶堆', color: AppColors.amber),
      (point: const Offset(.62,.51), label: '积水', color: AppColors.blue),
      (point: const Offset(.79,.25), label: '一号点', color: const Color(0xFF7B68C4)),
    ];
    for (final target in targets) {
      final p = Offset(target.point.dx * size.width, target.point.dy * size.height);
      canvas.drawCircle(p, 8, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = target.color);
      _text(canvas, target.label, p + const Offset(10,-8), color: AppColors.ink, size: 9, background: Colors.white.withValues(alpha: .9));
    }
  }

  void _vehicle(Canvas canvas, List<Offset> points, double progress, bool brush, bool pump) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) path.lineTo(point.dx, point.dy);
    final metric = path.computeMetrics().first;
    final tangentOffset = (metric.length * progress.clamp(0.0, 1.0).toDouble()).clamp(0, metric.length).toDouble();
    final tangent = metric.getTangentForOffset(tangentOffset)!;
    canvas.save(); canvas.translate(tangent.position.dx, tangent.position.dy); canvas.rotate(tangent.angle);
    if (brush) canvas.drawCircle(Offset.zero, 19, Paint()..color = AppColors.green.withValues(alpha: .13));
    if (pump) canvas.drawCircle(const Offset(-13, 0), 4, Paint()..color = AppColors.blue.withValues(alpha: .65));
    final body = RRect.fromRectAndRadius(const Rect.fromCenter(center: Offset.zero, width: 34, height: 22), const Radius.circular(7));
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromCenter(center: Offset.zero, width: 29, height: 17), const Radius.circular(5)), Paint()..color = AppColors.greenDark);
    _text(canvas, 'CN', const Offset(-7,-5), color: Colors.white, size: 8, bold: true);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(15,-2,9,4), const Radius.circular(2)), Paint()..color = AppColors.green);
    canvas.restore();
  }

  void _labels(Canvas canvas, Size size) {
    _text(canvas, 'HOME', Offset(size.width*.08,size.height*.82), color: AppColors.muted, size: 8, background: Colors.white.withValues(alpha: .9));
    _text(canvas, state.route.name.toUpperCase(), Offset(size.width-88,size.height-24), color: AppColors.greenDark, size: 8, bold: true, background: Colors.white.withValues(alpha: .92));
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, math.min(distance + dash, metric.length)), paint);
        distance += dash + gap;
      }
    }
  }

  void _text(Canvas canvas, String value, Offset at, {required Color color, required double size, bool bold = false, Color? background}) {
    final painter = TextPainter(text: TextSpan(text: value, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)), textDirection: TextDirection.ltr)..layout();
    if (background != null) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(at.dx-4,at.dy-3,painter.width+8,painter.height+6), const Radius.circular(5)), Paint()..color = background);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant MissionMapPainter oldDelegate) => oldDelegate.state != state;
}
