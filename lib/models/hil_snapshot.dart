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
      taskProgress: _clampProgress(task['progress']),
      activeTargetId: _stringValue(task['active_target_id']),
      remainingDistanceM: _doubleValue(task['remaining_distance_m']),
      taskMessage: _stringValue(
        task['message'],
        fallback: present ? '任务状态已收到' : '暂无执行任务',
      ),
    );
  }

  String get taskLabel => taskId == competitionTask.id
      ? competitionTask.label
      : taskId == 0
          ? '暂无任务'
          : 'Task $taskId';

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
    return _doubleValue(value).clamp(0.0, 1.0).toDouble();
  }
}

class HilSnapshot {
  const HilSnapshot({
    required this.gatewayConnected,
    required this.j6Connected,
    required this.localizationOk,
    required this.autonomousEnabled,
    required this.emergencyStop,
    required this.systemState,
    required this.systemMessage,
    required this.task,
    this.speedMps,
  });

  final bool gatewayConnected;
  final bool? j6Connected;
  final bool? localizationOk;
  final bool? autonomousEnabled;
  final bool? emergencyStop;
  final String systemState;
  final String systemMessage;
  final TaskStatusSnapshot task;
  final double? speedMps;

  factory HilSnapshot.unconfigured() => HilSnapshot(
        gatewayConnected: false,
        j6Connected: null,
        localizationOk: null,
        autonomousEnabled: null,
        emergencyStop: null,
        systemState: 'UNCONFIGURED',
        systemMessage: '请先配置 Gateway 地址',
        task: TaskStatusSnapshot.empty(),
      );

  factory HilSnapshot.disconnected(String message) => HilSnapshot(
        gatewayConnected: false,
        j6Connected: null,
        localizationOk: null,
        autonomousEnabled: null,
        emergencyStop: null,
        systemState: 'GATEWAY_OFFLINE',
        systemMessage: message,
        task: TaskStatusSnapshot.empty(),
      );

  factory HilSnapshot.fromJson(
    Map<String, dynamic> json, {
    required bool gatewayConnected,
  }) {
    final robot = _mapValue(json['robot']);
    final systemState = _stringValue(
      robot['system_state'],
      fallback: 'SYSTEM_UNKNOWN',
    ).toUpperCase();
    final message = _stringValue(
      robot['message'],
      fallback: systemState,
    );
    final emergency = robot['emergency_stop'] == true ||
        robot['emergency_stop_active'] == true ||
        systemState == 'SYSTEM_EMERGENCY_STOP';

    return HilSnapshot(
      gatewayConnected: gatewayConnected,
      j6Connected: _boolValue(json['j6_connected']),
      localizationOk: _boolValue(robot['localization_ok']),
      autonomousEnabled: _boolValue(robot['autonomous_enabled']),
      emergencyStop: emergency,
      systemState: systemState,
      systemMessage: message,
      task: TaskStatusSnapshot.fromJson(_mapValue(json['task'])),
      speedMps: _numberValue(
        robot['linear_velocity_mps'] ?? robot['speed'],
      ),
    );
  }

  static Map<String, dynamic> _mapValue(Object? value) {
    return value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  static bool? _boolValue(Object? value) => value is bool ? value : null;

  static double? _numberValue(Object? value) {
    return value is num ? value.toDouble() : null;
  }
}
