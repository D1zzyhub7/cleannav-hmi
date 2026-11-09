import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../theme/app_theme.dart';
import 'agent_page.dart';
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
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: index, children: [
            _page(
                0,
                () => OverviewPage(
                    controller: widget.controller,
                    openTasks: () => setState(() => index = 1))),
            _page(1, () => TasksPage(controller: widget.controller)),
            _page(2, () => ConnectionPage(controller: widget.controller)),
            AgentPage(
                active: index == 3,
                initialGatewayUrl: widget.controller.apiBase),
          ]),
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.controller.apiBase.isEmpty
                        ? null
                        : () async {
                            try {
                              await widget.controller.sendTask(6);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.toString())));
                              }
                            }
                          },
                    style:
                        FilledButton.styleFrom(backgroundColor: AppColors.red),
                    icon: const Icon(Icons.stop_circle),
                    label: const Text('软件急停 ESTOP'),
                  ))),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  selectedIcon:
                      Icon(Icons.grid_view_rounded, color: AppColors.greenDark),
                  label: '总览'),
              NavigationDestination(
                  icon: Icon(Icons.route_outlined),
                  selectedIcon: Icon(Icons.route, color: AppColors.greenDark),
                  label: '任务'),
              NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub, color: AppColors.greenDark),
                  label: '连接'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon:
                      Icon(Icons.auto_awesome, color: AppColors.greenDark),
                  label: 'Demo 演示'),
            ],
          ),
        ]),
      );

  Widget _page(int page, Widget Function() build) => ListenableBuilder(
        listenable:
            index == page ? widget.controller : const AlwaysStoppedAnimation(0),
        builder: (context, _) => build(),
      );
}
