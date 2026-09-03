import 'dart:ui';

enum TaskGroup { control, preset, perception, safety }
enum RouteKind { patrol, pointOne, routeOne, leaf, leafPile, puddle, priority, home }

class TaskDefinition {
  const TaskDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.detail,
    required this.group,
    required this.route,
    this.confirm = false,
    this.danger = false,
  });

  final int id;
  final String key;
  final String label;
  final String detail;
  final TaskGroup group;
  final RouteKind route;
  final bool confirm;
  final bool danger;
}

const tasks = <TaskDefinition>[
  TaskDefinition(id: 1, key: 'START_DEFAULT_CLEANING', label: '开始清扫', detail: '全区域弓字形覆盖清扫', group: TaskGroup.control, route: RouteKind.patrol),
  TaskDefinition(id: 2, key: 'PAUSE_CURRENT_TASK', label: '暂停任务', detail: '保留当前位置与任务上下文', group: TaskGroup.control, route: RouteKind.patrol),
  TaskDefinition(id: 3, key: 'RESUME_CURRENT_TASK', label: '继续任务', detail: '从暂停位置继续执行', group: TaskGroup.control, route: RouteKind.patrol),
  TaskDefinition(id: 4, key: 'STOP_CURRENT_TASK', label: '停止任务', detail: '取消当前任务并原地待机', group: TaskGroup.control, route: RouteKind.patrol, confirm: true),
  TaskDefinition(id: 5, key: 'RETURN_HOME', label: '返回起点', detail: '规划最短安全返航路线', group: TaskGroup.control, route: RouteKind.home, confirm: true),
  TaskDefinition(id: 6, key: 'SOFTWARE_EMERGENCY_STOP', label: '软件急停', detail: '立即请求安全监督器急停', group: TaskGroup.safety, route: RouteKind.patrol, danger: true),
  TaskDefinition(id: 7, key: 'RESET_SOFTWARE_EMERGENCY_STOP', label: '解除急停', detail: '仅在现场安全确认后解除', group: TaskGroup.safety, route: RouteKind.patrol, confirm: true, danger: true),
  TaskDefinition(id: 10, key: 'GOTO_POINT_1', label: '前往一号点', detail: '只导航，不启动清扫机构', group: TaskGroup.preset, route: RouteKind.pointOne),
  TaskDefinition(id: 20, key: 'CLEAN_ROUTE_1', label: '执行一号路线', detail: '按预设闭合路线连续清扫', group: TaskGroup.preset, route: RouteKind.routeOne),
  TaskDefinition(id: 30, key: 'CLEAN_NEAREST_LEAF', label: '清扫最近落叶', detail: '前往最近落叶并局部回旋清扫', group: TaskGroup.perception, route: RouteKind.leaf),
  TaskDefinition(id: 31, key: 'CLEAN_NEAREST_LEAF_PILE', label: '清扫最近落叶堆', detail: '低速接近并扩大清扫覆盖', group: TaskGroup.perception, route: RouteKind.leafPile),
  TaskDefinition(id: 32, key: 'CLEAN_NEAREST_PUDDLE', label: '处理最近积水', detail: '绕开中心并沿边缘处理', group: TaskGroup.perception, route: RouteKind.puddle),
  TaskDefinition(id: 33, key: 'CLEAN_HIGHEST_PRIORITY_TARGET', label: '处理最优先目标', detail: '按优先级选择目标与路线', group: TaskGroup.perception, route: RouteKind.priority),
];

TaskDefinition taskById(int id) => tasks.firstWhere((task) => task.id == id);

List<Offset> routePoints(RouteKind route) {
  switch (route) {
    case RouteKind.patrol:
      return const [Offset(.16,.78),Offset(.18,.27),Offset(.35,.27),Offset(.35,.72),Offset(.52,.72),Offset(.52,.24),Offset(.69,.24),Offset(.69,.70),Offset(.84,.70)];
    case RouteKind.pointOne:
      return const [Offset(.16,.78),Offset(.25,.66),Offset(.39,.57),Offset(.50,.48),Offset(.63,.37),Offset(.79,.25)];
    case RouteKind.routeOne:
      return const [Offset(.16,.78),Offset(.22,.43),Offset(.43,.24),Offset(.72,.29),Offset(.82,.57),Offset(.66,.76),Offset(.38,.71),Offset(.16,.78)];
    case RouteKind.leaf:
      return const [Offset(.16,.78),Offset(.29,.64),Offset(.42,.51),Offset(.57,.42),Offset(.67,.37),Offset(.70,.34),Offset(.66,.31),Offset(.62,.35),Offset(.66,.39),Offset(.70,.34)];
    case RouteKind.leafPile:
      return const [Offset(.16,.78),Offset(.28,.69),Offset(.40,.62),Offset(.50,.53),Offset(.56,.43),Offset(.59,.35),Offset(.66,.30),Offset(.72,.35),Offset(.70,.43),Offset(.62,.45),Offset(.56,.39),Offset(.59,.31),Offset(.67,.28)];
    case RouteKind.puddle:
      return const [Offset(.16,.78),Offset(.29,.65),Offset(.46,.61),Offset(.60,.64),Offset(.69,.59),Offset(.72,.50),Offset(.68,.42),Offset(.59,.40),Offset(.52,.47),Offset(.53,.57),Offset(.61,.63)];
    case RouteKind.priority:
      return const [Offset(.16,.78),Offset(.24,.62),Offset(.36,.52),Offset(.51,.48),Offset(.61,.35),Offset(.74,.30),Offset(.83,.20)];
    case RouteKind.home:
      return const [Offset(.69,.35),Offset(.58,.46),Offset(.44,.58),Offset(.31,.69),Offset(.16,.78)];
  }
}
