import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/vehicle_state.dart';
import 'vehicle_transport.dart';

class BleProtocol {
  const BleProtocol({required this.serviceUuid, required this.commandUuid, required this.stateUuid});
  final String serviceUuid;
  final String commandUuid;
  final String stateUuid;

  static const development = BleProtocol(
    serviceUuid: '0000c100-0000-1000-8000-00805f9b34fb',
    commandUuid: '0000c101-0000-1000-8000-00805f9b34fb',
    stateUuid: '0000c102-0000-1000-8000-00805f9b34fb',
  );
}

class BleTransport implements VehicleTransport {
  BleTransport({required this.deviceId, this.protocol = BleProtocol.development});
  final String deviceId;
  final BleProtocol protocol;
  final _states = StreamController<VehicleState>.broadcast();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _command;
  StreamSubscription<List<int>>? _stateSubscription;

  @override
  ConnectionKind get kind => ConnectionKind.bluetooth;
  @override
  Stream<VehicleState> get states => _states.stream;

  static Future<List<({String id, String name, int rssi})>> scan() async {
    final devices = <String, ({String id, String name, int rssi})>{};
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName.isEmpty ? '未命名 BLE 设备' : result.device.platformName;
        devices[result.device.remoteId.str] = (id: result.device.remoteId.str, name: name, rssi: result.rssi);
      }
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await FlutterBluePlus.isScanning.where((value) => value == false).first;
    await subscription.cancel();
    final result = devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return result;
  }

  @override
  Future<void> connect() async {
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect(timeout: const Duration(seconds: 12), autoConnect: false);
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.str.toLowerCase() != protocol.serviceUuid.toLowerCase()) continue;
      for (final characteristic in service.characteristics) {
        final uuid = characteristic.uuid.str.toLowerCase();
        if (uuid == protocol.commandUuid.toLowerCase()) _command = characteristic;
        if (uuid == protocol.stateUuid.toLowerCase()) {
          await characteristic.setNotifyValue(true);
          _stateSubscription = characteristic.onValueReceived.listen(_decodeState);
        }
      }
    }
    if (_command == null || _stateSubscription == null) {
      await device.disconnect();
      throw const TransportException('设备未提供 CleanNav BLE 服务，请核对 UUID');
    }
    _device = device;
    _states.add(VehicleState.initial().copyWith(connection: kind, message: '蓝牙设备已连接，等待车辆状态'));
  }

  void _decodeState(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      _states.add(VehicleState.fromJson(json, kind));
    } catch (_) {
      _states.add(VehicleState.initial().copyWith(mode: VehicleMode.error, connection: kind, message: '蓝牙状态报文无法解析'));
    }
  }

  @override
  Future<void> sendTask(int taskId, {bool userConfirmed = false}) async {
    final characteristic = _command;
    if (characteristic == null) throw const TransportException('蓝牙尚未连接');
    final now = DateTime.now().millisecondsSinceEpoch;
    final frame = utf8.encode('${jsonEncode({
      'interface_version': '1.0',
      'command_id': 'ble-$now-${taskId.toString().padLeft(2, '0')}',
      'task_id': taskId, 'timestamp_ms': now, 'valid_for_ms': 10000,
      'user_confirmed': userConfirmed,
    })}\n');
    await characteristic.write(frame, withoutResponse: characteristic.properties.writeWithoutResponse);
  }

  @override
  Future<void> disconnect() async {
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _device?.disconnect();
    _device = null;
    _command = null;
  }

  @override
  Future<void> dispose() async { await disconnect(); await _states.close(); }
}
