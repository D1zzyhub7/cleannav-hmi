import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CleanNavApp());
}

class CleanNavApp extends StatefulWidget {
  const CleanNavApp({super.key});

  @override
  State<CleanNavApp> createState() => _CleanNavAppState();
}

class _CleanNavAppState extends State<CleanNavApp> with WidgetsBindingObserver {
  final AppController controller = AppController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanNav',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: HomeShell(controller: controller),
    );
  }
}
