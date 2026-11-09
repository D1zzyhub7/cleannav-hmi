class TaskDefinition {
  const TaskDefinition(
      {required this.id,
      required this.key,
      required this.label,
      required this.detail});
  final int id;
  final String key;
  final String label;
  final String detail;
}

const tasks = <TaskDefinition>[
  TaskDefinition(
      id: 41, key: 'GOTO_REGION', label: '点到点导航', detail: '前往已注册区域入口'),
  TaskDefinition(
      id: 4, key: 'STOP_CURRENT_TASK', label: '普通停止', detail: '取消任务并清理等待队列'),
  TaskDefinition(
      id: 6,
      key: 'SOFTWARE_EMERGENCY_STOP',
      label: '紧急停车',
      detail: '请求 Safety 锁存急停'),
  TaskDefinition(
      id: 7,
      key: 'RESET_SOFTWARE_EMERGENCY_STOP',
      label: '急停复位',
      detail: '明确确认后请求复位，不恢复旧任务'),
  TaskDefinition(
      id: 43,
      key: 'RETURN_CHARGER',
      label: '返回充电点',
      detail: '前往已配置的充电等待位，不执行对接或充电'),
];
TaskDefinition taskById(int id) => tasks.firstWhere((task) => task.id == id);

class MapIdentity {
  const MapIdentity(this.mapId, this.revision, this.sha256);
  final String mapId;
  final String revision;
  final String sha256;
  factory MapIdentity.fromJson(Map<String, dynamic> json) {
    final id = (json['map_id'] is String ? json['map_id'] as String : '');
    final revision =
        (json['revision'] is String ? json['revision'] as String : '');
    final sha = ((json['sha256'] is String ? json['sha256'] as String : ''))
        .toLowerCase();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,64}$').hasMatch(id) ||
        !RegExp(r'^[A-Za-z0-9._:+-]{1,64}$').hasMatch(revision) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) {
      throw const FormatException('地图身份缺少有效 map_id / revision / sha256');
    }
    return MapIdentity(id, revision, sha);
  }
  Map<String, dynamic> toJson() =>
      {'map_id': mapId, 'revision': revision, 'sha256': sha256};
  bool matches(MapIdentity other) =>
      mapId == other.mapId &&
      revision == other.revision &&
      sha256 == other.sha256;
}

class RegisteredTarget {
  const RegisteredTarget(this.id, this.name);
  final String id;
  final String name;
}

/// Administrator-provided Registry JSON (or a read-only projection of it).
/// This does not discover targets through a new vehicle endpoint.
class TargetRegistry {
  const TargetRegistry(this.map, this.regions, this.chargers);
  final MapIdentity map;
  final List<RegisteredTarget> regions;
  final List<RegisteredTarget> chargers;
  factory TargetRegistry.fromJson(Map<String, dynamic> json) {
    final map = MapIdentity.fromJson(json['map'] as Map<String, dynamic>);
    List<RegisteredTarget> parse(String key, String idKey, String nameKey) {
      final values = json[key] as List<dynamic>? ?? [];
      final ids = <String>{};
      return List.unmodifiable(values.map((value) {
        final item = value as Map<String, dynamic>;
        final id = item[idKey] as String? ?? '';
        if (!RegExp(r'^[A-Za-z0-9._:-]{1,64}$').hasMatch(id) || !ids.add(id)) {
          throw FormatException('$idKey 无效或重复');
        }
        if (key == 'chargers' && json['schema_version'] == 1) {
          final pose = item['staging_pose'];
          if (pose is! Map ||
              !['x', 'y', 'yaw']
                  .every((k) => pose[k] is num && (pose[k] as num).isFinite)) {
            throw const FormatException('Registry Charger 缺少有效 staging_pose');
          }
        }
        return RegisteredTarget(
            id, (item['display_name'] ?? item[nameKey] ?? id).toString());
      }));
    }

    return TargetRegistry(map, parse('regions', 'region_id', 'region_name'),
        parse('chargers', 'charger_id', 'charger_name'));
  }
}
