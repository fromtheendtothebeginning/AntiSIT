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
  List<PluginNavItem> navItems(
    PluginRegistry registry,
    ValueListenable<int> tab,
  ) => [
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

  testWidgets('工具页长按卡片进入整理态，拖动换位并落到本地', (tester) async {
    AppState.I.demo = true;
    await tester.pumpWidget(MaterialApp(home: ToolsPage()));
    await tester.pumpAndSettle();

    final g = await tester.startGesture(tester.getCenter(find.text('工具甲')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('card-size-bar')),
      findsOneWidget,
      reason: '长按进入整理态，顶部出现尺寸条',
    );
    expect(find.textContaining('卡片大小'), findsOneWidget);

    // 先竖向挪一点，让方向锁定在「换位置」上（横向会变成改尺寸）
    await g.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 30));
    await g.moveTo(tester.getCenter(find.text('工具乙')));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pumpAndSettle();

    expect(PluginRegistry.I.toolCards.map((t) => t.title), ['工具乙', '工具甲']);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('plugin_tool_order'), ['ecard', 'timetable']);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('card-size-bar')), findsNothing);
    AppState.I.demo = false;
  });

  testWidgets('工具卡片拖右下角手柄：按拖出来的宽高吸附到最近一档', (tester) async {
    AppState.I.demo = true;
    await tester.pumpWidget(MaterialApp(home: ToolsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('整理卡片'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('整理卡片'), findsNothing, reason: '整理态标题栏换成「完成」');

    final before = tester.getSize(
      find.byKey(const ValueKey<String>('fgrid:timetable')),
    );
    // 只往左拖一档（32px 就够）：2×3 往左按「大小顺序」缩一档 = 2×2 竖卡
    await tester.drag(
      find.byKey(const ValueKey<String>('fgrid-handle:timetable')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();

    expect(PluginRegistry.I.toolSize('timetable'), GridCardSize.tall);
    final after = tester.getSize(
      find.byKey(const ValueKey<String>('fgrid:timetable')),
    );
    expect(after.width, lessThan(before.width * 0.7), reason: '从半屏宽缩成 1/3 屏宽');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('plugin_tool_sizes'), contains('"timetable":"2x2"'));

    // 点列表下方的空白也退出整理（不只是点卡片缝里）
    await tester.tapAt(const Offset(400, 520));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('card-size-bar')), findsNothing);
    AppState.I.demo = false;
  });

  testWidgets('顶部尺寸条：1×1 / 1×3 / 2×3 / 2×2 直接切换并落到本地', (tester) async {
    AppState.I.demo = true;
    await tester.pumpWidget(MaterialApp(home: ToolsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('整理卡片'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('card-size-bar')), findsOneWidget);
    expect(find.text('卡片大小 · 2×3'), findsOneWidget, reason: '默认选中第一张工具');

    final first = tester.getSize(
      find.byKey(const ValueKey<String>('fgrid:timetable')),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('card-size-option:1x1')),
    );
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.toolSize('timetable'), GridCardSize.single);
    expect(find.text('卡片大小 · 1×1'), findsOneWidget);
    final tiny = tester.getSize(
      find.byKey(const ValueKey<String>('fgrid:timetable')),
    );
    expect(tiny.height, lessThan(first.height), reason: '1x1 只有一行高');
    expect(tiny.width, lessThan(first.width / 2), reason: '1x1 只占 1 列');

    await tester.tap(
      find.byKey(const ValueKey<String>('card-size-option:1x3')),
    );
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.toolSize('timetable'), GridCardSize.wide);

    await tester.tap(
      find.byKey(const ValueKey<String>('card-size-option:2x2')),
    );
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.toolSize('timetable'), GridCardSize.tall);

    await tester.tap(
      find.byKey(const ValueKey<String>('card-size-option:2x3')),
    );
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.toolSize('timetable'), GridCardSize.standard);

    final sp = await SharedPreferences.getInstance();
    expect(
      sp.getString('plugin_tool_sizes'),
      isNull,
      reason: '改回默认 2×3 后不残留条目',
    );
    AppState.I.demo = false;
  });

  testWidgets('窄屏（360）上 1x1 / 1x3 / 2x2 三种工具卡片都不溢出', (tester) async {
    AppState.I.demo = true;
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    PluginRegistry.I = PluginRegistry(
      features: const [
        _Fake('timetable', '课程表', 10, toolTitle: '工具甲'),
        _Fake('ecard', '校园码', 20, toolTitle: '工具乙'),
        _Fake('extra', '额外', 30, toolTitle: '工具丙'),
      ],
      themes: const [GlassTheme()],
    );
    await PluginRegistry.I.setToolSize('timetable', GridCardSize.single);
    await PluginRegistry.I.setToolSize('ecard', GridCardSize.wide);
    await PluginRegistry.I.setToolSize('extra', GridCardSize.tall);

    await tester.pumpWidget(const MaterialApp(home: ToolsPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '1x1 / 1x3 / 2x2 卡片内容不能溢出');
    // 1x1 只画图标（放名字会被截断），所以这一张按卡片 key 断言
    expect(
      find.byKey(const ValueKey<String>('fgrid:timetable')),
      findsOneWidget,
    );
    expect(find.text('工具甲'), findsNothing, reason: '1x1 这档只显示图标');
    expect(find.text('工具乙'), findsOneWidget);
    expect(find.text('工具丙'), findsOneWidget);
    expect(find.text('副标题'), findsNWidgets(2), reason: '1x1 这档不显示副标题');
    AppState.I.demo = false;
  });

  testWidgets('管理页把启停的效果直接显示出来（底栏 / 工具宫格）', (tester) async {
    // 图卡片变高后，默认 600 高的视口里功能列表在惰性构建窗口之外
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
