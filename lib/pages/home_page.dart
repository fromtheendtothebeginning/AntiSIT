import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// 页面区域横滑中的连续位置（单位 = 底栏格）：底栏滑块跟着它走，松手置回 null
  /// 把位置交还给底栏自己的弹簧。单独用 ValueNotifier 是为了不每帧重建整棵页面树。
  final ValueNotifier<double?> _dragPos = ValueNotifier<double?>(null);

  /// 底栏**写出来**的当前滑块位置（每帧更新，含弹簧过程）：页面照着它位移，
  /// 于是页面和滑块是同一套弹簧、不会在切页时跳。
  final ValueNotifier<double> _pos = ValueNotifier<double>(0);
  double _dragFrom = 0;

  @override
  void initState() {
    super.initState();
    // 插件启停会改变底栏格数，当前下标可能越界
    PluginRegistry.I.addListener(_clampTab);
  }

  @override
  void dispose() {
    PluginRegistry.I.removeListener(_clampTab);
    _dragPos.dispose();
    _pos.dispose();
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

  // ── 页面区域左右滑动切页 ──
  // 只在「页面内部没接住这次横滑」时生效：课表的周视图、任何横向滚动组件都会先抢走手势，
  // 所以在那儿横滑是切周/滚内容，不会误切底栏（不冲突才切页）。
  // 判据是滑块位置就近落格：拖过一半就换页，界面永远是「最贴近滑块的那一格」。

  int get _tabCount => PluginRegistry.I.navPages(tab).length;

  double get _screenW {
    final w = MediaQuery.sizeOf(context).width;
    return w <= 0 ? 1 : w;
  }

  void _onDragStart(DragStartDetails _) {
    if (_tabCount < 2) return;
    // 从滑块**当前**位置起手（可能刚点过一下、还在弹），不然会跳一下
    _dragFrom = _pos.value;
    _dragPos.value = _dragFrom;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_tabCount < 2) return;
    final last = (_tabCount - 1).toDouble();
    // 与页面的直觉一致：content 往左拖 = 去下一格（像翻页），所以位置是「减去手指位移」
    final next = ((_dragPos.value ?? _dragFrom) - d.delta.dx / _screenW).clamp(0.0, last);
    _dragPos.value = next;
    final nearest = next.round();
    if (nearest != tab.value) tab.value = nearest;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_tabCount < 2) return;
    final last = _tabCount - 1;
    // 格/秒；与底栏同一套：慢速拖拽就近落格，快速甩动借动量多滑一格
    final v = (-d.velocity.pixelsPerSecond.dx / _screenW).clamp(-8.0, 8.0);
    var target = (_dragPos.value ?? tab.value.toDouble()).round().clamp(0, last);
    final next = target + (v > 0 ? 1 : -1);
    if (v.abs() >= 5.0 && next >= 0 && next <= last) target = next;
    _dragPos.value = null; // 交还弹簧：滑块从当前位置弹到落点
    if (target != tab.value) {
      HapticFeedback.selectionClick();
      tab.value = target;
    }
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
          // 页面做成静态子树：位置动画只动外面的 Transform，不每帧重建页面本身
          // （不加这层的话，滑动时每帧都会 build 一次课表页，直接卡住）
          final pageWidgets = [
            // key = 插件 id：增删插件时各页的 State 不会串位
            for (var k = 0; k < pages.length; k++)
              KeyedSubtree(key: ValueKey(pages[k].$1.id), child: pages[k].$2.build(k)),
          ];
          return Scaffold(
            body: pages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('所有功能插件都被停用了。到「我的 → 插件管理」里重新打开即可。',
                          textAlign: TextAlign.center),
                    ),
                  )
                : GestureDetector(
                    // translucent：页面空白处（底下没有可命中的组件）也要能起手势；
                    // 页面内部真接住了横滑（课表周视图等）时，内层识别器在手势竞技场里先赢，
                    // 所以那种滑动照旧滚内容，不会误切底栏（不冲突才切页）。
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: _onDragStart,
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    onHorizontalDragCancel: () => _dragPos.value = null,
                    // 页面跟着底栏滑块的位置一起位移（同一套弹簧，弹簧仍藏在底栏里）。
                    // 没用 PageView：那样没去过的 tab 不会建，启动时的并发预取、
                    // 校园码计时器这些「常驻」前提就没了。
                    child: ValueListenableBuilder<double>(
                      valueListenable: _pos,
                      builder: (context, pos, _) {
                        final w = MediaQuery.sizeOf(context).width;
                        return Stack(
                          children: [
                            for (var k = 0; k < pageWidgets.length; k++)
                              Positioned.fill(
                                // 只画当前这一页和拖动时露出来的邻页：更远的页不画，
                                // 省得每帧把四页都渲染一遍（状态照旧保留）
                                child: Offstage(
                                  offstage: (k - pos).abs() >= 0.999,
                                  child: Transform.translate(
                                    offset: Offset((k - pos) * w, 0),
                                    child: pageWidgets[k],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
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
                        dragPosition: _dragPos,
                        position: _pos,
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
