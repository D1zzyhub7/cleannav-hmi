import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../theme/app_theme.dart';
import 'connection_page.dart';
import 'overview_page.dart';
import 'tasks_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: index, children: [
          OverviewPage(controller: widget.controller, openTasks: () => setState(() => index = 1)),
          TasksPage(controller: widget.controller),
          ConnectionPage(controller: widget.controller),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded, color: AppColors.greenDark), label: '总览'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route, color: AppColors.greenDark), label: '任务'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub, color: AppColors.greenDark), label: '连接'),
        ],
      ),
    ),
  );
}
