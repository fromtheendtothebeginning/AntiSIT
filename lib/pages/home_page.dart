import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 主导航壳：底栏与页面**全部由插件注册表组装**——插件被停用（或被构建期剔除）后，
/// 这里既不会剩下空 tab，也不会引用到不存在的页面。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ValueNotifier<int> tab = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    // 插件启停会改变底栏格数，当前下标可能越界
    PluginRegistry.I.addListener(_clampTab);
  }

  @override
  void dispose() {
    PluginRegistry.I.removeListener(_clampTab);
    tab.dispose();
    super.dispose();
  }

  void _clampTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final last = PluginRegistry.I.navPages(tab).length - 1;
      if (last >= 0 && tab.value > last) tab.value = last;
    });
  }

  Future<void> _exitDemo() async {
    // 退出演示留在主导航界面（我的页显示未登录），不跳登录页
    await AppState.I.setDemo(false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tab,
      builder: (context, i, _) => ListenableBuilder(
        listenable: Listenable.merge([AppState.I, PluginRegistry.I]),
        builder: (context, _) {
          final demo = AppState.I.demo;
          final pages = PluginRegistry.I.navPages(tab);
          final index = pages.isEmpty ? 0 : i.clamp(0, pages.length - 1);
          return Scaffold(
            body: pages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('所有功能插件都被停用了。到「我的 → 插件管理」里重新打开即可。',
                          textAlign: TextAlign.center),
                    ),
                  )
                : IndexedStack(
                    index: index,
                    children: [
                      // key = 插件 id：增删插件时各页的 State 不会串位
                      for (var k = 0; k < pages.length; k++)
                        KeyedSubtree(
                          key: ValueKey(pages[k].$1.id),
                          child: pages[k].$2.build(k),
                        ),
                    ],
                  ),
            bottomNavigationBar: pages.isEmpty
                ? null
                : Column(
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer),
                                    const SizedBox(width: 6),
                                    Text('演示模式 · 本地假数据，点此退出',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onTertiaryContainer)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      GlassNavBar(
                        index: index,
                        onChanged: (v) => tab.value = v,
                        items: [
                          for (final (_, item) in pages)
                            GlassNavBarItem(item.icon, item.activeIcon, item.label),
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
