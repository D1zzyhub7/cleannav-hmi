import 'dart:convert';

import 'package:flutter/material.dart';

import '../controllers/agent_demo_controller.dart';
import '../models/agent_plan.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AgentPage extends StatefulWidget {
  const AgentPage(
      {super.key,
      this.initialGatewayUrl = '',
      this.controller,
      this.active = true});
  final bool active;
  final String initialGatewayUrl;
  final AgentDemoController? controller;

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> with WidgetsBindingObserver {
  late final AgentDemoController controller;
  late final TextEditingController server;
  final input = TextEditingController(text: '去A区巡航3轮，然后返回充电');

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? AgentDemoController();
    WidgetsBinding.instance.addObserver(this);
    controller.setActive(widget.active);
    final gateway = Uri.tryParse(widget.initialGatewayUrl);
    server = TextEditingController(
        text: gateway != null && gateway.host.isNotEmpty
            ? gateway
                .replace(port: 18083, path: '', query: '', fragment: '')
                .toString()
                .replaceAll(RegExp(r'[?#]+$'), '')
            : 'http://10.0.2.2:18083');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    server.dispose();
    input.dispose();
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.setActive(widget.active &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setActive(widget.active && state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final plan = controller.plan;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              const Text('任务助手',
                  style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('文字拆分 → 任务列表 → 顺序执行',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              const SectionCard(
                  child: Row(children: [
                Icon(Icons.science_outlined, color: AppColors.amber),
                SizedBox(width: 10),
                Expanded(
                    child: Text('独立模拟演示，不控制实车。支持 A / B 区，未接电量和真实导航。',
                        style: TextStyle(color: AppColors.ink, fontSize: 12))),
              ])),
              const SizedBox(height: 14),
              SectionCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    TextField(
                      key: const Key('agent-server'),
                      controller: server,
                      enabled: !controller.submitting &&
                          plan?.running != true &&
                          !controller.canRetry,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: '模拟服务地址',
                          helperText: '真机填写电脑 IP:18083；10.0.2.2 用于 Android 模拟器',
                          helperMaxLines: 2),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('agent-input'),
                      controller: input,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                          labelText: '你想让小车做什么？',
                          hintText: '去A区巡航3轮，然后返回充电',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('agent-submit'),
                          onPressed: controller.submitting ||
                                  controller.stopping ||
                                  controller.canRetry
                              ? null
                              : () => controller.submitInput(
                                  baseUrl: server.text, text: input.text),
                          icon: controller.submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(
                              controller.submitting ? '正在拆分任务…' : '拆分并模拟执行'),
                        )),
                    if (controller.canRetry)
                      TextButton(
                          onPressed: controller.retryPending,
                          child: const Text('重试原请求（不会重复执行）')),
                    if (controller.error != null ||
                        controller.trackingError != null) ...[
                      const SizedBox(height: 8),
                      Text((controller.error ?? controller.trackingError)!,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 12)),
                    ],
                  ])),
              if (plan != null) ...[
                const SizedBox(height: 14),
                _planCard(plan),
              ],
              const SizedBox(height: 14),
              const Text('语音接入可直接提交最终转写文字；模型解析由服务端配置。未配置模型时使用明确标注的本地规则模式。',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          );
        },
      );

  Widget _planCard(AgentPlan plan) => SectionCard(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            StatusPill(
                text: controller.trackingUnavailable
                    ? '当前结果未知'
                    : plan.statusLabel,
                color: controller.trackingUnavailable
                    ? AppColors.amber
                    : plan.state == 'FAILED'
                        ? AppColors.red
                        : AppColors.greenDark),
            StatusPill(
                text: plan.parserMode == 'llm'
                    ? plan.modelProvider == 'deepseek'
                        ? 'DeepSeek 云端解析'
                        : '大模型解析'
                    : '本地规则解析',
                color: AppColors.blue),
          ]),
          const SizedBox(height: 12),
          if (plan.parserMode == 'llm' && plan.modelName != null)
            Text('模型：${plan.modelName}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          Text(plan.text,
              style: const TextStyle(
                  color: AppColors.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (var i = 0; i < plan.steps.length; i++)
            _step(plan.steps[i], i + 1),
          if (plan.error != null)
            Text(plan.error!,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          if (plan.state == 'SUCCEEDED' &&
              plan.steps.last.action == 'return_to_charge')
            const Text('已模拟到达充电处；未模拟自动对接或开始充电。',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          if (plan.running)
            OutlinedButton.icon(
              key: const Key('agent-stop'),
              onPressed: controller.stopping || controller.submitting
                  ? null
                  : controller.stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(controller.stopping ? '正在停止…' : '停止模拟'),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('查看拆分结果 JSON', style: TextStyle(fontSize: 12)),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert({
                      'steps':
                          plan.steps.map((step) => step.toTaskJson()).toList()
                    }),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ))
            ],
          ),
        ],
      ));

  Widget _step(AgentPlanStep step, int number) {
    final (icon, color, status) = switch (step.state) {
      'RUNNING' => (Icons.play_circle_outline, AppColors.blue, '进行中'),
      'SUCCEEDED' => (Icons.check_circle_outline, AppColors.greenDark, '已完成'),
      'FAILED' => (Icons.error_outline, AppColors.red, '失败'),
      'CANCELED' => (Icons.remove_circle_outline, AppColors.muted, '未继续执行'),
      _ => (Icons.radio_button_unchecked, AppColors.muted, '等待中'),
    };
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('$number. ${step.label}',
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      step.action == 'patrol_clean'
                          ? '$status · 第 ${step.currentRound} / ${step.rounds} 轮 · 已完成 ${step.completedRounds} 轮'
                          : status,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ])),
          ],
        ));
  }
}
