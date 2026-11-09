import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final TextEditingController url;
  late final TextEditingController token;
  late final TextEditingController registry;
  String _lastSyncedApiBase = '';
  String _lastSyncedToken = '';
  String _lastSyncedRegistry = '';

  @override
  void initState() {
    super.initState();
    url = TextEditingController(text: widget.controller.apiBase);
    _lastSyncedApiBase = widget.controller.apiBase;
    token = TextEditingController(text: widget.controller.token);
    registry = TextEditingController(text: widget.controller.registryJson);
    _lastSyncedToken = widget.controller.token;
    _lastSyncedRegistry = widget.controller.registryJson;
  }

  @override
  void dispose() {
    url.dispose();
    token.dispose();
    registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncApiBase();
    final snapshot = widget.controller.snapshot;
    final gatewayStatus = widget.controller.apiBase.isEmpty
        ? '未配置'
        : snapshot.gatewayConnected
            ? '已连接'
            : '未连接';
    final gatewayColor = widget.controller.apiBase.isEmpty
        ? AppColors.amber
        : snapshot.gatewayConnected
            ? AppColors.green
            : AppColors.red;
    final j6Status = !snapshot.gatewayConnected
        ? '不可用'
        : snapshot.missionConnected == true
            ? '在线'
            : '离线';
    final j6Color = !snapshot.gatewayConnected
        ? AppColors.amber
        : snapshot.missionConnected == true
            ? AppColors.green
            : AppColors.red;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        const Text(
          '设备连接',
          style: TextStyle(
              color: AppColors.ink, fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        const Text(
          '连接 Gateway V1，读取车端导航与安全状态',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('网络网关',
                  style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('APP 只通过 HTTP HMI Gateway 发送上层任务',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 14),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: _decoration('API Base URL',
                    '例如：http://10.218.39.57:18082', Icons.language),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: token,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: '访问令牌',
                      helperText: '仅本次会话；重启后重新输入')),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.controller.busy
                      ? null
                      : () => widget.controller
                          .testConnection(url.text, accessToken: token.text),
                  icon: widget.controller.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_done),
                  label: const Text('保存并测试连接'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColors.greenDark,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              if (widget.controller.error != null) ...[
                const SizedBox(height: 10),
                Text(widget.controller.error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
            child:
                ExpansionTile(title: const Text('管理员目标配置（只读 JSON）'), children: [
          const Text('从实际部署 Registry 导出 JSON 或目标清单。普通用户只选择目标，不修改车端 Registry。'),
          TextField(
              controller: registry,
              minLines: 3,
              maxLines: 6,
              decoration:
                  const InputDecoration(labelText: 'Registry / 目标清单 JSON')),
          TextButton(
              onPressed: () async {
                try {
                  await widget.controller.importTargets(registry.text);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('目标配置已导入')));
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: const Text('导入只读目标清单')),
        ])),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('连接状态',
                  style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _statusRow('Gateway', gatewayStatus, gatewayColor),
              const SizedBox(height: 10),
              _statusRow('Mission', j6Status, j6Color),
              const SizedBox(height: 12),
              Text(snapshot.systemMessage,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  void _syncApiBase() {
    if (token.text == _lastSyncedToken &&
        token.text != widget.controller.token) {
      token.text = widget.controller.token;
    }
    if (registry.text == _lastSyncedRegistry &&
        registry.text != widget.controller.registryJson) {
      registry.text = widget.controller.registryJson;
    }
    _lastSyncedToken = widget.controller.token;
    _lastSyncedRegistry = widget.controller.registryJson;
    final current = widget.controller.apiBase;
    if ((url.text.isEmpty || url.text == _lastSyncedApiBase) &&
        url.text != current) {
      url.text = current;
      url.selection = TextSelection.collapsed(offset: url.text.length);
    }
    _lastSyncedApiBase = current;
  }

  Widget _statusRow(String label, String value, Color color) => Row(
        children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 13))),
          StatusPill(text: value, color: color),
        ],
      );

  InputDecoration _decoration(String label, String hint, IconData icon) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF4F8F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      );
}
