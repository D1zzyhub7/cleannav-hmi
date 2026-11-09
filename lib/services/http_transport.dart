import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/hil_snapshot.dart';
import '../models/occupancy_map.dart';
import '../models/task_definition.dart';
import 'vehicle_transport.dart';

Map<String, dynamic> buildHttpTaskPayload(
    {required int taskId,
    required String commandId,
    bool userConfirmed = false,
    int validForMs = 10000,
    String? sequenceId,
    String? regionId,
    String? chargerId,
    MapIdentity? map}) {
  final body = <String, dynamic>{
    'api_version': '1.0',
    'command_id': commandId,
    'valid_for_ms': validForMs.clamp(100, 30000),
    'user_confirmed': userConfirmed
  };
  if (taskId == 41 || taskId == 43) {
    final target = taskId == 41 ? regionId : chargerId;
    if (map == null || sequenceId == null || target == null || target.isEmpty) {
      throw const TransportException('空间任务需要地图身份、序列ID和已注册目标');
    }
    body.addAll({
      'task_id': taskId,
      'sequence_id': sequenceId,
      'map': map.toJson(),
      'parameters': {taskId == 41 ? 'region_id' : 'charger_id': target}
    });
  } else if (!{4, 6, 7}.contains(taskId)) {
    throw const TransportException('当前导航版本未开放此任务');
  }
  if (taskId == 7 && !userConfirmed) {
    throw const TransportException('急停复位需要明确确认');
  }
  return body;
}

/// A receipt and its observed state, not an APP execution queue.
class TaskSubmission {
  TaskSubmission(this.taskId, this.commandId, this.sequenceId, this.statusUrl,
      this.request);
  final int taskId;
  final String commandId;
  String? sequenceId;
  String statusUrl;
  final Map<String, dynamic> request;
  Map<String, dynamic> response = const {};
  String state = 'SUBMITTING';
  String message = '正在提交';
  int? reasonCode;
  bool outcomeUnknown = false;
  bool trackingUnavailable = false;
  int? completedSteps;
  int? stepCount;
  bool get terminal => {
        'SUCCEEDED',
        'FAILED',
        'REJECTED',
        'CANCELED',
        'EMERGENCY_STOPPED'
      }.contains(state);
}

class HttpTransport implements VehicleTransport {
  HttpTransport(
      {required this.baseUrl,
      this.token = '',
      http.Client? client,
      this.requestTimeout = const Duration(seconds: 5),
      this.pollInterval = const Duration(seconds: 1),
      this.saveReceipts,
      this.loadReceipts})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final Future<void> Function(List<Map<String, dynamic>>)? saveReceipts;
  final Future<List<dynamic>> Function()? loadReceipts;
  DateTime? _lastState;
  bool _paused = false;
  bool _receiptsLoaded = false;
  int _generation = 0;
  String _safe(Object? value) {
    final text = value.toString();
    return token.trim().isEmpty
        ? text
        : text.replaceAll(token.trim(), '[REDACTED]');
  }

  Future<void> _save() async {
    final completed = requests.values.where((r) => r.terminal).toList();
    for (final receipt
        in completed.take(completed.length > 20 ? completed.length - 20 : 0)) {
      requests.remove(receipt.commandId);
    }
    final active = requests.values.where((r) => !r.terminal).toList();
    await saveReceipts?.call(active
        .map((r) => {
              'task_id': r.taskId,
              'command_id': r.commandId,
              'sequence_id': r.sequenceId,
              'status_url': r.statusUrl,
            })
        .toList());
  }

  final String baseUrl;
  final String token;
  final Duration requestTimeout;
  final Duration pollInterval;
  final http.Client _client;
  final bool _ownsClient;
  final _snapshots = StreamController<HilSnapshot>.broadcast();
  final _maps = StreamController<OccupancyMap?>.broadcast();
  final _updates = StreamController<TaskSubmission>.broadcast();
  final Map<String, TaskSubmission> requests = {};
  MapIdentity? mapIdentity;
  Timer? _timer;
  bool _statePollActive = false, _trackingActive = false;
  bool _disposed = false;
  int _commandSequence = 0;
  @override
  Stream<HilSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<OccupancyMap?> get maps => _maps.stream;
  Stream<TaskSubmission> get taskUpdates => _updates.stream;
  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}'
      };
  Uri _uri(String path) {
    final relative = Uri.parse(path);
    if (relative.hasScheme ||
        relative.hasAuthority ||
        !path.startsWith('/api/v1/') ||
        relative.hasQuery ||
        relative.hasFragment ||
        relative.pathSegments.any((s) => s == '..' || s == '.')) {
      throw const TransportException('无效的 V1 状态查询地址');
    }
    return Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Map<String, dynamic> _json(http.Response response) {
    Object? redact(Object? value) {
      if (value is String) return _safe(value);
      if (value is List) return value.map(redact).toList();
      if (value is Map<String, dynamic>) {
        return value.map((k, v) => MapEntry(k, redact(v)));
      }
      return value;
    }

    final value = redact(jsonDecode(utf8.decode(response.bodyBytes)));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('响应不是 JSON 对象');
    }
    return value;
  }

  String _error(http.Response response, Map<String, dynamic> body) {
    final message = body['message'] ?? body['error'] ?? '请求失败';
    final code = body['reason_code'] ?? body['code'];
    return _safe(
        'HTTP ${response.statusCode}: $message${code == null ? '' : ' ($code)'}');
  }

  void _notify(TaskSubmission request) {
    if (!_updates.isClosed) _updates.add(request);
  }

  @override
  Future<void> connect() async {
    for (final value in await loadReceipts?.call() ?? []) {
      if (value is! Map ||
          value['command_id'] is! String ||
          value['status_url'] is! String ||
          value['task_id'] is! int ||
          (value['sequence_id'] != null && value['sequence_id'] is! String)) {
        throw const FormatException('已保存回执损坏，不能安全恢复');
      }
      _uri(value['status_url'] as String);
      final receipt = TaskSubmission(
          value['task_id'] as int,
          value['command_id'] as String,
          value['sequence_id'] as String?,
          value['status_url'] as String, const {});
      receipt.state = 'UNKNOWN';
      receipt.outcomeUnknown = true;
      receipt.message = '恢复原回执，仅查询原 status_url，不重新提交';
      requests[receipt.commandId] = receipt;
    }
    _receiptsLoaded = true;
    if (_disposed || _paused) return;
    _startTimer();
    await _pollState(propagateError: true);
    await pollSubmissions();
    if (_disposed) return;
  }

  void _startTimer() {
    _timer ??= Timer.periodic(pollInterval, (_) {
      if (_lastState == null ||
          DateTime.now().difference(_lastState!) >= requestTimeout) {
        mapIdentity = null;
        if (!_snapshots.isClosed) {
          _snapshots.add(HilSnapshot.disconnected('状态已过期 / UNKNOWN'));
        }
      }
      unawaited(_pollState());
      unawaited(pollSubmissions());
    });
  }

  Future<void> _pollState({bool propagateError = false}) async {
    if (_statePollActive || _disposed || _paused) return;
    final generation = _generation;
    _statePollActive = true;
    try {
      final response = await _client
          .get(_uri('/api/v1/state'), headers: _headers)
          .timeout(requestTimeout);
      final body = _json(response);
      if (response.statusCode != 200) {
        throw TransportException(_error(response, body));
      }
      final incoming = HilSnapshot.fromJson(body, gatewayConnected: true);
      if (_disposed || _paused || generation != _generation) return;
      _lastState = DateTime.now();
      mapIdentity = incoming.mapIdentity;
      if (!_snapshots.isClosed) _snapshots.add(incoming);
    } catch (error) {
      if (_disposed || _paused || generation != _generation) return;
      mapIdentity = null;
      if (!_snapshots.isClosed) {
        _snapshots.add(HilSnapshot.disconnected(_safe('Gateway 连接失败：$error')));
      }
      if (propagateError) {
        if (_safe(error) != error.toString()) {
          throw TransportException(_safe(error));
        }
        rethrow;
      }
    } finally {
      _statePollActive = false;
    }
  }

  @override
  Future<void> sendTask(int taskId,
      {bool userConfirmed = false,
      String? regionId,
      String? chargerId,
      int validForMs = 10000}) async {
    if (_disposed) throw const TransportException('Gateway 连接已关闭');
    if ((taskId == 41 || taskId == 43) && !_receiptsLoaded) {
      throw const TransportException('回执尚未恢复，不能提交新导航任务');
    }
    if ((taskId == 41 || taskId == 43) &&
        requests.values
            .any((r) => (r.taskId == 41 || r.taskId == 43) && !r.terminal)) {
      throw const TransportException('已有导航请求运行中或结果未知，请先核对原任务');
    }
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}-${++_commandSequence}';
    final command = 'app-$suffix-$taskId';
    final sequence = taskId == 41 || taskId == 43 ? 'app-seq-$suffix' : null;
    final path = switch (taskId) {
      4 => '/api/v1/stop',
      6 => '/api/v1/estop',
      7 => '/api/v1/estop/reset',
      _ => '/api/v1/tasks'
    };
    final body = buildHttpTaskPayload(
        taskId: taskId,
        commandId: command,
        sequenceId: sequence,
        map: mapIdentity,
        regionId: regionId,
        chargerId: chargerId,
        userConfirmed: userConfirmed,
        validForMs: validForMs);
    final request = TaskSubmission(
        taskId,
        command,
        sequence,
        sequence == null
            ? '/api/v1/commands/$command'
            : '/api/v1/sequences/$sequence',
        body);
    requests[command] = request;
    _notify(request);
    try {
      // Persist intent BEFORE POST: a process death at any later point must only GET.
      // STOP/ESTOP delivery must not wait for a storage operation.
      if (taskId != 4 && taskId != 6) await _save();
      final response = await _client
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(requestTimeout);
      Map<String, dynamic> data;
      try {
        data = _json(response);
      } on FormatException {
        data = const {};
      }
      request.response = data; // _json has already redacted secret values.
      if (data['command_id'] != null && data['command_id'] != command) {
        throw const FormatException('回执 command_id 不匹配');
      }
      if (data['sequence_id'] != null && data['sequence_id'] != sequence) {
        throw const FormatException('回执 sequence_id 不匹配');
      }
      if (data['status_url'] is String) {
        _uri(data['status_url'] as String);
        request.statusUrl = data['status_url'] as String;
      }
      if (data['sequence_id'] is String) {
        request.sequenceId = data['sequence_id'] as String;
      }
      request.reasonCode = (data['reason_code'] as num?)?.toInt();
      request.message =
          _safe(data['message'] ?? data['error'] ?? '请求已送达，等待执行结果');
      if (response.statusCode != 202 ||
          (data['accepted'] != true && data['accepted_for_delivery'] != true)) {
        request.outcomeUnknown = data['outcome_unknown'] == true ||
            response.statusCode == 202 ||
            (response.statusCode >= 500 && response.statusCode != 503);
        request.state = request.outcomeUnknown ? 'UNKNOWN' : 'REJECTED';
        request.message = _error(response, data);
        throw TransportException(request.message);
      }
      request.state = 'ACCEPTED'; // Delivery/admission only, never SUCCEEDED.
    } catch (error) {
      if (request.state == 'SUBMITTING') {
        request.state = 'UNKNOWN';
        request.outcomeUnknown = true;
        request.message = _safe('提交结果未知，请核对原请求状态；不会重新下单：$error');
      }
      if (_safe(error) != error.toString()) {
        throw TransportException(_safe(error));
      }
      rethrow;
    } finally {
      try {
        await _save();
      } catch (_) {
        request.message = '回执未能保存，请记录原请求身份并核对结果；${request.message}';
        if (taskId != 4 && taskId != 6) rethrow;
      } finally {
        _notify(request);
      }
    }
  }

  Future<void> pollSubmissions() async {
    if (_trackingActive || _disposed || _paused) return;
    _trackingActive = true;
    final generation = _generation;
    try {
      for (final request in requests.values.toList()) {
        if (request.terminal || request.state == 'SUBMITTING') continue;
        try {
          final response = await _client
              .get(_uri(request.statusUrl), headers: _headers)
              .timeout(requestTimeout);
          if (_disposed || _paused || generation != _generation) return;
          final body = _json(response);
          if (response.statusCode != 200) {
            throw TransportException(_error(response, body));
          }
          final status =
              body[request.sequenceId == null ? 'command' : 'sequence'];
          if (status is! Map<String, dynamic>) {
            throw const FormatException('缺少任务状态');
          }
          final id =
              status[request.sequenceId == null ? 'command_id' : 'sequence_id'];
          if (id != (request.sequenceId ?? request.commandId)) {
            throw const FormatException('状态身份不匹配');
          }
          request.state =
              (status['state'] as String? ?? 'UNKNOWN').toUpperCase();
          request.message = _safe(status['message'] ?? '');
          if (request.message.isEmpty) {
            request.message = request.taskId == 7 && request.state == 'FAILED'
                ? '急停复位失败（车端未提供详细原因），请核对 Safety 状态'
                : request.state;
          }
          request.reasonCode = (status['reason_code'] as num?)?.toInt();
          request.completedSteps = (status['completed_steps'] as num?)?.toInt();
          request.stepCount = (status['step_count'] as num?)?.toInt();
          request.outcomeUnknown = request.state == 'UNKNOWN';
          request.trackingUnavailable = false;
        } catch (error) {
          if (_disposed || _paused || generation != _generation) return;
          request.trackingUnavailable = true;
          request.message = _safe('当前结果暂不可查询，上次状态不代表当前结果：$error');
        }
        try {
          await _save();
        } catch (_) {
          request.trackingUnavailable = true;
          request.message = '回执保存失败，请保留原请求身份并核对状态；不会重新提交';
        }
        _notify(request);
      }
    } finally {
      _trackingActive = false;
    }
  }

  Future<void> setForeground(bool foreground) async {
    _paused = !foreground;
    ++_generation;
    _lastState = null;
    mapIdentity = null;
    if (!_snapshots.isClosed) {
      _snapshots.add(HilSnapshot.disconnected('状态待刷新 / UNKNOWN'));
    }
    if (!foreground) {
      await disconnect();
    } else if (!_disposed) {
      _startTimer();
      await _pollState();
      await pollSubmissions();
    }
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    if (_ownsClient) _client.close();
    await _snapshots.close();
    await _maps.close();
    await _updates.close();
  }
}
