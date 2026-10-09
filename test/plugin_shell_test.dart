import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/home_page.dart';
import 'package:campus_service/pages/plugin_manager_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_tools/plugin_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只贡献导航页 / 工具卡片的假插件——不把真实页面拉进壳层测试。
class _Fake extends FeaturePlugin {
  const _Fake(this.id, this.label, this.order, {this.toolTitle});

  @override
  final String id;
  final String label;
  final int order;
  final String? toolTitle;

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
          build: (_) => Center(child: Text('页面$label')),
        ),
      ];

  @override
  List<PluginTool> tools(PluginRegistry registry) => toolTitle == null
      ? const []
      : [
          PluginTool(
            icon: Icons.build,
            color: Colors.blue,
            title: toolTitle!,
            subtitle: () => '副标题',
            open: () => const SizedBox.shrink(),
          ),
        ];
}

PluginRegistry _registry() => PluginRegistry(
      features: const [
        _Fake('timetable', '课程表', 10, toolTitle: '工具甲'),
        _Fake('ecard', '校园码', 20, toolTitle: '工具乙'),
        _Fake('tools', '工具', 30),
      ],
      themes: const [GlassTheme()],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PluginRegistry.I = _registry();
    AppState.I.demo = false;
  });

  testWidgets('启停插件后底栏立刻跟着变，不用重启也不用重进页面', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.text('课程表'), findsOneWidget);
    expect(find.text('校园码'), findsOneWidget);
    // IndexedStack 里非当前页是 offstage 的，要显式跳过 offstage 检查
    expect(find.text('页面校园码', skipOffstage: false), findsOneWidget);

    await PluginRegistry.I.disable('ecard');
    await tester.pumpAndSettle();

    expect(find.text('校园码'), findsNothing);
    expect(find.text('页面校园码', skipOffstage: false), findsNothing);
    expect(find.text('课程表'), findsOneWidget);
  });

  testWidgets('工具宫格跟着注册表变：停用插件后卡片立刻消失', (tester) async {
    AppState.I.demo = true; // LoginGate 放行，不必真登录
    await tester.pumpWidget(MaterialApp(home: ToolsPage()));
    await tester.pumpAndSettle();
    expect(find.text('工具甲'), findsOneWidget);
    expect(find.text('工具乙'), findsOneWidget);

    await PluginRegistry.I.disable('ecard');
    await tester.pumpAndSettle();
    expect(find.text('工具乙'), findsNothing);
    expect(find.text('工具甲'), findsOneWidget);
    AppState.I.demo = false;
  });

  testWidgets('工具排序：排完立刻生效，并落到本地', (tester) async {
    AppState.I.demo = true;
    await tester.pumpWidget(MaterialApp(home: ToolsPage()));
    await tester.pumpAndSettle();

    double leftOf(String title) => tester.getTopLeft(find.text(title)).dx;
    expect(leftOf('工具甲'), lessThan(leftOf('工具乙'))); // 初始按清单顺序

    // 排序弹层存在（两个以上工具才有这个入口）
    expect(find.byTooltip('排序'), findsOneWidget);

    await PluginRegistry.I.setToolOrder(const ['ecard']);
    await tester.pumpAndSettle();
    expect(leftOf('工具乙'), lessThan(leftOf('工具甲')), reason: '排过的插件要排到前面');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('plugin_tool_order'), ['ecard']);
    AppState.I.demo = false;
  });

  testWidgets('拖拽手柄能改顺序：松手立刻生效并落到本地', (tester) async {
    AppState.I.demo = true;
    await tester.pumpWidget(MaterialApp(home: ToolOrderPage()));
    await tester.pumpAndSettle();

    double topOf(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(topOf('工具甲'), lessThan(topOf('工具乙')));

    // 按住第一行右侧手柄往下拖过第二行
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(topOf('工具乙'), lessThan(topOf('工具甲')), reason: '拖到下面后顺序应该换过来');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('plugin_tool_order'), ['ecard', 'timetable']);
    AppState.I.demo = false;
  });

  testWidgets('管理页把启停的效果直接显示出来（底栏 / 工具宫格）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PluginManagerPage()));
    await tester.pumpAndSettle();
    expect(find.text('课程表 · 校园码 · 工具'), findsOneWidget);
    expect(find.textContaining('2 个：工具甲 · 工具乙'), findsOneWidget);

    await PluginRegistry.I.disable('tools');
    await tester.pumpAndSettle();
    expect(find.text('课程表 · 校园码'), findsOneWidget);
    expect(find.text('已停用'), findsWidgets); // 停用的行有明确标记

    await PluginRegistry.I.disable('ecard');
    await tester.pumpAndSettle();
    expect(find.text('课程表'), findsOneWidget);
    expect(find.textContaining('1 个：工具甲'), findsOneWidget);
  });
}
