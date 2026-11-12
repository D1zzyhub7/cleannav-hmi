import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/static_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hil_snapshot.dart';
import '../models/occupancy_map.dart';
import '../models/task_definition.dart';
import '../services/http_transport.dart';
import '../services/vehicle_transport.dart';

class AppController extends ChangeNotifier {
  AppController({http.Client? client}) : _client = client;
  final http.Client? _client;
  SharedPreferences? _preferences;
  StreamSubscription<TaskSubmission>? _taskSubscription;
  bool _disposed = false;
  bool _connecting = false;
  bool _foreground = true;
  StaticMapData? staticMap;
  final mapPose = ValueNotifier<MapRobotPose?>(null);
  final _poseClock = Stopwatch()..start();
  int _lastPoseMs = -2000;
  String token = '';
  String registryJson = '';
  TargetRegistry? registry;
  String? selectedRegionId;
  String? selectedChargerId;
  List<TaskSubmission> get submissions =>
      _transport?.requests.values.toList().reversed.toList() ?? [];
  HilSnapshot snapshot = HilSnapshot.unconfigured();
  OccupancyMap? map;
  HttpTransport? _transport;
  StreamSubscription<HilSnapshot>? _snapshotSubscription;
  StreamSubscription<OccupancyMap?>? _mapSubscription;
  bool busy = false;
  String? error;
  String apiBase = '';

  bool get gatewayConnected => snapshot.gatewayConnected;
  bool? get missionConnected => snapshot.missionConnected;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _preferences = prefs;
    if (_disposed) return;
    final display = jsonDecode(
      await rootBundle.loadString('assets/map_display_metadata.json'),
    ) as Map<String, dynamic>;
    if (_disposed) return;
    staticMap = StaticMapData.fromJson(
      jsonDecode(await rootBundle.loadString('assets/map.json'))
          as Map<String, dynamic>,
      displayScale: (display['displayScale'] as num).toDouble(),
    );
    if (_disposed) return;
    apiBase = prefs.getString('api_base') ?? '';
    token = prefs.getString('gateway_token') ?? '';
    registryJson = prefs.getString('target_registry_json') ??
        await rootBundle.loadString('assets/app_targets.json');
    if (_disposed) return;
    if (registryJson.isNotEmpty) {
      try {
        _readRegistry(registryJson);
      } catch (_) {
        error = '已保存的目标配置无效，请重新导入';
      }
    }
    notifyListeners();
    if (apiBase.isNotEmpty) {
      await testConnection(apiBase, save: false);
    }
  }

  Future<void> testConnection(String url,
      {bool save = true, String? accessToken}) async {
    if (_disposed || _connecting) return;
    _connecting = true;
    try {
      if (accessToken != null) token = accessToken.trim();
      final parsed = Uri.tryParse(url.trim());
      final normalized =
          (parsed?.toString() ?? url.trim()).replaceAll(RegExp(r'/+$'), '');
      final valid = normalized.isNotEmpty &&
          parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https') &&
          parsed.host.isNotEmpty &&
          !parsed.hasQuery &&
          !parsed.hasFragment &&
          parsed.userInfo.isEmpty;
      if (!valid) {
        await _closeTransport();
        apiBase = normalized;
        error = normalized.isEmpty ? null : '请输入有效的 Gateway 地址';
        snapshot = normalized.isEmpty
            ? HilSnapshot.unconfigured()
            : HilSnapshot.disconnected(error!);
        if (save && normalized.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('api_base');
        }
        notifyListeners();
        return;
      }

      apiBase = normalized;
      if (save) {
        final prefs = await SharedPreferences.getInstance();
        _preferences = prefs;
        await prefs.setString('api_base', apiBase);
        if (token.isNotEmpty) {
          await prefs.setString('gateway_token', token);
        }
      }
      await _activate(HttpTransport(
          baseUrl: apiBase,
          token: token,
          client: _client,
          loadReceipts: () async {
            final prefs = _preferences;
            if (prefs == null) return [];
            final value = jsonDecode(
                prefs.getString('task_receipts:$normalized') ?? '[]');
            if (value is! List<dynamic>) {
              throw const FormatException('任务回执必须为列表');
            }
            return value;
          },
          saveReceipts: (receipts) async {
            final prefs = _preferences;
            if (prefs == null) {
              if (receipts.isNotEmpty) {
                throw const TransportException("请先初始化 APP 配置再提交任务");
              }
              return;
            }
            if (!await prefs.setString(
                'task_receipts:$normalized', jsonEncode(receipts))) {
              throw const TransportException('任务回执无法持久保存；请勿重复提交');
            }
          }));
    } finally {
      _connecting = false;
    }
  }

  Future<void> _closeTransport() async {
    await _taskSubscription?.cancel();
    await _snapshotSubscription?.cancel();
    await _mapSubscription?.cancel();
    await _transport?.dispose();
    _snapshotSubscription = null;
    _mapSubscription = null;
    _transport = null;
    map = null;
    if (!_disposed) mapPose.value = null;
  }

  Future<void> _activate(HttpTransport next) async {
    if (_disposed) {
      await next.dispose();
      return;
    }
    busy = true;
    error = null;
    snapshot = HilSnapshot.disconnected('正在连接 Gateway…');
    map = null;
    notifyListeners();
    try {
      await _closeTransport();
      if (_disposed) {
        await next.dispose();
        return;
      }
      _transport = next;
      _snapshotSubscription = next.snapshots.listen((incoming) {
        if (_disposed || !_foreground) return;
        snapshot = incoming;
        if (incoming.pose == null ||
            _poseClock.elapsedMilliseconds - _lastPoseMs >= 2000) {
          mapPose.value = incoming.pose;
          _lastPoseMs = _poseClock.elapsedMilliseconds;
        }
        error = null;
        notifyListeners();
      });
      _mapSubscription = next.maps.listen((incoming) {
        map = incoming;
        notifyListeners();
      });
      _taskSubscription = next.taskUpdates.listen((_) => notifyListeners());
      if (!_foreground) await next.setForeground(false);
      await next.connect();
    } on Exception catch (exception) {
      error = exception.toString();
      snapshot = HilSnapshot.disconnected(error!);
      map = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sendTask(int taskId, {bool userConfirmed = false}) async {
    final ordinary = taskId != 4 && taskId != 6;
    if (busy && ordinary) throw const TransportException('请求处理中，请稍候');
    final transport = _transport;
    if (transport == null ||
        (!gatewayConnected && taskId != 4 && taskId != 6)) {
      throw const TransportException('Gateway 尚未连接');
    }
    if (ordinary) busy = true;
    error = null;
    notifyListeners();
    try {
      if (taskId == 41 || taskId == 43) {
        if (!snapshot.safetyFresh ||
            snapshot.emergencyStop != false ||
            snapshot.blockAll == true) {
          throw const TransportException('Safety 未确认安全或急停锁存，不能提交导航任务');
        }
        final targets = taskId == 41 ? registry?.regions : registry?.chargers;
        final id = taskId == 41 ? selectedRegionId : selectedChargerId;
        if (targets == null || !targets.any((target) => target.id == id)) {
          throw TransportException(taskId == 43 ? '尚未配置充电点' : '请选择已注册 Region');
        }
        final identity = snapshot.mapIdentity;
        if (identity == null || !registry!.map.matches(identity)) {
          throw const TransportException('目标清单与当前车端地图身份不一致，请更新管理员配置');
        }
      }
      await transport.sendTask(taskId,
          userConfirmed: userConfirmed,
          regionId: selectedRegionId,
          chargerId: selectedChargerId);
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      if (ordinary) busy = false;
      notifyListeners();
    }
  }

  void _readRegistry(String text) {
    registry =
        TargetRegistry.fromJson(jsonDecode(text) as Map<String, dynamic>);
    selectedRegionId =
        registry!.regions.isEmpty ? null : registry!.regions.first.id;
    selectedChargerId =
        registry!.chargers.isEmpty ? null : registry!.chargers.first.id;
  }

  Future<void> importTargets(String text) async {
    if (_disposed) return;
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('目标配置必须为 JSON 对象');
    }
    TargetRegistry.fromJson(
        value); // Validate completely before writing or replacing current state.
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('target_registry_json', text)) {
      throw const FormatException('无法保存目标配置，原配置保留');
    }
    if (_disposed) return;
    _preferences = prefs;
    _readRegistry(text);
    registryJson = text;
    notifyListeners();
  }

  void selectRegion(String? id) {
    selectedRegionId = id;
    notifyListeners();
  }

  void selectCharger(String? id) {
    selectedChargerId = id;
    notifyListeners();
  }

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    snapshot = HilSnapshot.disconnected('状态待刷新 / UNKNOWN');
    if (!_disposed) mapPose.value = null;
    notifyListeners();
    await _transport?.setForeground(foreground);
  }

  Future<void> emergencyReset() => sendTask(7, userConfirmed: true);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    mapPose.dispose();
    _taskSubscription?.cancel();
    _snapshotSubscription?.cancel();
    _mapSubscription?.cancel();
    _transport?.dispose();
    super.dispose();
  }
}
