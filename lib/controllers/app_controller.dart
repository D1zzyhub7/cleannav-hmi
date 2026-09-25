import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hil_snapshot.dart';
import '../models/occupancy_map.dart';
import '../services/http_transport.dart';
import '../services/vehicle_transport.dart';

class AppController extends ChangeNotifier {
  HilSnapshot snapshot = HilSnapshot.unconfigured();
  OccupancyMap? map;
  HttpTransport? _transport;
  StreamSubscription<HilSnapshot>? _snapshotSubscription;
  StreamSubscription<OccupancyMap?>? _mapSubscription;
  bool busy = false;
  String? error;
  String apiBase = '';

  bool get gatewayConnected => snapshot.gatewayConnected;
  bool? get j6Connected => snapshot.j6Connected;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    apiBase = prefs.getString('api_base') ?? '';
    notifyListeners();
    if (apiBase.isNotEmpty) {
      await testConnection(apiBase, save: false);
    }
  }

  Future<void> testConnection(String url, {bool save = true}) async {
    final normalized = url.trim();
    final parsed = Uri.tryParse(normalized);
    final valid = normalized.isNotEmpty &&
        parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty;
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
      await prefs.setString('api_base', apiBase);
    }
    await _activate(HttpTransport(baseUrl: apiBase));
  }

  Future<void> _closeTransport() async {
    await _snapshotSubscription?.cancel();
    await _mapSubscription?.cancel();
    await _transport?.dispose();
    _snapshotSubscription = null;
    _mapSubscription = null;
    _transport = null;
    map = null;
  }

  Future<void> _activate(HttpTransport next) async {
    busy = true;
    error = null;
    snapshot = HilSnapshot.disconnected('正在连接 Gateway…');
    map = null;
    notifyListeners();
    try {
      await _closeTransport();
      _transport = next;
      _snapshotSubscription = next.snapshots.listen((incoming) {
        snapshot = incoming;
        error = null;
        notifyListeners();
      });
      _mapSubscription = next.maps.listen((incoming) {
        map = incoming;
        notifyListeners();
      });
      await next.connect();
    } catch (exception) {
      error = exception.toString();
      snapshot = HilSnapshot.disconnected(error!);
      map = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sendTask(int taskId, {bool userConfirmed = false}) async {
    if (busy) return;
    final transport = _transport;
    if (transport == null || !gatewayConnected) {
      throw const TransportException('Gateway 尚未连接');
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await transport.sendTask(taskId, userConfirmed: userConfirmed);
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> emergencyReset() => sendTask(7, userConfirmed: true);

  @override
  void dispose() {
    _snapshotSubscription?.cancel();
    _mapSubscription?.cancel();
    _transport?.dispose();
    super.dispose();
  }
}
