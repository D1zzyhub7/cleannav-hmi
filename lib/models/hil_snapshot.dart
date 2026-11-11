import 'dart:math' as math;
import 'occupancy_map.dart';
import 'task_definition.dart';

class TaskStatusSnapshot {
  const TaskStatusSnapshot({
    required this.taskStatusPresent,
    required this.executionId,
    required this.commandId,
    required this.taskId,
    required this.taskState,
    required this.taskProgress,
    required this.activeTargetId,
    required this.remainingDistanceM,
    required this.taskMessage,
    this.reasonCode = 0,
    this.statusScope = 'UNKNOWN',
  });

  final bool taskStatusPresent;
  final String executionId;
  final String commandId;
  final int taskId;
  final String taskState;
  final double taskProgress;
  final String activeTargetId;
  final double remainingDistanceM;
  final String taskMessage;
  final int reasonCode;
  final String statusScope;

  factory TaskStatusSnapshot.empty() => const TaskStatusSnapshot(
        taskStatusPresent: false,
        executionId: '',
        commandId: '',
        taskId: 0,
        taskState: 'UNKNOWN',
        taskProgress: 0,
        activeTargetId: '',
        remainingDistanceM: 0,
        taskMessage: '暂无执行任务',
      );

  factory TaskStatusSnapshot.fromJson(Map<String, dynamic>? json) {
    final task = json ?? const <String, dynamic>{};
    final executionId = _stringValue(task['execution_id']);
    final commandId = _stringValue(task['command_id']);
    final taskId = _intValue(task['task_id']);
    final taskState = _stringValue(
      task['state'],
      fallback: 'UNKNOWN',
    ).toUpperCase();
    final present = executionId.isNotEmpty ||
        commandId.isNotEmpty ||
        taskId != 0 ||
        taskState != 'UNKNOWN';

    return TaskStatusSnapshot(
      taskStatusPresent: present,
      executionId: executionId,
      commandId: commandId,
      taskId: taskId,
      taskState: taskState,
      taskProgress:
          task['progress'] == null ? -1 : _clampProgress(task['progress']),
      reasonCode: _intValue(task['reason_code']),
      statusScope: _stringValue(task['status_scope_name'], fallback: 'UNKNOWN'),
      activeTargetId: _stringValue(task['active_target_id']),
      remainingDistanceM: _doubleValue(task['remaining_distance_m']),
      taskMessage: _stringValue(
        task['message'],
        fallback: present ? '任务状态已收到' : '暂无执行任务',
      ),
    );
  }

  String get taskLabel {
    for (final task in tasks) {
      if (task.id == taskId) return task.label;
    }
    return taskId == 0 ? '暂无任务' : 'Task $taskId';
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  static int _intValue(Object? value) {
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  static double _doubleValue(Object? value) {
    return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  }

  static double _clampProgress(Object? value) {
    return _doubleValue(value) < 0
        ? -1
        : _doubleValue(value).clamp(0.0, 1.0).toDouble();
  }
}

class VehicleBattery {
  const VehicleBattery({this.soc, this.ageSec});

  final double? soc;
  final double? ageSec;

  bool get known =>
      soc != null && ageSec != null && ageSec! >= 0 && ageSec! <= 15;

  String get label => known ? '${soc!.toStringAsFixed(0)}%' : '未知';

  static VehicleBattery? fromJson(Object? value) {
    if (value is! Map) return null;
    return VehicleBattery(
      soc: _finite(value['soc']),
      ageSec: _finite(value['age_sec']),
    );
  }
}

class VehicleImu {
  const VehicleImu({
    this.ageSec,
    this.orientation = const {},
    this.angularVelocity = const {},
    this.linearAcceleration = const {},
  });

  final double? ageSec;
  final Map<String, dynamic> orientation;
  final Map<String, dynamic> angularVelocity;
  final Map<String, dynamic> linearAcceleration;

  bool get known {
    if (ageSec == null || ageSec! < 0 || ageSec! > 15) return false;
    return _finite(linearAcceleration['x']) != null &&
        _finite(linearAcceleration['y']) != null &&
        _finite(linearAcceleration['z']) != null;
  }

  String get label {
    if (!known) return '未知';
    return '姿态 $attitudeText\n'
        '加速度 $accelerationText m/s²\n'
        '角速度 $gyroText';
  }

  String get rollText => _degrees()[0];
  String get pitchText => _degrees()[1];
  String get yawText => _degrees()[2];
  String get accelX => _axis(linearAcceleration, 'x');
  String get accelY => _axis(linearAcceleration, 'y');
  String get accelZ => _axis(linearAcceleration, 'z');
  String get gyroX => _axis(angularVelocity, 'x');
  String get gyroY => _axis(angularVelocity, 'y');
  String get gyroZ => _axis(angularVelocity, 'z');

  List<String> _degrees() {
    if (!known) return const ['未知', '未知', '未知'];
    final x = _finite(orientation['x']);
    final y = _finite(orientation['y']);
    final z = _finite(orientation['z']);
    final w = _finite(orientation['w']);
    if (x == null || y == null || z == null || w == null) {
      return const ['未知', '未知', '未知'];
    }
    final roll = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));
    final sinPitch = (2 * (w * y - z * x)).clamp(-1.0, 1.0).toDouble();
    final pitch = math.asin(sinPitch);
    final yaw = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));
    String deg(double radians) => '${(radians * 180 / math.pi).toStringAsFixed(1)}°';
    return [deg(roll), deg(pitch), deg(yaw)];
  }

  String _axis(Map<String, dynamic> value, String key) {
    if (!known) return '未知';
    final number = _finite(value[key]);
    return number == null ? '未知' : number.toStringAsFixed(2);
  }

  String get attitudeText =>
      known ? '$rollText $pitchText $yawText' : '未知';

  String get accelerationText =>
      known ? _vector(linearAcceleration) : '未知';

  String get gyroText => known ? _vector(angularVelocity) : '未知';

  static VehicleImu? fromJson(Object? value) {
    if (value is! Map) return null;
    return VehicleImu(
      ageSec: _finite(value['age_sec']),
      orientation: _xyzw(value['orientation']),
      angularVelocity: _xyz(value['angular_velocity']),
      linearAcceleration: _xyz(value['linear_acceleration']),
    );
  }

  static String _vector(Map<String, dynamic> value) {
    final x = _finite(value['x']);
    final y = _finite(value['y']);
    final z = _finite(value['z']);
    if (x == null || y == null || z == null) return '未知';
    return '${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} ${z.toStringAsFixed(2)}';
  }
}

double? _finite(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}

Map<String, dynamic> _xyz(Object? value) {
  if (value is! Map) return const {};
  return {
    'x': value['x'],
    'y': value['y'],
    'z': value['z'],
  };
}

Map<String, dynamic> _xyzw(Object? value) {
  if (value is! Map) return const {};
  return {
    'x': value['x'],
    'y': value['y'],
    'z': value['z'],
    'w': value['w'],
  };
}

class HilSnapshot {
  const HilSnapshot(
      {required this.gatewayConnected,
      required this.missionConnected,
      required this.localizationOk,
      required this.autonomousEnabled,
      required this.emergencyStop,
      required this.systemState,
      required this.systemMessage,
      required this.task,
      this.speedMps,
      this.pose,
      this.robotFresh = false,
      this.safetyAvailable = false,
      this.safetyFresh = false,
      this.blockAll,
      this.leaseOwner,
      this.mapIdentity,
      this.sequence = const {},
      this.lastCommand = const {},
      this.connection = const {},
      this.battery,
      this.imu});
  final bool gatewayConnected;
  final bool? missionConnected;
  final bool? localizationOk;
  final bool? autonomousEnabled;
  final bool? emergencyStop;
  final String systemState;
  final String systemMessage;
  final TaskStatusSnapshot task;
  final double? speedMps;
  final MapRobotPose? pose;
  final bool robotFresh;
  final bool safetyAvailable;
  final bool safetyFresh;
  final bool? blockAll;
  final String? leaseOwner;
  final MapIdentity? mapIdentity;
  final Map<String, dynamic> sequence;
  final Map<String, dynamic> lastCommand;
  final Map<String, dynamic> connection;
  final VehicleBattery? battery;
  final VehicleImu? imu;

  factory HilSnapshot.unconfigured() =>
      HilSnapshot.disconnected('请先配置 Gateway 地址');
  factory HilSnapshot.disconnected(String message) => HilSnapshot(
      gatewayConnected: false,
      missionConnected: null,
      localizationOk: null,
      autonomousEnabled: null,
      emergencyStop: null,
      systemState: 'GATEWAY_OFFLINE',
      systemMessage: message,
      task: TaskStatusSnapshot.empty());

  factory HilSnapshot.fromJson(Map<String, dynamic> json,
      {required bool gatewayConnected}) {
    final robot = _map(json['robot']);
    final safety = _map(json['safety']);
    final connection = _map(json['connection']);
    final health = _map(_map(json['status_health'])['robot']);
    final fresh = health['fresh'] == true;
    final safeFresh = safety['available'] == true && safety['fresh'] == true;
    MapIdentity? identity;
    if (json['map_identity'] is Map<String, dynamic>) {
      try {
        identity =
            MapIdentity.fromJson(json['map_identity'] as Map<String, dynamic>);
      } on FormatException {
        identity = null;
      }
    }
    return HilSnapshot(
      gatewayConnected:
          gatewayConnected && connection['gateway'] == 'CONNECTED',
      missionConnected: fresh && connection['task_command_subscribers'] is num
          ? (connection['task_command_subscribers'] as num) > 0
          : null,
      connection: connection,
      pose: fresh &&
              robot['localization_ok'] == true &&
              robot['pose_frame'] == 'map'
          ? _pose(robot['pose'])
          : null,
      robotFresh: fresh,
      localizationOk: fresh
          ? (robot['localization_ok'] is bool
              ? robot['localization_ok'] as bool
              : null)
          : null,
      autonomousEnabled: safeFresh
          ? (safety['autonomous_enabled'] is bool
              ? safety['autonomous_enabled'] as bool
              : null)
          : null,
      emergencyStop: safeFresh
          ? (safety['emergency_stop_active'] is bool
              ? safety['emergency_stop_active'] as bool
              : null)
          : null,
      blockAll: safeFresh
          ? (safety['block_all'] is bool ? safety['block_all'] as bool : null)
          : null,
      leaseOwner: safeFresh
          ? (safety['lease_owner_execution_id'] is String
              ? safety['lease_owner_execution_id'] as String
              : null)
          : null,
      safetyAvailable: safety['available'] == true,
      safetyFresh: safeFresh,
      systemState: fresh
          ? (robot['system_state'] is String
              ? robot['system_state'] as String
              : 'SYSTEM_UNKNOWN')
          : 'STATUS_STALE',
      systemMessage: fresh
          ? (robot['message'] is String ? robot['message'] as String : '')
          : '车辆周期状态未收到或已过期',
      task: TaskStatusSnapshot.fromJson(_map(json['task'])),
      sequence: _map(json['sequence']),
      lastCommand: _map(json['last_command']),
      mapIdentity: identity,
      speedMps: fresh
          ? (robot['linear_velocity_mps'] is num &&
                  (robot['linear_velocity_mps'] as num).isFinite
              ? (robot['linear_velocity_mps'] as num).toDouble()
              : null)
          : null,
      battery: VehicleBattery.fromJson(json['battery']),
      imu: VehicleImu.fromJson(json['imu']),
    );
  }
  static MapRobotPose? _pose(Object? value) {
    final p = _map(value);
    final q = _map(p['orientation']);
    final values = [p['x'], p['y'], q['x'], q['y'], q['z'], q['w']];
    if (values.any((v) => v is! num || !v.isFinite)) return null;
    final x = (q['x'] as num).toDouble(), y = (q['y'] as num).toDouble();
    final z = (q['z'] as num).toDouble(), w = (q['w'] as num).toDouble();
    return MapRobotPose(
        x: (p['x'] as num).toDouble(),
        y: (p['y'] as num).toDouble(),
        yaw: math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)));
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
}
