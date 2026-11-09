import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../services/http_transport.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
        const Text('导航任务',
            style: TextStyle(
                color: AppColors.ink,
                fontSize: 28,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('默认目标：SIMULATION 仿真配置。导入配置后请核对地图身份；接受不代表抵达。',
            style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        const Text('结果未知时只查询原请求，不会自动重新提交。回执丢失或损坏时，须人工核对车端任务，勿创建第二个任务。',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 16),
        SectionCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('点到点导航 · Task41',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (controller.registry?.regions.isNotEmpty == true)
            DropdownButton<String>(
                isExpanded: true,
                value: controller.selectedRegionId,
                items: controller.registry!.regions
                    .map((target) => DropdownMenuItem(
                        value: target.id, child: Text(target.name)))
                    .toList(),
                onChanged: controller.selectRegion)
          else
            const Text('尚未导入已注册 Region，请在连接页导入管理员目标配置。'),
          FilledButton.icon(
              onPressed: controller.busy ||
                      !controller.gatewayConnected ||
                      controller.selectedRegionId == null
                  ? null
                  : () => _execute(context, 41),
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('前往区域')),
        ])),
        const SizedBox(height: 14),
        SectionCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('返回充电点 · Task43',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (controller.registry?.chargers.isNotEmpty == true)
            DropdownButton<String>(
                isExpanded: true,
                value: controller.selectedChargerId,
                items: controller.registry!.chargers
                    .map((target) => DropdownMenuItem(
                        value: target.id, child: Text(target.name)))
                    .toList(),
                onChanged: controller.selectCharger)
          else
            const Text('尚未配置充电点'),
          const Text('仅导航至充电等待位，不执行自动对接或充电。',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          FilledButton.icon(
              onPressed: controller.busy ||
                      !controller.gatewayConnected ||
                      controller.selectedChargerId == null
                  ? null
                  : () => _execute(context, 43),
              icon: const Icon(Icons.ev_station_outlined),
              label: const Text('返回充电等待位')),
        ])),
        const SizedBox(height: 14),
        OutlinedButton.icon(
            onPressed:
                controller.gatewayConnected ? () => _execute(context, 4) : null,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('普通停止 · STOP（不锁存急停）')),
        if (controller.error != null)
          Text(controller.error!, style: const TextStyle(color: AppColors.red)),
        const SizedBox(height: 14),
        for (final request in controller.submissions.take(6)) _receipt(request),
      ]);

  Widget _receipt(TaskSubmission request) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'Task ${request.taskId} · ${request.outcomeUnknown || request.trackingUnavailable ? '结果未知 / 待核对' : request.state}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        StatusPill(
            text: request.trackingUnavailable ? 'UNKNOWN' : request.state,
            color: taskStateColor(
                request.trackingUnavailable ? 'UNKNOWN' : request.state)),
        Text(request.commandId, style: const TextStyle(fontSize: 10)),
        Text('Status URL: ${request.statusUrl}',
            style: const TextStyle(fontSize: 10)),
        if (request.sequenceId != null)
          Text('Sequence ${request.sequenceId}',
              style: const TextStyle(fontSize: 10)),
        if (request.stepCount != null)
          Text('已完成步骤 ${request.completedSteps ?? 0}/${request.stepCount}'),
        Text(request.message),
        if (request.reasonCode != null) Text('原因码 ${request.reasonCode}'),
      ])));

  Future<void> _execute(BuildContext context, int taskId) async {
    try {
      await controller.sendTask(taskId);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: AppColors.red));
      }
    }
  }
}
