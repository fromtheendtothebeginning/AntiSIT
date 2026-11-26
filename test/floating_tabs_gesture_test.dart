import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 组 2（#11 上滑到顶两页跳变）回归 + 真机红屏根因：横向可滚区不能驱动切页位置，收起 / 展开不能在滚动回调里同步 setState。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => AppState.I.glassTopBar = true);
  });

  /// 页面骨架：悬浮切换器 + 一个搜索框（横向可滚）+ 一条长列表。
  Widget page({
    required ValueNotifier<double> pos,
    required ValueNotifier<double?> drag,
    required List<double?> dragLog,
    required int tab,
    ValueChanged<int>? onTab,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: FloatingTabsHeader(
            topInset: 0,
            header: GlassTabs(
              flat: true,
              labels: const ['活动广场', '我的报名'],
              index: tab,
              position: pos,
              dragPosition: drag,
              onChanged: onTab ?? (_) {},
              height: 32,
            ),
            dragPosition: drag,
            child: Column(
              children: [
                // 顶栏 / 切换器是浮层：内容要让出它那一截，搜索框才不会被切换器盖住
                const SizedBox(height: 56),
                // 搜索框的 EditableText 是横向可滚动的，这里用显式横向滚动区等价替代，方便直接拖它。
                SizedBox(
                  height: 56,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < 30; i++)
                          SizedBox(
                            width: 80,
                            child: Text('关键词 $i'),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: const [
                      SizedBox(height: 400, child: Text('第一屏')),
                      SizedBox(height: 400, child: Text('第二屏')),
                      SizedBox(height: 400, child: Text('第三屏')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('横向可滚区域（搜索框）不再驱动切页位置', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final pos = ValueNotifier<double>(1); // 停在第二页
    final drag = ValueNotifier<double?>(null);
    final written = <double?>[];
    drag.addListener(() => written.add(drag.value));
    addTearDown(() {
      pos.dispose();
      drag.dispose();
    });

    await tester.pumpWidget(
      page(pos: pos, drag: drag, dragLog: written, tab: 1),
    );
    await tester.pumpAndSettle();

    // 拖搜索框（横向滚动）
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();

    expect(
      written.where((v) => v != null),
      isEmpty,
      reason: '横向滚动把「伪位置」写进了 dragPosition —— 就是 issue #11 的跳页来源',
    );
    expect(pos.value, 1, reason: '页面位置不能被搜索框的滚动带动');
  });

  testWidgets('竖向滑到顶：切换器展开，且不在 layout 里 setState（红屏回归）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final pos = ValueNotifier<double>(0);
    final drag = ValueNotifier<double?>(null);
    addTearDown(() {
      pos.dispose();
      drag.dispose();
    });

    await tester.pumpWidget(
      page(pos: pos, drag: drag, dragLog: const [], tab: 0),
    );
    await tester.pumpAndSettle();

    // 先往下看内容 → 切换器收起
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    AnimatedSlide slide() =>
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide).first);
    expect(slide().offset.dy, lessThan(-1), reason: '下滑时切换器要收起');

    // 猛甩回顶部：overscroll 纠正发生在 layout 阶段，这里以前会撞断言
    for (var i = 0; i < 4; i++) {
      await tester.fling(find.byType(ListView), const Offset(0, 500), 2000);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: '滚动回调里同步 setState 会让框架断言');
    expect(slide().offset.dy, 0, reason: '回到顶部时切换器要重新展开');
    expect(pos.value, 0, reason: '整个过程页面不能自己动');
  });
}
