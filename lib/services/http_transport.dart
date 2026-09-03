import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/vehicle_state.dart';
import 'vehicle_transport.dart';

class HttpTransport implements VehicleTransport {
  HttpTransport({required this.baseUrl, this.token = ''});
  final String baseUrl;
  final String token;
  final _states = StreamController<VehicleState>.broadcast();
  Timer? _timer;

  @override
  ConnectionKind get kind => ConnectionKind.network;
  @override
  Stream<VehicleState> get states => _states.stream;
  Map<String, String> get _headers => {'content-type': 'application/json', if (token.isNotEmpty) 'authorization': 'Bearer $token'};
  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');

  @override
  Future<void> connect() async {
    await _poll();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final response = await http.get(_uri('/api/state'), headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) throw TransportException('服务器返回 ${response.statusCode}');
      _states.add(VehicleState.fromJson(jsonDecode(response.body) as Map<String, dynamic>, kind));
    } catch (error) {
      _states.add(VehicleState.initial().copyWith(mode: VehicleMode.offline, connection: kind, message: '网络连接失败：$error'));
      rethrow;
    }
  }

  @override
  Future<void> sendTask(int taskId, {bool safetyConfirmed = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = taskId == 7 ? '/api/emergency-reset' : '/api/tasks';
    final body = <String, dynamic>{
      'command_id': 'app-$now-${taskId.toString().padLeft(2, '0')}',
      'task_id': taskId, 'timestamp_ms': now, 'valid_for_ms': 10000,
      if (taskId == 7) 'safety_confirmed': safetyConfirmed,
    };
    final response = await http.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) throw TransportException('任务下发失败：${response.statusCode} ${response.body}');
    await _poll();
  }

  @override
  Future<void> disconnect() async { _timer?.cancel(); _timer = null; }
  @override
  Future<void> dispose() async { await disconnect(); await _states.close(); }
}
