import 'task_definition.dart';

enum VehicleMode { offline, standby, planning, navigating, cleaning, paused, returning, charging, emergency, error }
enum ConnectionKind { demo, network, bluetooth }

extension VehicleModeText on VehicleMode {
  String get label => switch (this) {
    VehicleMode.offline => '离线', VehicleMode.standby => '待机中', VehicleMode.planning => '规划中',
    VehicleMode.navigating => '导航中', VehicleMode.cleaning => '清扫中', VehicleMode.paused => '已暂停',
    VehicleMode.returning => '返航中', VehicleMode.charging => '充电中', VehicleMode.emergency => '紧急锁定',
    VehicleMode.error => '系统异常',
  };
}

class VehicleState {
  const VehicleState({
    required this.mode,
    required this.connection,
    required this.battery,
    required this.speed,
    required this.progress,
    required this.route,
    required this.message,
    this.task,
    this.emergencyStop = false,
    this.brushOn = false,
    this.waterPumpOn = false,
    this.localizationOk = false,
    this.charging = false,
  });

  final VehicleMode mode;
  final ConnectionKind connection;
  final double battery;
  final double speed;
  final double progress;
  final RouteKind route;
  final String message;
  final TaskDefinition? task;
  final bool emergencyStop;
  final bool brushOn;
  final bool waterPumpOn;
  final bool localizationOk;
  final bool charging;

  VehicleState copyWith({
    VehicleMode? mode, ConnectionKind? connection, double? battery, double? speed,
    double? progress, RouteKind? route, String? message, TaskDefinition? task,
    bool clearTask = false, bool? emergencyStop, bool? brushOn, bool? waterPumpOn,
    bool? localizationOk, bool? charging,
  }) => VehicleState(
    mode: mode ?? this.mode, connection: connection ?? this.connection,
    battery: battery ?? this.battery, speed: speed ?? this.speed,
    progress: progress ?? this.progress, route: route ?? this.route,
    message: message ?? this.message, task: clearTask ? null : task ?? this.task,
    emergencyStop: emergencyStop ?? this.emergencyStop, brushOn: brushOn ?? this.brushOn,
    waterPumpOn: waterPumpOn ?? this.waterPumpOn, localizationOk: localizationOk ?? this.localizationOk,
    charging: charging ?? this.charging,
  );

  factory VehicleState.initial() => const VehicleState(
    mode: VehicleMode.standby, connection: ConnectionKind.demo, battery: 78,
    speed: 0, progress: 0, route: RouteKind.patrol, message: '车辆已就绪',
  );

  factory VehicleState.fromJson(Map<String, dynamic> json, ConnectionKind kind) {
    final robot = (json['robot'] ?? json['robot_status'] ?? json) as Map<String, dynamic>;
    final taskJson = json['task'] as Map<String, dynamic>?;
    final taskId = (taskJson?['task_id'] ?? taskJson?['taskId'] ?? taskJson?['id']) as num?;
    TaskDefinition? task;
    if (taskId != null) {
      for (final candidate in tasks) {
        if (candidate.id == taskId.toInt()) { task = candidate; break; }
      }
    }
    final rawMode = (robot['mode'] ?? robot['system_state'] ?? robot['systemState'] ?? 'STANDBY').toString().toUpperCase();
    final taskState = (taskJson?['state'] ?? '').toString().toUpperCase();
    final emergency = robot['emergency_stop'] == true || robot['emergency_stop_active'] == true || robot['emergencyStop'] == true || rawMode.contains('EMERGENCY') || taskState == 'EMERGENCY_STOPPED';
    final offline = robot['connection']?.toString().toLowerCase() == 'offline';
    final charging = robot['charging'] == true || rawMode == 'CHARGING';
    final mode = offline ? VehicleMode.offline : emergency ? VehicleMode.emergency : charging ? VehicleMode.charging : switch (taskState) {
      'PLANNING' || 'ACCEPTED' || 'QUEUED' || 'WAITING_TARGET' => VehicleMode.planning,
      'NAVIGATING' => VehicleMode.navigating, 'PAUSED' => VehicleMode.paused,
      'RETURNING_HOME' => VehicleMode.returning,
      _ => switch (rawMode) {
        'RUNNING' || 'NAVIGATING' || 'BUSY' || 'SYSTEM_BUSY' => VehicleMode.navigating,
        'CLEANING' => VehicleMode.cleaning, 'PAUSED' => VehicleMode.paused,
        'RETURNING' || 'RETURNING_HOME' => VehicleMode.returning,
        'PLANNING' => VehicleMode.planning,
        'SYSTEM_READY' => VehicleMode.standby,
        'SYSTEM_PAUSED' => VehicleMode.paused,
        'SYSTEM_ERROR' || 'SYSTEM_BLOCKED' || 'ERROR' => VehicleMode.error,
        _ => VehicleMode.standby,
      },
    };
    final batteryValue = robot['battery'] ?? robot['battery_percent'];
    final speedValue = robot['linear_velocity_mps'] ?? robot['speed'] ?? robot['linear_speed'] ?? 0;
    return VehicleState(
      mode: mode, connection: kind,
      battery: batteryValue is num ? batteryValue.toDouble() : -1,
      speed: speedValue is num ? speedValue.toDouble() : 0,
      progress: ((taskJson?['progress'] ?? 0) as num).toDouble().clamp(0, 1).toDouble(),
      route: task?.route ?? RouteKind.patrol, task: task,
      message: (taskJson?['message'] ?? robot['message'] ?? mode.label).toString(),
      emergencyStop: emergency, brushOn: robot['brush_on'] == true || robot['brushOn'] == true,
      waterPumpOn: robot['water_pump_on'] == true || robot['waterPumpOn'] == true,
      localizationOk: robot['localization_ok'] == true,
      charging: charging,
    );
  }
}
