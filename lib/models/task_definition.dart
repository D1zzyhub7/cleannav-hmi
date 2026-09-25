class TaskDefinition {
  const TaskDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.detail,
  });

  final int id;
  final String key;
  final String label;
  final String detail;
}

const competitionTask = TaskDefinition(
  id: 30,
  key: 'CLEAN_NEAREST_LEAF',
  label: '清扫最近落叶',
  detail: '自动寻找并清扫最近可用落叶目标',
);

const tasks = <TaskDefinition>[competitionTask];

TaskDefinition taskById(int id) => tasks.firstWhere((task) => task.id == id);
