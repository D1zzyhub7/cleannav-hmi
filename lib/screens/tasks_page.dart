import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/task_definition.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          const Text(
            '比赛任务',
            style: TextStyle(color: AppColors.ink, fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            '当前比赛版仅保留 Task 30 上层任务入口',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _taskCard(context),
          if (controller.snapshot.emergencyStop == true) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF2B5BE)),
              ),
              child: const Text(
                '车辆当前处于急停状态，请先在总览页确认现场安全并解除。',
                style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      );

  Widget _taskCard(BuildContext context) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.eco_rounded, color: AppColors.greenDark),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('清扫最近落叶', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('Task 30 · CLEAN_NEAREST_LEAF', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    ],
                  ),
                ),
                const StatusPill(text: '比赛任务', color: AppColors.greenDark),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '自动寻找并清扫最近可用落叶目标',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.busy || !controller.gatewayConnected
                    ? null
                    : () => _execute(context, competitionTask),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(controller.gatewayConnected ? '开始清扫' : 'Gateway 未连接'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppColors.greenDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _execute(BuildContext context, TaskDefinition task) async {
    try {
      await controller.sendTask(task.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task 30 已下发至 Gateway')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString()), backgroundColor: AppColors.red),
        );
      }
    }
  }
}
