import 'package:campus_service/pages/plugin_manager_page.dart';
import 'package:campus_core/campus_core.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_theme_ink/plugin_theme_ink.dart';
import 'package:campus_service/widgets/plugin_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理界面的被测插件：依赖链为 b → a → lib，net 是核心插件。
class _Fake extends FeaturePlugin {
  const _Fake(this.id, {this.deps = const [], this.core = false});

  @override
  final String id;
  final List<String> deps;
  final bool core;

  @override
  String get name => '插件$id';
  @override
  String get description => '说明 $id';
  @override
  List<String> get dependencies => deps;
  @override
  bool get removable => !core;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PluginRegistry.I = PluginRegistry(
      features: const [
        _Fake('net', core: true),
        _Fake('lib'),
        _Fake('a', deps: ['lib']),
        _Fake('b', deps: ['a']),
      ],
      themes: const [GlassTheme(), InkTheme()],
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PluginManagerPage()));
    await tester.pumpAndSettle();
  }

  Finder switchTile(String name) => find.widgetWithText(SwitchListTile, name);

  testWidgets('核心插件没有开关，普通插件有', (tester) async {
    await pumpPage(tester);
    expect(tester.widget<SwitchListTile>(switchTile('插件net')).onChanged, isNull);
    expect(tester.widget<SwitchListTile>(switchTile('插件a')).onChanged, isNotNull);
    expect(find.text('4/4 已启用'), findsOneWidget);
  });

  testWidgets('停用有下游的插件要先确认，取消则一点都不变', (tester) async {
    await pumpPage(tester);
    await tester.tap(switchTile('插件a'));
    await tester.pumpAndSettle();

    expect(find.text('连带停用'), findsOneWidget);
    expect(find.textContaining('插件b'), findsWidgets);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.isEnabled('a'), isTrue);
    expect(PluginRegistry.I.isEnabled('b'), isTrue);
  });

  testWidgets('确认后连带停用下游，上游与核心插件不受影响', (tester) async {
    await pumpPage(tester);
    await tester.tap(switchTile('插件a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一并停用'));
    await tester.pumpAndSettle();

    expect(PluginRegistry.I.isEnabled('a'), isFalse);
    expect(PluginRegistry.I.isEnabled('b'), isFalse);
    expect(PluginRegistry.I.isEnabled('lib'), isTrue);
    expect(PluginRegistry.I.isEnabled('net'), isTrue);
  });

  testWidgets('启用插件会把它的硬依赖一起打开', (tester) async {
    await PluginRegistry.I.disable('lib'); // 连带 a、b 一起停
    expect(PluginRegistry.I.isEnabled('b'), isFalse);

    await pumpPage(tester);
    await tester.tap(switchTile('插件b'));
    await tester.pumpAndSettle();

    expect(PluginRegistry.I.isEnabled('a'), isTrue);
    expect(PluginRegistry.I.isEnabled('lib'), isTrue);
    expect(find.textContaining('并连带启用依赖'), findsOneWidget);
  });

  testWidgets('点关系图里的节点会显示依赖详情', (tester) async {
    await pumpPage(tester);
    final node = find.descendant(
        of: find.byType(PluginGraphView), matching: find.text('插件lib'));
    await tester.tap(node);
    await tester.pumpAndSettle();

    // 详情面板里的那一行（列表条目的副标题是「说明 lib\n被 插件a 依赖」，不参与精确匹配）
    expect(find.text('被 插件a 依赖'), findsOneWidget);
  });

  testWidgets('主题插件可以直接切换', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.widgetWithText(ListTile, '墨白极简'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.theme.id, InkTheme.themeId);
  });

  testWidgets('清单写错时顶部给出告警，页面其余部分照常可用', (tester) async {
    PluginRegistry.I = PluginRegistry(features: const [
      _Fake('a', deps: ['ghost']),
    ]);
    await pumpPage(tester);
    expect(find.text('插件清单有问题'), findsOneWidget);
    expect(find.textContaining('依赖了不存在的插件：ghost'), findsOneWidget);
    expect(switchTile('插件a'), findsOneWidget);
  });

  testWidgets('手机尺寸（400×800）下不溢出、能滚到底', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: PluginManagerPage(),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('主题插件'), findsOneWidget);
  });

  // 曾经的问题：画布（332 逻辑宽）比卡片宽，右边那几列（网络与登录 / 主题）被裁在框外，
  // 首屏看不出图有多大、也不知道能拖。现在 FittedBox 会先把整张图缩到装得下。
  testWidgets('画布比视口宽时，最左最右两列都落在框内', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final graph = PluginGraph.fromRegistry(PluginRegistry.I);
    final layout = PluginGraphLayout.compute(graph);
    const viewport = Size(300, 260);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: PluginGraphView(graph: graph, layout: layout),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(layout.size.width, greaterThan(viewport.width), reason: '这个用例要在「画布比视口宽」时才有效');
    final box = tester.getRect(find.byType(PluginGraphView));
    Rect node(String label) => tester.getRect(find
        .ancestor(
          of: find.descendant(
              of: find.byType(PluginGraphView), matching: find.text(label)),
          matching: find.byType(GestureDetector),
        )
        .first);

    expect(node('插件b').left, greaterThanOrEqualTo(box.left - 0.5)); // 最左列（依赖最深）
    expect(node('插件lib').right, lessThanOrEqualTo(box.right + 0.5)); // 最右列（基础插件）
  });

  testWidgets('视口装得下时保持原始大小（不无故放大）', (tester) async {
    final graph = PluginGraph.fromRegistry(PluginRegistry.I);
    final layout = PluginGraphLayout.compute(graph);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: layout.size.width + 40,
            height: layout.size.height + 40,
            child: PluginGraphView(graph: graph, layout: layout),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final card = tester.getRect(find
        .ancestor(
          of: find.descendant(
              of: find.byType(PluginGraphView), matching: find.text('插件lib')),
          matching: find.byType(GestureDetector),
        )
        .first);
    expect(card.width, closeTo(PluginGraphLayout.nodeW, 0.5));
  });
}
