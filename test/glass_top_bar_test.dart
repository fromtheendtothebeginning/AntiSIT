import 'package:campus_core/campus_core.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 悬浮玻璃顶栏的基础契约：真 AppBar（系统行为不变）+ 渐变模糊背景 + 圆钮按钮。
void main() {
  Widget host({required Widget child}) => MaterialApp(home: child);

  Widget page({
    Widget? title,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    return Builder(
      builder: (context) {
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: title ?? const Text('标题'),
            actions: actions,
            bottom: bottom,
          ),
          body: ListView(
            padding: EdgeInsets.only(top: topInset),
            children: const [SizedBox(height: 800)],
          ),
        );
      },
    );
  }

  testWidgets('顶栏仍是 AppBar，高度包含渐变模糊段', (tester) async {
    await tester.pumpWidget(host(child: page()));
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    // 模糊区只占顶栏本身：顶栏高度 = 标题栏高度
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
  });

  testWidgets('背景是纯渐变遮罩，没有任何实时模糊', (tester) async {
    await tester.pumpWidget(host(child: page()));
    // 方案 B：只有色带、不画 backdrop——滚动/overscroll/切页都不可能出重影与噪点
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets('顶栏色带真的生效：红色内容穿过标题行也会被底色盖住', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Builder(
            builder: (context) {
              final topInset = glassTopInset(context);
              return Scaffold(
                extendBodyBehindAppBar: glassTopBarEnabled,
                appBar: glassAppBar(context, title: const Text('标题')),
                // 纯红 body：色带生效的话，标题行几乎看不到红
                body: ColoredBox(
                  color: const Color(0xFFFF0000),
                  child: SizedBox(height: topInset + 400),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    final w = boundary.size.width.round();
    int red(int x, int y) => bytes!.getUint8((y * w + x) * 4);
    int green(int x, int y) => bytes!.getUint8((y * w + x) * 4 + 1);
    int blue(int x, int y) => bytes!.getUint8((y * w + x) * 4 + 2);

    // 标题行（顶栏 50% 处）：色带 alpha ≈0.95 → 红色只剩 5%，绿蓝仍是浅底色的高值
    final cx = w ~/ 2;
    expect(green(cx, kToolbarHeight ~/ 2), greaterThan(120), reason: '色带未覆盖标题行：内容透出来了');
    expect(blue(cx, kToolbarHeight ~/ 2), greaterThan(120), reason: '色带未覆盖标题行：内容透出来了');

    // 顶栏底边：色带已透明、内容渐隐 mask 也接近 1 → 应看得到红
    expect(red(cx, kToolbarHeight.round() - 3), greaterThan(200), reason: '顶栏底边应完全透明');
  });
  testWidgets('应用内切深色/浅色：顶栏色带立即换色，不用重启', (tester) async {
    addTearDown(() => SemColors.p = GlassPalette.light);
    SemColors.p = GlassPalette.light;
    await tester.pumpWidget(host(child: page()));

    Color barTopColor() {
      // 色带 = GlassBarScrim 里那层线性渐变（它在 AppBar 外面，铺满整个顶栏）
      final boxes = find.descendant(
        of: find.byType(GlassBarScrim),
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient is LinearGradient,
        ),
      );
      final box = tester.widget<DecoratedBox>(boxes.first);
      final g = (box.decoration as BoxDecoration).gradient! as LinearGradient;
      return g.colors.first;
    }

    final light = barTopColor();
    // 色带是 const 组件，页面重建时会被跳过——必须靠订阅色板自己重画，
    // 否则应用内切深浅色后顶栏还是旧色，要重启才生效。
    SemColors.p = GlassPalette.dark;
    await tester.pump();
    final dark = barTopColor();
    expect(dark, isNot(light), reason: '切到深色后色带要立刻换成深色底');
    expect(dark.a, greaterThan(0), reason: '色带仍要有底色（只是透明度较低）');
  });
  testWidgets('图标按钮套成玻璃圆钮（不再叠第二层模糊）', (tester) async {
    await tester.pumpWidget(
      host(
        child: page(
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
            ),
          ],
        ),
      ),
    );
    // 圆钮 = 40 直径的「更实一档」玻璃面；BackdropFilter 只留给顶栏背景那一层，
    // 圆钮里再套一层会在 Impeller 下产生椭圆光晕
    final face = find.ancestor(
      of: find.byTooltip('刷新'),
      matching: find.byType(Container),
    );
    expect(face, findsAtLeastNWidgets(1));
    expect(tester.getSize(face.first), const Size(40, 40));
    expect(
      find.descendant(of: face.first, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
  });

  testWidgets('标题靠左对齐（不再居中）', (tester) async {
    await tester.pumpWidget(host(child: page()));
    final width = tester.getSize(find.byType(Scaffold)).width;
    final titleLeft = tester.getTopLeft(find.text('标题')).dx;
    expect(titleLeft, lessThan(width / 2 - 20), reason: '标题应靠左，不再是居中');
    expect(titleLeft, lessThan(80), reason: '左对齐时标题应贴近左边距（约 titleSpacing）');
  });

  testWidgets('悬浮顶栏关掉：glassTopBarAction 不再套玻璃圆钮', (tester) async {
    addTearDown(() => AppState.I.glassTopBar = true);
    AppState.I.glassTopBar = false;
    await tester.pumpWidget(
      host(child: Builder(builder: (context) => glassTopBarAction(const Text('动作')))),
    );
    // 只剩页面底色，没有 40 圆片那层 Container
    expect(find.byType(Text), findsOneWidget);
    expect(tester.getSize(find.byType(Text)), isNot(const Size(40, 40)));
    final container = find.ancestor(of: find.text('动作'), matching: find.byType(Container));
    expect(container, findsNothing, reason: '关掉开关后不该再包圆钮');
  });
  testWidgets('能 pop 的页面自动补圆钮返回键；根页面不给', (tester) async {
    await tester.pumpWidget(host(child: page()));
    expect(find.byType(BackButton), findsNothing);

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: page()));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => page()));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('glassTopInset 按状态栏 + 标题栏 + 渐变段算', (tester) async {
    late double inset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(top: 24)),
          child: Builder(
            builder: (context) {
              inset = glassTopInset(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(inset, 24 + kToolbarHeight);
  });

  testWidgets('外观开关关掉 → 退回普通 AppBar、不再留顶栏内边距', (tester) async {
    AppState.I.glassTopBar = false;
    addTearDown(() => AppState.I.glassTopBar = true);

    await tester.pumpWidget(host(child: page()));
    expect(find.byType(AppBar), findsOneWidget);
    // 没有渐变模糊层
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(GlassBarScrim), findsNothing);
    // 内边距归零：内容排到普通 AppBar 下面，不再额外让位
    late double inset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(top: 24)),
          child: Builder(
            builder: (context) {
              inset = glassTopInset(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(inset, 0);
  });
}
