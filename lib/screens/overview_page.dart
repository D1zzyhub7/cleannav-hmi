import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/hil_snapshot.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mission_map.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.controller, required this.openTasks});

  final AppController controller;
  final VoidCallback openTasks;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final emergency = snapshot.emergencyStop == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0C3138), Color(0xFF11624F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Center(
                  child: Text(
                    'CN',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CleanNav',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'M1 Competition APP Runtime',
                      style: TextStyle(color: Color(0xFFB9D7D0), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (snapshot.gatewayConnected)
                Icon(
                  emergency ? Icons.warning_rounded : Icons.check_circle_rounded,
                  color: emergency ? AppColors.red : AppColors.green,
                  size: 30,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _connectionCard(snapshot),
        const SizedBox(height: 14),
        _vehicleCard(snapshot),
        const SizedBox(height: 14),
        _taskCard(snapshot),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('真实 RTAB OccupancyGrid', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('来自 GET /api/map，不使用模拟路线', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  StatusPill(
                    text: controller.map == null ? '不可用' : 'MAP ${controller.map!.seq}',
                    color: controller.map == null ? AppColors.amber : AppColors.green,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MissionMap(map: controller.map),
              if (controller.map != null) ...[
                const SizedBox(height: 8),
                Text(
                  'frame: ${controller.map!.frameId} · ${controller.map!.width} × ${controller.map!.height} · ${controller.map!.resolution.toStringAsFixed(3)} m/cell',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.map!.robotPose == null
                      ? 'robot_pose: 暂不可用'
                      : 'robot_pose: x=${controller.map!.robotPose!.x.toStringAsFixed(2)} · y=${controller.map!.robotPose!.y.toStringAsFixed(2)} · yaw=${controller.map!.robotPose!.yaw.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _safetyCard(context, snapshot),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: openTasks,
          icon: const Icon(Icons.eco_rounded),
          label: const Text('进入比赛任务'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.greenDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          ),
        ),
      ],
    );
  }

  Widget _connectionCard(HilSnapshot snapshot) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('系统连接', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _statusRow('Gateway', snapshot.gatewayConnected ? '已连接' : '未连接', snapshot.gatewayConnected),
            const SizedBox(height: 8),
            _statusRow(
              'J6 控制器',
              !snapshot.gatewayConnected
                  ? '不可用'
                  : snapshot.j6Connected == true
                      ? '在线'
                      : '离线',
              snapshot.j6Connected,
            ),
          ],
        ),
      );

  Widget _vehicleCard(HilSnapshot snapshot) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('车辆状态', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _stateTile('定位', _boolText(snapshot.localizationOk, '正常', '未就绪'), snapshot.localizationOk),
                _stateTile('自动驾驶', _boolText(snapshot.autonomousEnabled, '已启用', '未启用'), snapshot.autonomousEnabled),
                _stateTile('急停', _boolText(snapshot.emergencyStop, '已触发', '正常'), snapshot.emergencyStop == null ? null : !snapshot.emergencyStop!),
                _stateTile('系统状态', snapshot.systemState, snapshot.gatewayConnected),
              ],
            ),
            const SizedBox(height: 12),
            Text(snapshot.systemMessage, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (snapshot.speedMps != null) ...[
              const SizedBox(height: 5),
              Text('速度 ${snapshot.speedMps!.toStringAsFixed(2)} m/s', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ],
        ),
      );

  Widget _taskCard(HilSnapshot snapshot) {
    final task = snapshot.task;
    if (!task.taskStatusPresent) {
      return const SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前任务', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 10),
            Text('暂无执行任务', style: TextStyle(color: AppColors.muted, fontSize: 14)),
          ],
        ),
      );
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('当前任务', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800))),
              StatusPill(text: task.taskState, color: AppColors.greenDark),
            ],
          ),
          const SizedBox(height: 10),
          Text(task.taskLabel, style: const TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text('Task ${task.taskId} · ${(task.taskProgress * 100).round()}%', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          if (task.activeTargetId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('目标：${task.activeTargetId}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
          if (task.remainingDistanceM > 0) ...[
            const SizedBox(height: 4),
            Text('剩余距离：${task.remainingDistanceM.toStringAsFixed(2)} m', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
          const SizedBox(height: 7),
          Text(task.taskMessage, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _safetyCard(BuildContext context, HilSnapshot snapshot) {
    final triggered = snapshot.emergencyStop == true;
    final available = snapshot.emergencyStop != null;
    final canAct = snapshot.gatewayConnected && !controller.busy;
    return SectionCard(
      child: Row(
        children: [
          Icon(!available ? Icons.help_outline_rounded : triggered ? Icons.lock_rounded : Icons.shield_outlined, color: !available ? AppColors.amber : triggered ? AppColors.red : AppColors.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(!available ? '急停状态不可用' : triggered ? '急停已触发' : '安全状态正常', style: TextStyle(color: !available ? AppColors.amber : triggered ? AppColors.red : AppColors.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(!available ? '请先连接 Gateway 获取安全状态' : triggered ? '确认现场安全后可解除急停' : '软件急停仅通过 Gateway 请求，不替代硬件急停', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          if (triggered)
            FilledButton(
              onPressed: canAct ? () => _reset(context) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('解除'),
            )
          else if (available)
            IconButton(
              onPressed: canAct ? () => _emergency(context) : null,
              icon: const Icon(Icons.stop_circle_outlined),
              color: AppColors.red,
              tooltip: '软件急停',
            ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, bool? ok) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          StatusPill(text: value, color: ok == true ? AppColors.green : ok == false ? AppColors.red : AppColors.amber),
        ],
      );

  Widget _stateTile(String label, String value, bool? ok) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: ok == true ? AppColors.greenDark : ok == false ? AppColors.red : AppColors.amber, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  String _boolText(bool? value, String trueText, String falseText) {
    if (value == null) return '不可用';
    return value ? trueText : falseText;
  }

  Future<void> _emergency(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('触发软件急停？'),
        content: const Text('将通过 Gateway 请求停止自主运动。网络急停不能替代车辆硬件急停。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('立即急停')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.sendTask(6);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()), backgroundColor: AppColors.red));
    }
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认现场安全'),
        content: const Text('请确认车辆周围无人、故障原因已排除。解除后车辆保持待机。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认解除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.emergencyReset();
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()), backgroundColor: AppColors.red));
    }
  }
}
