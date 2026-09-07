import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/vehicle_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final TextEditingController url = TextEditingController(text: widget.controller.apiBase);
  late final TextEditingController token = TextEditingController(text: widget.controller.token);
  List<({String id, String name, int rssi})> devices = [];
  bool scanning = false;

  @override
  void dispose(){url.dispose();token.dispose();super.dispose();}

  @override
  Widget build(BuildContext context) => ListView(padding:const EdgeInsets.fromLTRB(18,18,18,28),children:[
    const Text('设备连接',style:TextStyle(color:AppColors.ink,fontSize:28,fontWeight:FontWeight.w900)),
    const SizedBox(height:5),
    const Text('演示、网络与低功耗蓝牙三种工作模式',style:TextStyle(color:AppColors.muted,fontSize:13)),
    const SizedBox(height:16),
    SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('当前通道',style:TextStyle(color:AppColors.muted,fontSize:11)),const SizedBox(height:8),
      Row(children:[Icon(_connectionIcon(),color:AppColors.greenDark),const SizedBox(width:10),Expanded(child:Text(_connectionName(),style:const TextStyle(color:AppColors.ink,fontSize:18,fontWeight:FontWeight.w800))),StatusPill(text:widget.controller.state.mode==VehicleMode.offline?'未连接':'在线',color:widget.controller.state.mode==VehicleMode.offline?AppColors.red:AppColors.green)]),
      const SizedBox(height:10),Text(widget.controller.state.message,style:const TextStyle(color:AppColors.muted,fontSize:12)),
    ])),
    const SizedBox(height:14),
    SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('网络连接',style:TextStyle(color:AppColors.ink,fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:4),const Text('通过 HTTPS 安全网关连接实验室 ROS 2 Bridge',style:TextStyle(color:AppColors.muted,fontSize:11)),const SizedBox(height:14),
      TextField(controller:url,keyboardType:TextInputType.url,decoration:_decoration('API 地址','http://车辆IP:8765',Icons.language)),const SizedBox(height:10),
      TextField(controller:token,obscureText:true,decoration:_decoration('访问令牌','Bearer Token',Icons.key)),const SizedBox(height:12),
      FilledButton.icon(onPressed:widget.controller.busy?null:()=>widget.controller.connectNetwork(url.text,token.text),icon:const Icon(Icons.cloud_done),label:const Text('连接网络网关'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48),backgroundColor:AppColors.greenDark,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15))))
    ])),
    const SizedBox(height:14),
    SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('蓝牙连接',style:TextStyle(color:AppColors.ink,fontSize:18,fontWeight:FontWeight.w800)),SizedBox(height:4),Text('适合车辆近场调试与无网络场景',style:TextStyle(color:AppColors.muted,fontSize:11))])),OutlinedButton.icon(onPressed:scanning?null:_scan,icon:scanning?const SizedBox(width:15,height:15,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.bluetooth_searching),label:Text(scanning?'扫描中':'扫描'))]),
      if(devices.isEmpty)...[const SizedBox(height:14),const Text('尚未扫描到设备。真机需要授予蓝牙和附近设备权限。',style:TextStyle(color:AppColors.muted,fontSize:11))],
      for(final device in devices) ListTile(contentPadding:EdgeInsets.zero,leading:const CircleAvatar(backgroundColor:Color(0xFFE8F5F0),child:Icon(Icons.bluetooth,color:AppColors.greenDark)),title:Text(device.name),subtitle:Text('${device.id} · ${device.rssi} dBm',maxLines:1,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.chevron_right),onTap:()=>widget.controller.connectBluetooth(device.id)),
    ])),
    const SizedBox(height:14),
    SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('演示与状态验证',style:TextStyle(color:AppColors.ink,fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:4),const Text('无需车辆即可验证差异化路线和状态界面',style:TextStyle(color:AppColors.muted,fontSize:11)),const SizedBox(height:12),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:widget.controller.useDemo,icon:const Icon(Icons.science_outlined),label:const Text('进入演示'))),const SizedBox(width:10),Expanded(child:OutlinedButton.icon(onPressed:()=>widget.controller.setDemoCharging(true),icon:const Icon(Icons.battery_charging_full),label:const Text('模拟充电')))]),
      TextButton(onPressed:()=>widget.controller.setDemoCharging(false),child:const Text('结束充电并恢复待机')),
    ])),
    if(widget.controller.error!=null)...[const SizedBox(height:12),Text(widget.controller.error!,style:const TextStyle(color:AppColors.red,fontSize:12))],
  ]);

  InputDecoration _decoration(String label,String hint,IconData icon)=>InputDecoration(labelText:label,hintText:hint,prefixIcon:Icon(icon),filled:true,fillColor:const Color(0xFFF4F8F7),border:OutlineInputBorder(borderRadius:BorderRadius.circular(15),borderSide:BorderSide.none));
  IconData _connectionIcon()=>switch(widget.controller.state.connection){ConnectionKind.demo=>Icons.science,ConnectionKind.network=>Icons.cloud_done,ConnectionKind.bluetooth=>Icons.bluetooth_connected};
  String _connectionName()=>switch(widget.controller.state.connection){ConnectionKind.demo=>'本地演示车辆',ConnectionKind.network=>'HTTPS 网络网关',ConnectionKind.bluetooth=>'BLE 清扫车'};
  Future<void> _scan() async{setState(()=>scanning=true);try{devices=await widget.controller.scanBluetooth();}catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('蓝牙扫描失败：$error')));}finally{if(mounted)setState(()=>scanning=false);}}
}
