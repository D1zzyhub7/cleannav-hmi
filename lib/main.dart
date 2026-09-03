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

class _CleanNavAppState extends State<CleanNavApp> {
  final AppController controller = AppController();

  @override
  void initState() {
    super.initState();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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
