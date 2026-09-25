import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/hil_snapshot.dart';
import '../models/occupancy_map.dart';
import 'vehicle_transport.dart';

Map<String, dynamic> buildHttpTaskPayload({
  required int taskId,
  required String commandId,
  required int timestampMs,
  bool userConfirmed = false,
  int validForMs = 60000,
}) => {
  'command_id': commandId,
  'task_id': taskId,
  'timestamp_ms': timestampMs,
  'valid_for_ms': validForMs,
  'user_confirmed': userConfirmed,
};

class HttpTransport implements VehicleTransport {
  HttpTransport({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final _snapshots = StreamController<HilSnapshot>.broadcast();
  final _maps = StreamController<OccupancyMap?>.broadcast();
  Timer? _timer;
  bool _statePollActive = false;
  bool _mapPollActive = false;
  int _commandSequence = 0;

  @override
  Stream<HilSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<OccupancyMap?> get maps => _maps.stream;
  Map<String, String> get _headers => {'content-type': 'application/json'};
  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');

  @override
  Future<void> connect() async {
    await _pollState(propagateError: true);
    await _pollMap();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollState());
      unawaited(_pollMap());
    });
  }

  Future<void> _pollState({bool propagateError = false}) async {
    if (_statePollActive) return;
    _statePollActive = true;
    try {
      final response = await _client.get(_uri('/api/state'), headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw TransportException('服务器返回 ${response.statusCode}');
      if (!_snapshots.isClosed) {
        _snapshots.add(HilSnapshot.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
          gatewayConnected: true,
        ));
      }
    } catch (error) {
      if (!_snapshots.isClosed) {
        _snapshots.add(HilSnapshot.disconnected('Gateway 连接失败：$error'));
      }
      if (propagateError) rethrow;
    } finally {
      _statePollActive = false;
    }
  }

  Future<void> _pollMap() async {
    if (_mapPollActive) return;
    _mapPollActive = true;
    try {
      final response = await _client
          .get(_uri('/api/map'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 503) {
        if (!_maps.isClosed) _maps.add(null);
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TransportException('地图服务返回 ${response.statusCode}');
      }
      if (!_maps.isClosed) {
        _maps.add(OccupancyMap.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        ));
      }
    } catch (_) {
      // Map is an enhancement: it must never disconnect task/state control.
      if (!_maps.isClosed) _maps.add(null);
    } finally {
      _mapPollActive = false;
    }
  }

  @override
  Future<void> sendTask(int taskId, {bool userConfirmed = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = taskId == 7 ? '/api/emergency-reset' : '/api/tasks';
    final sequence = ++_commandSequence;
    final body = buildHttpTaskPayload(
      taskId: taskId,
      commandId: 'app-${DateTime.now().microsecondsSinceEpoch}-$sequence-${taskId.toString().padLeft(2, '0')}',
      timestampMs: now,
      userConfirmed: userConfirmed,
    );
    final response = await _client.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) throw TransportException('任务下发失败：${response.statusCode} ${response.body}');
    await _pollState();
  }

  @override
  Future<void> disconnect() async { _timer?.cancel(); _timer = null; }
  @override
  Future<void> dispose() async {
    await disconnect();
    if (_ownsClient) _client.close();
    await _snapshots.close();
    await _maps.close();
  }
}
