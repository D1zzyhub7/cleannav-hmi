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
      this.connection = const {}});
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
