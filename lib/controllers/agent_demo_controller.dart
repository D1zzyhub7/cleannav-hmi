import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/agent_plan.dart';

class _AgentApiException implements Exception {
  const _AgentApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

/// Simulation-only client. Never sends anything to the vehicle /api/tasks.
class AgentDemoController extends ChangeNotifier {
  AgentDemoController(
      {http.Client? client,
      this.pollInterval = const Duration(milliseconds: 400)})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration pollInterval;
  AgentPlan? plan;
  String? error;
  String? trackingError;
  bool submitting = false;
  bool stopping = false;
  bool trackingUnavailable = false;
  String _baseUrl = '';
  Map<String, dynamic>? _pendingInput;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  bool _active = true;
  int _requestSequence = 0;
  int _generation = 0;

  bool get canRetry => _pendingInput != null && !submitting;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _validateBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的模拟服务地址');
    }
    return value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> _request(String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await (body == null
            ? _client.get(uri)
            : _client.post(uri,
                headers: {'content-type': 'application/json'},
                body: jsonEncode(body)))
        .timeout(Duration(seconds: body == null ? 5 : 35));
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _AgentApiException(
          decoded['error']?.toString() ?? '服务返回 ${response.statusCode}',
          response.statusCode);
    }
    return decoded;
  }

  /// Speech integration passes final ASR text, source='voice', and inputId.
  Future<void> submitInput(
      {required String baseUrl,
      required String text,
      String source = 'text',
      String? inputId}) async {
    if (submitting || stopping || _disposed) return;
    try {
      final normalized = _validateBase(baseUrl);
      if (text.trim().isEmpty) throw const FormatException('请输入任务文字');
      if (_pendingInput != null) {
        throw const FormatException('上次提交结果未知，请先点击“重试原请求”');
      }
      if (plan?.running == true && normalized != _baseUrl) {
        throw const FormatException('请先停止当前模拟，再切换服务地址');
      }
      _baseUrl = normalized;
      _pendingInput = {
        'text': text.trim(),
        'source': source,
        'input_id': inputId ??
            'app-${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}',
      };
      await _submitPending();
    } catch (exception) {
      error = exception.toString();
      _notify();
    }
  }

  Future<void> retryPending() async {
    if (submitting || _disposed || _pendingInput == null) return;
    await _submitPending();
  }

  Future<void> _submitPending() async {
    submitting = true;
    error = null;
    _notify();
    var deliveryStarted = false;
    try {
      if (!_pendingInput!.containsKey('service_id')) {
        final info = await _request('/api/agent/info');
        if (_disposed) return;
        if (info['execution_mode'] != 'simulation' ||
            info['service_id'] is! String) {
          throw const FormatException('请连接独立的 Agent 模拟服务（端口 18083）');
        }
        _pendingInput!['service_id'] = info['service_id'];
      }
      deliveryStarted = true;
      final json = await _request('/api/agent/plans', body: _pendingInput!);
      final incoming = AgentPlan.fromJson(json);
      if (_disposed) return;
      plan = incoming;
      _pendingInput = null;
      trackingUnavailable = false;
      trackingError = null;
      ++_generation;
      _timer?.cancel();
      _timer = incoming.running && _active
          ? Timer.periodic(pollInterval, (_) => unawaited(refresh()))
          : null;
    } catch (exception) {
      if (_disposed) return;
      // A received 4xx is a definite rejection. On transport/5xx errors,
      // preserve the input_id so retry cannot start a second plan.
      if (!deliveryStarted) {
        _pendingInput = null;
        error = '连接模拟服务失败，尚未提交任务：$exception';
      } else if (exception is _AgentApiException &&
          exception.statusCode >= 400 &&
          exception.statusCode < 500) {
        _pendingInput = null;
        error = exception.message;
      } else {
        error = '提交结果未知，请重试原请求核对；不会自动重新执行。$exception';
      }
    } finally {
      submitting = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    final current = plan;
    if (_disposed || !_active || _polling || current == null) return;
    final generation = _generation;
    _polling = true;
    try {
      final incoming =
          AgentPlan.fromJson(await _request('/api/agent/plans/${current.id}'));
      if (_disposed || generation != _generation) return;
      plan = incoming;
      trackingUnavailable = false;
      trackingError = null;
      if (!incoming.running) _timer?.cancel();
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      trackingUnavailable = true;
      trackingError = '状态暂不可用，上次状态不代表当前结果：$exception';
      if (exception is _AgentApiException && exception.statusCode == 404) {
        _timer?.cancel();
      }
    } finally {
      _polling = false;
      _notify();
    }
  }

  Future<void> stop() async {
    final current = plan;
    if (current == null || stopping || submitting || _disposed) return;
    stopping = true;
    error = null;
    _notify();
    final generation = ++_generation;
    try {
      final incoming = AgentPlan.fromJson(
          await _request('/api/agent/plans/${current.id}/stop', body: {}));
      if (_disposed || generation != _generation) return;
      plan = incoming;
      trackingUnavailable = false;
      trackingError = null;
      if (!incoming.running) _timer?.cancel();
    } catch (exception) {
      error = '停止结果尚未确认：$exception';
    } finally {
      stopping = false;
      _notify();
    }
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _timer?.cancel();
    _timer = null;
    if (active && plan?.running == true) {
      trackingUnavailable = true;
      unawaited(refresh());
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
