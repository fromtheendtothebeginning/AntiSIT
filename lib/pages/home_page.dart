import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/common.dart';
import 'ecard_page.dart';
import 'profile_page.dart';
import 'timetable_page.dart';
import 'tools_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ValueNotifier<int> tab = ValueNotifier(0);

  Future<void> _exitDemo() async {
    // 退出演示留在主导航界面（我的页显示未登录），不跳登录页
    await AppState.I.setDemo(false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tab,
      builder: (context, i, _) => ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final demo = AppState.I.demo;
          return Scaffold(
            body: IndexedStack(index: i, children: [
              const TimetablePage(),
              EcardPage(activeTab: tab),
              const ToolsPage(),
              const ProfilePage(),
            ]),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (demo)
                  Material(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 34,
                        child: InkWell(
                          onTap: _exitDemo,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.science_outlined,
                                  size: 15,
                                  color: Theme.of(context).colorScheme.onTertiaryContainer),
                              const SizedBox(width: 6),
                              Text('演示模式 · 本地假数据，点此退出',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                GlassNavBar(
                  index: i,
                  onChanged: (v) => tab.value = v,
                  items: const [
                    GlassNavBarItem(Icons.calendar_month_outlined, Icons.calendar_month, '课程表'),
                    GlassNavBarItem(Icons.qr_code_2_outlined, Icons.qr_code_2, '校园码'),
                    GlassNavBarItem(Icons.widgets_outlined, Icons.widgets, '工具'),
                    GlassNavBarItem(Icons.person_outline, Icons.person, '我的'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
