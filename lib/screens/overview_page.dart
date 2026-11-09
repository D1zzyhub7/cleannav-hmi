import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/hil_snapshot.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mission_map.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage(
      {super.key, required this.controller, required this.openTasks});

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
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900),
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
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Navigation V1',
                      style: TextStyle(color: Color(0xFFB9D7D0), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (snapshot.gatewayConnected)
                Icon(
                  emergency
                      ? Icons.warning_rounded
                      : Icons.check_circle_rounded,
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
                        Text('导航静态地图',
                            style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('A7 / R9 正式地图 · 车辆位置约 2 秒更新',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              StaticMissionMap(controller: controller),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _safetyCard(context, snapshot),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: openTasks,
          icon: const Icon(Icons.eco_rounded),
          label: const Text('进入导航任务'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.greenDark,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          ),
        ),
      ],
    );
  }

  Widget _connectionCard(HilSnapshot snapshot) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('系统连接',
                style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _statusRow('Gateway', snapshot.gatewayConnected ? '已连接' : '未连接',
                snapshot.gatewayConnected),
            const SizedBox(height: 8),
            _statusRow(
              'Mission Manager',
              !snapshot.gatewayConnected
                  ? '不可用'
                  : snapshot.missionConnected == null
                      ? 'UNKNOWN'
                      : snapshot.missionConnected == true
                          ? '在线'
                          : '离线',
              snapshot.missionConnected,
            ),
          ],
        ),
      );

  Widget _vehicleCard(HilSnapshot snapshot) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('车辆状态',
                style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _stateTile(
                    '定位',
                    _boolText(snapshot.localizationOk, '正常', '未就绪'),
                    snapshot.localizationOk),
                _stateTile(
                    '自动驾驶',
                    _boolText(snapshot.autonomousEnabled, '已启用', '无任务授权'),
                    snapshot.autonomousEnabled,
                    valueColor: snapshot.autonomousEnabled == false
                        ? AppColors.ink
                        : null),
                _stateTile(
                    '急停',
                    _boolText(snapshot.emergencyStop, '已触发', '正常'),
                    snapshot.emergencyStop == null
                        ? null
                        : !snapshot.emergencyStop!),
                _stateTile(
                    '系统状态',
                    _systemLabel(snapshot),
                    !snapshot.gatewayConnected || !snapshot.safetyFresh
                        ? null
                        : snapshot.emergencyStop == true
                            ? false
                            : snapshot.systemState == 'SYSTEM_READY'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
                '${snapshot.systemState} · ${snapshot.systemMessage} · Safety ${snapshot.safetyFresh ? '新鲜' : '未知'} · block_all=${snapshot.blockAll ?? '未知'} · Lease=${snapshot.leaseOwner ?? '未知'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (snapshot.speedMps != null) ...[
              const SizedBox(height: 5),
              Text('速度 ${formatOverviewSpeedMps(snapshot.speedMps!)} m/s',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
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
            Text('当前任务',
                style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            SizedBox(height: 10),
            Text('暂无执行任务',
                style: TextStyle(color: AppColors.muted, fontSize: 14)),
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
              const Expanded(
                  child: Text('当前任务',
                      style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800))),
              StatusPill(
                  text: task.taskState, color: taskStateColor(task.taskState)),
            ],
          ),
          const SizedBox(height: 10),
          Text(task.taskLabel,
              style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
              'Task ${task.taskId} · ${task.taskProgress < 0 ? '进度未知' : '${(task.taskProgress * 100).round()}%'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          if (task.activeTargetId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('目标：${task.activeTargetId}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
          if (task.remainingDistanceM > 0) ...[
            const SizedBox(height: 4),
            Text('剩余距离：${task.remainingDistanceM.toStringAsFixed(2)} m',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
          const SizedBox(height: 7),
          Text(task.taskMessage,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _safetyCard(BuildContext context, HilSnapshot snapshot) {
    final triggered = snapshot.emergencyStop == true;
    final available = snapshot.emergencyStop != null;
    final canAct = snapshot.gatewayConnected;
    return SectionCard(
      child: Row(
        children: [
          Icon(
              !available
                  ? Icons.help_outline_rounded
                  : triggered
                      ? Icons.lock_rounded
                      : Icons.shield_outlined,
              color: !available
                  ? AppColors.amber
                  : triggered
                      ? AppColors.red
                      : AppColors.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    !available
                        ? '急停状态不可用'
                        : triggered
                            ? '急停已触发'
                            : '安全状态正常',
                    style: TextStyle(
                        color: !available
                            ? AppColors.amber
                            : triggered
                                ? AppColors.red
                                : AppColors.ink,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                    !available
                        ? 'Safety 状态未收到或过期；可发送急停请求，但需核对结果'
                        : triggered
                            ? '确认现场安全后可解除急停'
                            : '软件急停仅通过 Gateway 请求，不替代硬件急停',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          if (triggered)
            FilledButton(
              onPressed:
                  canAct && !controller.busy ? () => _reset(context) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('确认复位'),
            )
          else
            FilledButton.icon(
              onPressed: canAct ? () => _emergency(context) : null,
              icon: const Icon(Icons.stop_circle),
              label: const Text('ESTOP'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.red,
                  minimumSize: const Size(100, 48)),
            ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, bool? ok) => Row(
        children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 13))),
          StatusPill(
              text: value,
              color: ok == true
                  ? AppColors.green
                  : ok == false
                      ? AppColors.red
                      : AppColors.amber),
        ],
      );

  Widget _stateTile(String label, String value, bool? ok, {Color? valueColor}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: valueColor ??
                        (ok == true
                            ? AppColors.greenDark
                            : ok == false
                                ? AppColors.red
                                : AppColors.amber),
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );

  String _systemLabel(HilSnapshot s) {
    if (!s.gatewayConnected) return '网关离线';
    if (s.emergencyStop == true) return '急停锁存';
    if (!s.safetyFresh) return '安全状态未知';
    if (s.blockAll == true) return '系统阻断';
    if (s.localizationOk == false) return '定位异常';
    return switch (s.systemState) {
      'SYSTEM_READY' => '系统正常',
      'SYSTEM_BLOCKED' => '系统阻断',
      'SYSTEM_EMERGENCY_STOP' => '急停锁存',
      'SYSTEM_ERROR' => '系统异常',
      _ => '状态待确认',
    };
  }

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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('立即急停')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.sendTask(6);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认现场安全'),
        content: const Text('请确认车辆周围无人、故障原因已排除。解除后车辆保持待机。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认解除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.emergencyReset();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: AppColors.red));
      }
    }
  }
}

String formatOverviewSpeedMps(double metersPerSecond) {
  final shown = metersPerSecond.toStringAsFixed(2);
  return shown == '-0.00' ? '0.00' : shown;
}
