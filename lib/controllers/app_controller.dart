import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_definition.dart';
import '../models/occupancy_map.dart';
import '../models/vehicle_state.dart';
import '../services/ble_transport.dart';
import '../services/demo_transport.dart';
import '../services/http_transport.dart';
import '../services/vehicle_transport.dart';

class AppController extends ChangeNotifier {
  VehicleState state = VehicleState.initial();
  VehicleTransport? _transport;
  StreamSubscription<VehicleState>? _subscription;
  StreamSubscription<OccupancyMap?>? _mapSubscription;
  OccupancyMap? map;
  bool busy = false;
  String? error;
  String apiBase = '';
  String token = '';
  String bleDeviceId = '';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    apiBase = prefs.getString('api_base') ?? '';
    token = prefs.getString('token') ?? '';
    bleDeviceId = prefs.getString('ble_device_id') ?? '';
    await useDemo();
  }

  Future<void> _activate(VehicleTransport next) async {
    busy = true; error = null; notifyListeners();
    try {
      await _subscription?.cancel();
      await _mapSubscription?.cancel();
      await _transport?.dispose();
      map = null;
      _transport = next;
      _subscription = next.states.listen((incoming) {
        state = incoming; error = null; notifyListeners();
      });
      if (next is HttpTransport) {
        _mapSubscription = next.maps.listen((incoming) {
          map = incoming;
          notifyListeners();
        });
      } else {
        _mapSubscription = null;
      }
      await next.connect();
    } catch (exception) {
      error = exception.toString();
      final fallback = next.kind == ConnectionKind.network
          ? VehicleState.initial().copyWith(
              battery: -1,
              speed: -1,
              brushKnown: false,
              waterPumpKnown: false,
            )
          : state;
      state = fallback.copyWith(mode: VehicleMode.offline, connection: next.kind, message: error);
    } finally {
      busy = false; notifyListeners();
    }
  }

  Future<void> useDemo() => _activate(DemoTransport());

  Future<void> connectNetwork(String url, String accessToken) async {
    final normalized = url.trim();
    final parsed = Uri.tryParse(normalized);
    if (normalized.isEmpty ||
        parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      error = '请输入有效的 http 或 https 网关地址';
      notifyListeners();
      return;
    }
    apiBase = normalized; token = accessToken.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base', apiBase); await prefs.setString('token', token);
    await _activate(HttpTransport(baseUrl: apiBase, token: token));
  }

  Future<void> connectBluetooth(String id) async {
    bleDeviceId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ble_device_id', id);
    await _activate(BleTransport(deviceId: id));
  }

  Future<List<({String id, String name, int rssi})>> scanBluetooth() => BleTransport.scan();

  Future<void> execute(int taskId, {bool userConfirmed = false}) async {
    if (busy) return;
    busy = true; error = null; notifyListeners();
    try {
      await _transport?.sendTask(taskId, userConfirmed: userConfirmed);
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      busy = false; notifyListeners();
    }
  }

  void setDemoCharging(bool enabled) {
    final transport = _transport;
    if (transport is DemoTransport) transport.setCharging(enabled);
  }

  TaskDefinition get activeRouteTask => state.task ?? taskById(state.route == RouteKind.home ? 5 : 1);

  @override
  void dispose() {
    _subscription?.cancel();
    _mapSubscription?.cancel();
    _transport?.dispose();
    super.dispose();
  }
}
