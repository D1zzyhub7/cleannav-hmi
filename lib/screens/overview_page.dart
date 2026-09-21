import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/vehicle_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mission_map.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.controller, required this.openTasks});
  final AppController controller;
  final VoidCallback openTasks;

  Color _modeColor(VehicleMode mode) => switch (mode) {
    VehicleMode.emergency || VehicleMode.error || VehicleMode.offline => AppColors.red,
    VehicleMode.charging => AppColors.blue,
    VehicleMode.paused || VehicleMode.planning => AppColors.amber,
    _ => AppColors.green,
  };

  IconData _modeIcon(VehicleMode mode) => switch (mode) {
    VehicleMode.standby => Icons.power_settings_new_rounded, VehicleMode.planning => Icons.alt_route_rounded,
    VehicleMode.navigating => Icons.navigation_rounded, VehicleMode.cleaning => Icons.cleaning_services_rounded,
    VehicleMode.paused => Icons.pause_rounded, VehicleMode.returning => Icons.home_rounded,
    VehicleMode.charging => Icons.battery_charging_full_rounded, VehicleMode.emergency => Icons.emergency_rounded,
    VehicleMode.error => Icons.error_rounded, VehicleMode.offline => Icons.cloud_off_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final color = _modeColor(state.mode);
    return ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 26), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0C3138),Color(0xFF11624F)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(26)),
        child: Row(children: [
          Container(width: 48,height:48,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.12),borderRadius:BorderRadius.circular(15)),child:const Center(child:Text('CN',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900)))),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('CleanNav',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),SizedBox(height:3),Text('无人清扫车智能控制中心',style:TextStyle(color:Color(0xFFB9D7D0),fontSize:12))])),
          InkWell(onTap: state.emergencyStop ? null : () => _emergency(context), borderRadius: BorderRadius.circular(99), child: Container(width:48,height:48,decoration:BoxDecoration(color:AppColors.red,borderRadius:BorderRadius.circular(99)),child:const Icon(Icons.stop_rounded,color:Colors.white))),
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(child: Row(children: [
        Container(width:52,height:52,decoration:BoxDecoration(color:color.withValues(alpha:.11),borderRadius:BorderRadius.circular(17)),child:Icon(_modeIcon(state.mode),color:color)),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('车辆当前状态',style:TextStyle(color:AppColors.muted,fontSize:11)),const SizedBox(height:3),Text(state.mode.label,style:const TextStyle(color:AppColors.ink,fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(state.message,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:AppColors.muted,fontSize:12))])),
        StatusPill(text: switch(state.connection){ConnectionKind.demo=>'演示',ConnectionKind.network=>'网络',ConnectionKind.bluetooth=>'蓝牙'}, color: state.mode==VehicleMode.offline?AppColors.red:AppColors.green),
      ])),
      if (state.emergencyStop) ...[const SizedBox(height: 12), _EmergencyBanner(controller: controller)],
      const SizedBox(height: 14),
      GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:1.17,children:[
        MetricTile(icon:state.charging?Icons.battery_charging_full:Icons.battery_5_bar,label:'剩余电量',value:state.battery<0?'--':'${state.battery.toStringAsFixed(0)}%',color:state.battery>=0&&state.battery<20?AppColors.red:AppColors.green,caption:state.charging?'充电输入正常':state.battery<0?'当前接口未提供电量':'预计续航 ${(state.battery/20).toStringAsFixed(1)} h'),
        MetricTile(icon:Icons.speed_rounded,label:'当前速度',value:state.speed<0?'--':'${state.speed.toStringAsFixed(2)} m/s',color:AppColors.blue,caption:state.speed<0?'当前接口未提供速度':state.speed>0?'车辆正在运动':'车辆静止'),
        MetricTile(icon:Icons.gps_fixed_rounded,label:'定位状态',value:state.localizationOk?'正常':'异常',color:state.localizationOk?AppColors.green:AppColors.red,caption:'map 坐标系'),
        MetricTile(icon:state.brushOn?Icons.cleaning_services:Icons.blur_circular,label:'清扫机构',value:state.brushKnown?(state.brushOn?'工作中':'已关闭'):'--',color:state.brushOn?AppColors.green:AppColors.muted,caption:state.waterPumpKnown?(state.waterPumpOn?'水泵/吸水机构开启':'水泵关闭'):'当前接口未提供机构状态'),
      ]),
      const SizedBox(height:14),
      SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('实时作业地图',style:TextStyle(color:AppColors.ink,fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(controller.map == null ? (state.connection == ConnectionKind.network ? '等待 PC RTAB-Map 数据' : '演示路线随任务进度变化') : 'RTAB-Map 2D occupancy grid',style:const TextStyle(color:AppColors.muted,fontSize:11))])),StatusPill(text:controller.map == null?'${(state.progress*100).round()}%':'MAP ${controller.map!.seq}',color:AppColors.green)]),
        const SizedBox(height:14), MissionMap(state:state,map:controller.map), const SizedBox(height:12),
        Row(children:[_legend(AppColors.green,'已执行'),const SizedBox(width:15),_legend(const Color(0xFFB6C8C8),'待执行'),const Spacer(),Text(state.task?.label??'当前无任务',style:const TextStyle(color:AppColors.muted,fontSize:11))]),
      ])),
      const SizedBox(height:14),
      FilledButton.icon(onPressed:openTasks,icon:const Icon(Icons.route_rounded),label:const Text('进入任务中心'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52),backgroundColor:AppColors.greenDark,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(17)))),
    ]);
  }

  Widget _legend(Color color,String label)=>Row(children:[Container(width:20,height:5,decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(5))),const SizedBox(width:6),Text(label,style:const TextStyle(color:AppColors.muted,fontSize:10))]);

  Future<void> _emergency(BuildContext context) async {
    final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('触发软件急停？'),content:const Text('将立即关闭自主运动与清扫输出。网络急停不能替代车辆硬件急停。'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('取消')),FilledButton(style:FilledButton.styleFrom(backgroundColor:AppColors.red),onPressed:()=>Navigator.pop(context,true),child:const Text('立即急停'))]));
    if(confirmed==true) await controller.execute(6);
  }
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFFFEEF1),borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFF2B5BE))),child:Row(children:[const Icon(Icons.lock_rounded,color:AppColors.red),const SizedBox(width:10),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('急停锁定',style:TextStyle(color:AppColors.red,fontWeight:FontWeight.w800)),Text('普通任务已禁用，请确认现场安全',style:TextStyle(color:Color(0xFF9E5C66),fontSize:11))])),FilledButton(onPressed:()=>_reset(context),style:FilledButton.styleFrom(backgroundColor:AppColors.red),child:const Text('解除'))]));
  Future<void> _reset(BuildContext context) async {final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('确认现场安全'),content:const Text('请确认车辆周围无人、故障原因已排除。解除后车辆保持待机，不会自动恢复旧任务。'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('确认解除'))]));if(ok==true)await controller.execute(7,userConfirmed:true);}
}
