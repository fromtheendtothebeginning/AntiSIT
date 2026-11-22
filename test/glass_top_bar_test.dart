import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 悬浮玻璃顶栏的基础契约：真 AppBar（系统行为不变）+ 渐变模糊背景 + 圆钮按钮。
void main() {
  Widget host({required Widget child}) => MaterialApp(
        home: child,
      );

  Widget page({Widget? title, List<Widget>? actions, PreferredSizeWidget? bottom}) {
    return Builder(
      builder: (context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: glassAppBar(
          context,
          title: title ?? const Text('标题'),
          actions: actions,
          bottom: bottom,
        ),
        body: ListView(
          padding: EdgeInsets.only(top: glassTopInset(context)),
          children: const [SizedBox(height: 800)],
        ),
      ),
    );
  }

  testWidgets('顶栏仍是 AppBar，高度包含渐变模糊段', (tester) async {
    await tester.pumpWidget(host(child: page()));
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    // 模糊区只占顶栏本身：顶栏高度 = 标题栏高度
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
  });

  testWidgets('背景带是渐变模糊（多层 BackdropFilter 叠加）', (tester) async {
    await tester.pumpWidget(host(child: page()));
    // 渐变段被切成若干层模糊叠出来，至少 2 层
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackdropFilter),
      ),
      findsAtLeastNWidgets(2),
    );
  });

  testWidgets('图标按钮套成玻璃圆钮（不再叠第二层模糊）', (tester) async {
    await tester.pumpWidget(host(
      child: page(actions: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.refresh), tooltip: '刷新'),
      ]),
    ));
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
          child: Builder(builder: (context) {
            inset = glassTopInset(context);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    expect(inset, 24 + kToolbarHeight);
  });
}
