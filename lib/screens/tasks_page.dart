import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/task_definition.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
    children: [
      const Text('任务中心', style: TextStyle(color: AppColors.ink, fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      const Text('不同任务对应独立目标、轨迹和作业动作', style: TextStyle(color: AppColors.muted, fontSize: 13)),
      if (controller.state.emergencyStop) ...[
        const SizedBox(height: 15),
        Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFFFEEF1), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF2B5BE))), child: const Row(children: [Icon(Icons.lock, color: AppColors.red),SizedBox(width:10),Expanded(child:Text('车辆处于急停锁定状态，请在总览页解除后再下发普通任务。',style:TextStyle(color:AppColors.red,fontWeight:FontWeight.w700)))])),
      ],
      const SizedBox(height: 16),
      _group(context, '系统控制', tasks.where((task) => task.group == TaskGroup.control).toList()),
      const SizedBox(height: 14),
      _group(context, '固定点与路线', tasks.where((task) => task.group == TaskGroup.preset).toList()),
      const SizedBox(height: 14),
      _group(context, '感知目标清扫', tasks.where((task) => task.group == TaskGroup.perception).toList()),
      const SizedBox(height: 16),
      InkWell(
        onTap: controller.state.emergencyStop ? null : () => _execute(context, taskById(6)),
        borderRadius: BorderRadius.circular(20),
        child: Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x28D93B50),blurRadius:20,offset:Offset(0,8))]), child: const Row(children:[CircleAvatar(backgroundColor:Colors.white24,child:Icon(Icons.stop_rounded,color:Colors.white)),SizedBox(width:13),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('软件紧急停止',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800)),Text('立即发送 task_id 6',style:TextStyle(color:Colors.white70,fontSize:11))])),Icon(Icons.chevron_right,color:Colors.white)])),
      ),
    ],
  );

  Widget _group(BuildContext context, String title, List<TaskDefinition> items) => SectionCard(
    padding: const EdgeInsets.fromLTRB(17, 17, 17, 5),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800))),StatusPill(text:'${items.length} 项',color:AppColors.greenDark)]),
      const SizedBox(height: 8),
      for (final task in items) _taskRow(context, task),
    ]),
  );

  Widget _taskRow(BuildContext context, TaskDefinition task) {
    final blocked = controller.state.emergencyStop;
    final icon = switch (task.id) {1=>Icons.bolt,2=>Icons.pause,3=>Icons.play_arrow,4=>Icons.stop,5=>Icons.home,10=>Icons.location_on,20=>Icons.route,30=>Icons.eco,31=>Icons.grass,32=>Icons.water_drop,_=>Icons.star};
    return Opacity(
      opacity: blocked ? .38 : 1,
      child: InkWell(
        onTap: blocked ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('请先解除急停锁定'))) : () => _execute(context, task),
        child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEAF0EE)))), child: Row(children: [
          Container(width:45,height:45,decoration:BoxDecoration(color:AppColors.green.withValues(alpha:.10),borderRadius:BorderRadius.circular(14)),child:Icon(icon,color:AppColors.greenDark,size:22)),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(task.label,style:const TextStyle(color:AppColors.ink,fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(task.detail,style:const TextStyle(color:AppColors.muted,fontSize:11))])),
          Text('ID ${task.id}',style:const TextStyle(color:Color(0xFF9CACB0),fontSize:10)),
          const SizedBox(width:4),const Icon(Icons.chevron_right,color:Color(0xFF93A4A8),size:20),
        ])),
      ),
    );
  }

  Future<void> _execute(BuildContext context, TaskDefinition task) async {
    var confirmed = !task.confirm && !task.danger;
    if (!confirmed) {
      confirmed = await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:Text(task.label),content:Text(task.id==6?'将立即停止车辆自主运动和清扫输出。':'${task.detail}，确认继续吗？'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('取消')),FilledButton(style:FilledButton.styleFrom(backgroundColor:task.danger?AppColors.red:AppColors.greenDark),onPressed:()=>Navigator.pop(context,true),child:const Text('确认执行'))]))??false;
    }
    if (!confirmed) return;
    try {await controller.execute(task.id);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${task.label}已下发')));} catch(error){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.toString()),backgroundColor:AppColors.red));}
  }
}
