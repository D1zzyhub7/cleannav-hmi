import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE4ECEA)),
      boxShadow: const [BoxShadow(color: Color(0x0B17313B), blurRadius: 24, offset: Offset(0, 9))],
    ),
    child: child,
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
      Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.icon, required this.label, required this.value, required this.color, this.caption});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? caption;
  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.all(15),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 21)),
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 21, fontWeight: FontWeight.w800)),
      if (caption != null) ...[const SizedBox(height: 3), Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9AA8AC), fontSize: 10))],
    ]),
  );
}
