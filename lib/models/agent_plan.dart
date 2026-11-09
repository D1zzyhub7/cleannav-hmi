/// Demo business actions are deliberately separate from TaskCommand task IDs.
class AgentPlanStep {
  const AgentPlanStep({
    required this.action,
    required this.state,
    this.areaId,
    this.rounds = 0,
    this.currentRound = 0,
    this.completedRounds = 0,
  });

  final String action;
  final String state;
  final String? areaId;
  final int rounds;
  final int currentRound;
  final int completedRounds;

  factory AgentPlanStep.fromJson(Map<String, dynamic> json) => AgentPlanStep(
        action: json['action'] as String,
        state: json['state'] as String,
        areaId: json['area_id'] as String?,
        rounds: (json['rounds'] as num?)?.toInt() ?? 0,
        currentRound: (json['current_round'] as num?)?.toInt() ?? 0,
        completedRounds: (json['completed_rounds'] as num?)?.toInt() ?? 0,
      );

  String get label => switch (action) {
        'go_to_area' => '前往 $areaId 区',
        'patrol_clean' => '$areaId 区巡航清扫 $rounds 轮',
        'return_to_charge' => '返回充电处',
        'emergency_stop' => '紧急停车（模拟）',
        _ => action,
      };

  Map<String, dynamic> toTaskJson() => {
        'action': action,
        if (areaId != null) 'area_id': areaId,
        if (action == 'patrol_clean') 'rounds': rounds,
      };
}

class AgentPlan {
  const AgentPlan({
    required this.id,
    required this.text,
    required this.state,
    required this.parserMode,
    required this.steps,
    this.error,
    this.modelProvider,
    this.modelName,
  });

  final String id;
  final String text;
  final String state;
  final String parserMode;
  final List<AgentPlanStep> steps;
  final String? error;
  final String? modelProvider;
  final String? modelName;

  bool get running => state == 'RUNNING';

  factory AgentPlan.fromJson(Map<String, dynamic> json) {
    if (json['execution_mode'] != 'simulation') {
      throw const FormatException('助手演示只接受模拟执行服务');
    }
    return AgentPlan(
      id: json['plan_id'] as String,
      text: json['text'] as String,
      state: json['state'] as String,
      parserMode: json['parser_mode'] as String,
      steps: List.unmodifiable((json['steps'] as List).map(
        (step) => AgentPlanStep.fromJson(step as Map<String, dynamic>),
      )),
      error: json['error'] as String?,
      modelProvider: json['model_provider'] as String?,
      modelName: json['model_name'] as String?,
    );
  }

  String get statusLabel => switch (state) {
        'RUNNING' => '模拟执行中',
        'SUCCEEDED' => '模拟计划已完成',
        'CANCELED' => '模拟已停止',
        'EMERGENCY_STOPPED' => '模拟急停已执行',
        'FAILED' => '模拟执行失败',
        _ => state,
      };
}
