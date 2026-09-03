import 'dart:async';

import '../models/task_definition.dart';
import '../models/vehicle_state.dart';
import 'vehicle_transport.dart';

class DemoTransport implements VehicleTransport {
  final _states = StreamController<VehicleState>.broadcast();
  VehicleState _state = VehicleState.initial();
  Timer? _timer;
  TaskDefinition? _suspendedTask;

  @override
  ConnectionKind get kind => ConnectionKind.demo;
  @override
  Stream<VehicleState> get states => _states.stream;

  @override
  Future<void> connect() async {
    _emit(_state.copyWith(connection: ConnectionKind.demo, message: '演示车辆已连接'));
    _timer ??= Timer.periodic(const Duration(milliseconds: 450), (_) => _tick());
  }

  void _emit(VehicleState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  void _tick() {
    if (_state.charging) {
      _emit(_state.copyWith(
        battery: (_state.battery + .08).clamp(0, 100).toDouble(),
        speed: 0,
        message: '充电中 · 输入功率 1.2 kW',
      ));
      return;
    }
    if (_state.emergencyStop || _state.task == null || _state.mode == VehicleMode.paused) return;
    final task = _state.task!;
    var progress = _state.progress + _stepFor(task.id);
    if (progress >= 1) {
      _emit(_state.copyWith(
        mode: task.id == 5 ? VehicleMode.standby : VehicleMode.standby,
        speed: 0, progress: 1, brushOn: false, waterPumpOn: false,
        message: task.id == 5 ? '已返回起点，车辆待机' : '${task.label}已完成',
      ));
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_state.progress >= 1 && !_state.emergencyStop) {
          _emit(_state.copyWith(progress: 0, clearTask: true, message: '车辆待机，等待新任务'));
        }
      });
      return;
    }
    final phase = _phase(task, progress);
    _emit(_state.copyWith(
      progress: progress,
      mode: phase.mode,
      speed: phase.speed,
      brushOn: phase.brush,
      waterPumpOn: phase.pump,
      battery: (_state.battery - .018).clamp(0, 100).toDouble(),
      message: phase.message,
    ));
  }

  double _stepFor(int taskId) => switch (taskId) {
    10 => .025, 20 => .014, 30 => .018, 31 => .012, 32 => .013, 33 => .016, 5 => .022, _ => .015,
  };

  ({VehicleMode mode, double speed, bool brush, bool pump, String message}) _phase(TaskDefinition task, double progress) {
    if (task.id == 5) return (mode: VehicleMode.returning, speed: .72, brush: false, pump: false, message: '沿返航路线返回充电点');
    if (task.id == 10) return (mode: VehicleMode.navigating, speed: .68, brush: false, pump: false, message: '正在导航至一号点，清扫机构关闭');
    if (task.id == 20) return (mode: VehicleMode.cleaning, speed: .42, brush: true, pump: true, message: '沿一号闭合路线连续清扫');
    if (task.id == 1) return (mode: VehicleMode.cleaning, speed: .38, brush: true, pump: true, message: '正在执行全区域弓字形覆盖');
    final navigating = progress < .58;
    if (navigating) return (mode: VehicleMode.navigating, speed: task.id == 31 ? .34 : .54, brush: false, pump: false, message: '正在接近${task.label.replaceFirst('清扫最近', '')}目标');
    return switch (task.id) {
      30 => (mode: VehicleMode.cleaning, speed: .18, brush: true, pump: false, message: '局部回旋清扫散落叶片'),
      31 => (mode: VehicleMode.cleaning, speed: .12, brush: true, pump: true, message: '低速扩大覆盖，处理落叶堆'),
      32 => (mode: VehicleMode.cleaning, speed: .10, brush: false, pump: true, message: '沿积水边缘执行吸水处理'),
      _ => (mode: VehicleMode.cleaning, speed: .22, brush: true, pump: true, message: '正在处理最高优先级目标'),
    };
  }

  @override
  Future<void> sendTask(int taskId, {bool safetyConfirmed = false}) async {
    final task = taskById(taskId);
    if (_state.emergencyStop && taskId != 7) throw const TransportException('急停锁定中，请先确认现场安全');
    switch (taskId) {
      case 2:
        if (_state.task == null) throw const TransportException('当前没有可暂停任务');
        _suspendedTask = _state.task;
        _emit(_state.copyWith(mode: VehicleMode.paused, speed: 0, brushOn: false, waterPumpOn: false, message: '任务已暂停，执行上下文已保留'));
        return;
      case 3:
        if (_suspendedTask == null && _state.task == null) throw const TransportException('没有可继续的任务');
        final resume = _suspendedTask ?? _state.task!;
        _emit(_state.copyWith(task: resume, route: resume.route, mode: VehicleMode.planning, message: '重新规划后继续执行'));
        return;
      case 4:
        _suspendedTask = null;
        _emit(_state.copyWith(mode: VehicleMode.standby, speed: 0, progress: 0, clearTask: true, brushOn: false, waterPumpOn: false, message: '任务已停止，车辆原地待机'));
        return;
      case 6:
        _emit(_state.copyWith(mode: VehicleMode.emergency, speed: 0, emergencyStop: true, brushOn: false, waterPumpOn: false, message: '软件急停已触发，自主输出关闭'));
        return;
      case 7:
        if (!safetyConfirmed) throw const TransportException('缺少现场安全确认');
        _suspendedTask = null;
        _emit(_state.copyWith(mode: VehicleMode.standby, speed: 0, progress: 0, clearTask: true, emergencyStop: false, brushOn: false, waterPumpOn: false, message: '急停已解除，车辆保持待机'));
        return;
      default:
        _suspendedTask = null;
        _emit(_state.copyWith(task: task, route: task.route, mode: VehicleMode.planning, progress: 0, speed: 0, brushOn: false, waterPumpOn: false, charging: false, message: taskId == 5 ? '正在生成返航路线' : '正在生成任务专属路线'));
        return;
    }
  }

  void setCharging(bool enabled) {
    if (_state.emergencyStop) return;
    _emit(_state.copyWith(
      mode: enabled ? VehicleMode.charging : VehicleMode.standby,
      charging: enabled, speed: 0, progress: enabled ? 1 : 0,
      route: enabled ? RouteKind.home : RouteKind.patrol, clearTask: true,
      message: enabled ? '已连接充电桩，正在补能' : '充电结束，车辆待机',
    ));
  }

  @override
  Future<void> disconnect() async { _timer?.cancel(); _timer = null; }
  @override
  Future<void> dispose() async { await disconnect(); await _states.close(); }
}
