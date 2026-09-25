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
  String _lastSyncedApiBase = '';

  @override
  void initState() {
    super.initState();
    url = TextEditingController(text: widget.controller.apiBase);
    _lastSyncedApiBase = widget.controller.apiBase;
  }

  @override
  void dispose() {
    url.dispose();
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
        : snapshot.j6Connected == true
            ? '在线'
            : '离线';
    final j6Color = !snapshot.gatewayConnected
        ? AppColors.amber
        : snapshot.j6Connected == true
            ? AppColors.green
            : AppColors.red;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        const Text(
          '设备连接',
          style: TextStyle(color: AppColors.ink, fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        const Text(
          '连接 PC / WSL HMI Gateway，查看实时比赛状态',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('网络网关', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('APP 只通过 HTTP HMI Gateway 发送上层任务', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 14),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: _decoration('API Base URL', '例如：http://10.218.39.57:18082', Icons.language),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.controller.busy ? null : () => widget.controller.testConnection(url.text),
                  icon: widget.controller.busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_done),
                  label: const Text('保存并测试连接'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColors.greenDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              if (widget.controller.error != null) ...[
                const SizedBox(height: 10),
                Text(widget.controller.error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('连接状态', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _statusRow('Gateway', gatewayStatus, gatewayColor),
              const SizedBox(height: 10),
              _statusRow('J6', j6Status, j6Color),
              const SizedBox(height: 12),
              Text(snapshot.systemMessage, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  void _syncApiBase() {
    final current = widget.controller.apiBase;
    if ((url.text.isEmpty || url.text == _lastSyncedApiBase) && url.text != current) {
      url.text = current;
      url.selection = TextSelection.collapsed(offset: url.text.length);
    }
    _lastSyncedApiBase = current;
  }

  Widget _statusRow(String label, String value, Color color) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          StatusPill(text: value, color: color),
        ],
      );

  InputDecoration _decoration(String label, String hint, IconData icon) => InputDecoration(
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
