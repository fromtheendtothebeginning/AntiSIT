import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/home_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：**不冲突时**左右滑动切界面，且界面永远是「最贴近底栏滑块的那一格」
/// （拖过一半就换页，不用等松手）。
///
/// 「冲突」= 页面内部自己吃掉了这次横滑（课表周视图、任何横向滚动组件），
/// 那时照旧滚内容/切周，不切底栏。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.I.demo = false;
  });

  Future<void> pumpShell(WidgetTester tester, {required PluginRegistry reg}) async {
    PluginRegistry.I = reg;
    tester.view.physicalSize = const Size(1080, 2000); // 逻辑 540×1000
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  /// 现在「在屏幕上」的是第几页：页面跟着滑块一起位移，所以取离屏幕正中最近的那一页
  int shownTab(WidgetTester tester) {
    final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    const labels = ['课程表', '校园码'];
    var best = 0;
    var bestD = double.infinity;
    for (var k = 0; k < labels.length; k++) {
      // 非当前页是 Offstage 的（只是不画，位置还在），要显式跳过 offstage 检查
      final c = tester.getCenter(find.text('页面${labels[k]}', skipOffstage: false));
      final d = (c.dx - w / 2).abs();
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  /// 从 [from] 起手横拖；第一步只为越过 touch slop（不计入位移）
  Future<TestGesture> begin(WidgetTester tester, Offset from) async {
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(-20, 0));
    await tester.pump();
    return g;
  }

  group('页面区域左右滑动切页', () {
    testWidgets('拖过一半就切到下一格（松手前界面已经是新的了）', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());
      expect(shownTab(tester), 0);

      final g = await begin(tester, const Offset(420, 600));
      await g.moveBy(const Offset(-300, 0)); // 540 屏宽的一半多一点
      await tester.pump();

      expect(shownTab(tester), 1, reason: '滑块已经更贴近第二格，界面就该是第二格');
      await g.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 1, reason: '松手后停在这一格');
    });

    testWidgets('拖不过一半就弹回原格', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());

      final g = await begin(tester, const Offset(420, 600));
      await g.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(shownTab(tester), 0, reason: '还没到一半，视线不该跳');

      await g.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 0);
    });

    testWidgets('右滑回上一格', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());
      // 先滑到第二格
      final g1 = await begin(tester, const Offset(420, 600));
      await g1.moveBy(const Offset(-300, 0));
      await g1.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 1);

      final g2 = await begin(tester, const Offset(120, 600));
      await g2.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(shownTab(tester), 0);
      await g2.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 0);
    });

    testWidgets('第一格再往右滑不动（不循环）', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());

      final g = await begin(tester, const Offset(120, 600));
      await g.moveBy(const Offset(400, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 0);
    });
  });

  group('切页是平滑过渡（页面跟着滑块走同一套弹簧）', () {
    double pageLeft(WidgetTester tester) =>
        tester.getTopLeft(find.text('页面课程表', skipOffstage: false)).dx;

    testWidgets('拖动中页面连续跟手，不是到点才跳一下', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());
      final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final before = pageLeft(tester);

      final g = await begin(tester, const Offset(420, 600));
      await g.moveBy(const Offset(-135, 0)); // 约 1/4 屏
      await tester.pump();

      // 页面被推走了约 1/4 屏（既不是没动，也不是整屏瞬移）
      expect(before - pageLeft(tester), closeTo(w * 0.25, w * 0.06));
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('点底栏切页也是动画：中间帧在路上，最终停到下一页', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());
      final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final before = pageLeft(tester);

      await tester.tap(find.text('校园码'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final mid = before - pageLeft(tester);
      expect(mid, greaterThan(0), reason: '已经开始动了');
      expect(mid, lessThan(w * 0.9), reason: '还在路上——瞬切的话这一帧就已经整屏位移了');

      await tester.pumpAndSettle();
      expect(before - pageLeft(tester), closeTo(w, w * 0.02), reason: '最终停在下一页');
    });
  });

  group('开关：界面是否实时跟着滑块切换', () {
    testWidgets('关掉后拖动中界面不动，松手落位才换', (tester) async {
      AppState.I.followSlider = false;
      addTearDown(() => AppState.I.followSlider = true);
      await pumpShell(tester, reg: _plainRegistry());
      final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      double left() => tester.getTopLeft(find.text('页面课程表', skipOffstage: false)).dx;
      final before = left();

      final g = await begin(tester, const Offset(420, 600));
      await g.moveBy(Offset(-w * 0.7, 0));
      await tester.pump();
      expect(left(), closeTo(before, 1), reason: '关掉实时跟随：拖动中界面不动');
      expect(shownTab(tester), 0, reason: '也没换页');

      await g.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 1, reason: '松手落位后才切');
    });
  });

  group('冲突时不抢手势', () {
    testWidgets('页面里有横向滚动组件：横滑它只滚内容，不切页', (tester) async {
      await pumpShell(tester, reg: _registryWithHorizontalStrip());

      // 页面顶部有一条横向列表（高 200），在它上面横滑
      final g = await begin(tester, const Offset(420, 100));
      await g.moveBy(const Offset(-200, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(shownTab(tester), 0, reason: '内部横向滚动组件先接住了手势');
      final inner = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(inner.position.pixels, greaterThan(0), reason: '内容确实被滚了');

      // 同一条页面的空白区域横滑 → 没有冲突，照常切页
      final g2 = await begin(tester, const Offset(420, 600));
      await g2.moveBy(const Offset(-300, 0));
      await tester.pump();
      await g2.up();
      await tester.pumpAndSettle();
      expect(shownTab(tester), 1);
    });
  });

  group('底栏自身的拖拽照旧可用', () {
    testWidgets('在底栏上横拖滑块也能换页（回归保护）', (tester) async {
      await pumpShell(tester, reg: _plainRegistry());

      // 底栏滑块是「跟手」的：往右拖 = 去下一格
      await tester.drag(find.text('课程表'), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(shownTab(tester), 1);
    });
  });

  group('拓展子页接进主界面滑动链（NavSwipeScope 桥）', () {
    /// 底栏三页：工具(0) 拓展(1) 我的(2)；拓展内部两子页：我的(0) 市场(1)。
    /// 滑动链：… 工具 ⇄ 拓展·我的 ⇄ 拓展·市场 ⇄ 我的 …
    Future<void> pumpExtShell(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      ExtensionStore.I = ExtensionStore();
      ExtensionStore.builtins = const [];
      // 市场目录不真发网络请求（失败即可，别让 loading 的不定动画卡住 settle）
      MarketSource.I = MarketSource();
      MarketSource.fetcher = (Uri url) => throw Exception('offline');
      PluginRegistry.I = PluginRegistry(
        features: const [
          _Page('tools', '工具', 30),
          WebViewPlugin(),
          ExtPlugin(),
          _Page('profile', '我的', 99),
        ],
        themes: const [GlassTheme()],
        capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
      );
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
    }

    /// 拓展页 body 的拖动起点（AppBar 与标签条之下、列表空白处）
    final extBody = const Offset(270, 600);

    /// 拓展页在屏幕上的水平中心：哪个子页在显示就用哪个的标志文本
    /// （另一个子页的标志被滑到一屏之外，不能拿来代表拓展页位置）
    double extCenterX(WidgetTester tester) {
      final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final mine = tester.getCenter(find.text('还没有拓展', skipOffstage: false)).dx;
      final market = tester.getCenter(find.text('搜名称 / 简介 / 作者', skipOffstage: false)).dx;
      return (mine - w / 2).abs() <= (market - w / 2).abs() ? mine : market;
    }

    /// 现在在屏幕正中附近的是哪页：0=工具 1=拓展 2=我的
    int shownPage(WidgetTester tester) {
      final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final xs = [
        tester.getCenter(find.text('页面工具', skipOffstage: false)).dx,
        extCenterX(tester),
        tester.getCenter(find.text('页面我的', skipOffstage: false)).dx,
      ];
      var best = 0;
      var bestD = double.infinity;
      for (var k = 0; k < xs.length; k++) {
        final d = (xs[k] - w / 2).abs();
        if (d < bestD) {
          bestD = d;
          best = k;
        }
      }
      return best;
    }

    testWidgets('「我的」子页向上一格方向拖：工具页跟着滑进来，松手落位工具', (tester) async {
      await pumpExtShell(tester);
      await tester.tap(find.text('拓展'));
      await tester.pumpAndSettle();
      expect(find.text('还没有拓展'), findsOneWidget);

      final g = await begin(tester, extBody);
      await g.moveBy(const Offset(300, 0)); // 手指右划 = 主界面上一格（工具）
      await tester.pump();
      expect(shownPage(tester), 0, reason: '拖动中工具页已经滑到眼前');
      await g.up();
      await tester.pumpAndSettle();
      expect(shownPage(tester), 0, reason: '松手落位工具页');
    });

    testWidgets('市场子页向下一格方向拖：切到「我的」页（底栏）', (tester) async {
      await pumpExtShell(tester);
      await tester.tap(find.text('拓展'));
      await tester.pumpAndSettle();

      // 先在拓展内部滑到「市场」子页
      final g1 = await begin(tester, extBody);
      await g1.moveBy(const Offset(-300, 0));
      await tester.pump();
      await g1.up();
      await tester.pumpAndSettle();
      expect(find.text('搜名称 / 简介 / 作者'), findsOneWidget);
      expect(shownPage(tester), 1, reason: '还在拓展页，只是子页切了');

      // 继续向下一格方向拖：主界面滑向「我的」页
      final g2 = await begin(tester, extBody);
      await g2.moveBy(const Offset(-300, 0));
      await tester.pump();
      expect(shownPage(tester), 2, reason: '「我的」页滑到眼前');
      await g2.up();
      await tester.pumpAndSettle();
      expect(shownPage(tester), 2, reason: '松手落位「我的」页');
    });

    testWidgets('一次拖动穿三层：市场 → 我的（子页）→ 工具页', (tester) async {
      await pumpExtShell(tester);
      await tester.tap(find.text('拓展'));
      await tester.pumpAndSettle();

      final g1 = await begin(tester, extBody);
      await g1.moveBy(const Offset(-300, 0));
      await g1.up();
      await tester.pumpAndSettle();
      expect(find.text('搜名称 / 简介 / 作者'), findsOneWidget);

      // 反方向一把拖过一屏多：子页市场→我的，越界后主界面工具页进来
      final g2 = await begin(tester, extBody);
      await g2.moveBy(const Offset(1100, 0));
      await tester.pump();
      expect(shownPage(tester), 0, reason: '一路滑到了工具页');
      await g2.up();
      await tester.pumpAndSettle();
      expect(shownPage(tester), 0);
    });

    testWidgets('越界后拖回来松手：就近弹回拓展页，不误切', (tester) async {
      await pumpExtShell(tester);
      await tester.tap(find.text('拓展'));
      await tester.pumpAndSettle();

      final g = await begin(tester, extBody);
      await g.moveBy(const Offset(200, 0)); // 越界约 0.4 格
      await tester.pump();
      await g.moveBy(const Offset(-200, 0)); // 拖回来
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(shownPage(tester), 1, reason: '拖回来了就留在拓展页');
      expect(find.text('还没有拓展'), findsOneWidget);
    });

    testWidgets('越界方向快甩借一格：直接落到工具页', (tester) async {
      await pumpExtShell(tester);
      await tester.tap(find.text('拓展'));
      await tester.pumpAndSettle();

      await tester.flingFrom(extBody, const Offset(200, 0), 3000);
      await tester.pumpAndSettle();
      expect(shownPage(tester), 0, reason: '快甩借一格，落到工具页');
    });

    testWidgets('界内镜像不锚定主界面：切页弹簧半路拖子页不会拽回上一格', (tester) async {
      await pumpExtShell(tester);
      // 直接驱动桥（拓展页手势的另一端）：手势时序版要拿捏弹簧半路的那几十毫秒，
      // 太脆；守卫的语义是「over=0 且从未越界 → 整体跳过」，按谓词直接测。
      // 若不跳过，切页弹簧半路（_pos 非整格）时的界内镜像会被照单锚定，
      // round 把 tab 拽回上一格、掐断切页动画。
      final host = NavSwipeScope.of(tester.element(find.text('页面工具')))!;
      int navIndex() => tester.widget<GlassNavBar>(find.byType(GlassNavBar)).index;
      expect(navIndex(), 0);

      // 从未越界：界内镜像与松手落位都是空操作
      host.navDragOver(0);
      await tester.pump();
      expect(navIndex(), 0, reason: '界内镜像不该换格');
      host.navDragEnd(-3000);
      await tester.pumpAndSettle();
      expect(navIndex(), 0, reason: '没越界过的快甩也不借格');

      // 真越界过的：拖回来（over=0）要照常同步回弹
      host.navDragOver(0.6);
      await tester.pump();
      expect(navIndex(), 1, reason: '越界中拖过半，实时换格');
      host.navDragOver(0);
      await tester.pump();
      expect(navIndex(), 0, reason: '拖回界内越界量归零，主界面跟着回');
      host.navDragEnd(0);
      await tester.pumpAndSettle();
      expect(navIndex(), 0);
    });
  });
}

PluginRegistry _plainRegistry() => PluginRegistry(
      features: const [_Page('timetable', '课程表', 10), _Page('ecard', '校园码', 20)],
      themes: const [GlassTheme()],
    );

/// 第一格顶部带一条横向列表（高 200），下方留白——用来区分「冲突」与「不冲突」
PluginRegistry _registryWithHorizontalStrip() => PluginRegistry(
      features: const [
        _Page('timetable', '课程表', 10, horizontalStrip: true),
        _Page('ecard', '校园码', 20),
      ],
      themes: const [GlassTheme()],
    );

class _Page extends FeaturePlugin {
  const _Page(this.id, this.label, this.order, {this.horizontalStrip = false});

  @override
  final String id;
  final String label;
  final int order;
  final bool horizontalStrip;

  @override
  String get name => '插件$id';
  @override
  String get description => '测试插件';

  @override
  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) => [
        PluginNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: label,
          order: order,
          build: (_) => horizontalStrip
              ? Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < 20; i++)
                            Container(width: 120, alignment: Alignment.center, child: Text('卡片$i')),
                        ],
                      ),
                    ),
                    Expanded(child: Center(child: Text('页面$label'))),
                  ],
                )
              : Center(child: Text('页面$label')),
        ),
      ];
}
