import 'package:campus_core/campus_core.dart';
import 'package:campus_service/plugins/bootstrap.dart';
import 'package:plugin_theme_bamboo/plugin_theme_bamboo.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_theme_ink/plugin_theme_ink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用插件：只有 id / 依赖 / 几个贡献点，不拉任何真实页面。
class _Fake extends FeaturePlugin {
  const _Fake(
    this.id, {
    this.deps = const [],
    this.opt = const [],
    this.core = false,
    this.navOrder,
    this.tool = false,
    this.tiles = const [],
    this.settingsOrder = 50,
  });

  @override
  final String id;
  final List<String> deps;
  final List<String> opt;
  final bool core;
  final int? navOrder;
  final bool tool;

  /// 贡献的设置条目（用文字代替真实控件，便于断言顺序）。
  final List<String> tiles;

  @override
  final int settingsOrder;

  @override
  String get name => 'P-$id';
  @override
  String get description => '测试插件 $id';
  @override
  List<String> get dependencies => deps;
  @override
  List<String> get optionalDependencies => opt;
  @override
  bool get removable => !core;

  @override
  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) =>
      navOrder == null
          ? const []
          : [
              PluginNavItem(
                icon: Icons.tab,
                activeIcon: Icons.tab,
                label: id,
                order: navOrder!,
                build: (_) => const SizedBox.shrink(),
              ),
            ];

  @override
  List<PluginTool> tools(PluginRegistry registry) => tool
      ? [
          PluginTool(
            icon: Icons.build,
            color: Colors.blue,
            title: '工具-$id',
            subtitle: () => '副标题-$id',
            open: () => const SizedBox.shrink(),
          ),
        ]
      : const [];

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) =>
      [for (final t in tiles) Text(t)];
}

void main() {
  // 「真实清单」= 宿主按 pubspec 依赖组装出来的那份（生成器产出的 manifest.g.dart）
  final features = buildAppRegistry().features;
  final themes = buildAppRegistry().themes;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('清单自检', () {
    test('真实清单：id 不重复、依赖都存在、硬依赖无环', () {
      expect(PluginRegistry.validate(features), isEmpty);
      expect(features, isNotEmpty);
    });

    test('核心插件不会被构建开关剔掉，且都在清单里', () {
      final ids = features.map((p) => p.id).toSet();
      expect(ids, containsAll(['network', 'profile']));
      expect(features.where((p) => !p.removable).length, 2);
    });

    test('基础设施按 id 引用的插件确实在清单里（防止字符串写错后静默失效）', () {
      // ai_vision.dart: PluginRegistry.I.isEnabled('ai')
      // class_reminder_service.dart: PluginRegistry.I.isEnabled('reminder')
      final ids = features.map((p) => p.id).toSet();
      expect(ids, contains('ai'));
      expect(ids, contains('reminder'));
    });

    test('默认主题在主题清单里', () {
      final registry = buildAppRegistry();
      expect(registry.themes.any((t) => t.id == registry.defaultThemeId), isTrue);
      expect(registry.theme.id, GlassTheme.themeId);
    });

    test('能抓出重复 id', () {
      expect(PluginRegistry.validate(const [_Fake('a'), _Fake('a')]),
          contains('插件 id 重复：a'));
    });

    test('能抓出依赖不存在的插件', () {
      final problems = PluginRegistry.validate(const [_Fake('a', deps: ['ghost'])]);
      expect(problems.single, contains('依赖了不存在的插件：ghost'));
    });

    test('能抓出硬依赖成环，并给出环路径', () {
      const features = [_Fake('a', deps: ['b']), _Fake('b', deps: ['a'])];
      expect(PluginRegistry.validate(features).single, startsWith('硬依赖成环：'));
      expect(PluginRegistry.hardCycles(features).single.length, 3); // a → b → a
    });

    test('软依赖指向不存在的插件不报错（软依赖就该允许缺席）', () {
      expect(PluginRegistry.validate(const [_Fake('a', opt: ['ghost'])]), isEmpty);
    });
  });

  group('依赖联动', () {
    const chain = [
      _Fake('lib'),
      _Fake('mid', deps: ['lib']),
      _Fake('top', deps: ['mid']),
    ];

    test('停用会被下游连带停掉，但不动上游与无关插件', () async {
      final r = PluginRegistry(features: [...chain, const _Fake('other')]);
      final off = await r.disable('lib');
      expect(off.toSet(), {'lib', 'mid', 'top'});
      expect(r.isEnabled('other'), isTrue);
    });

    test('enable 会把硬依赖闭包一起打开', () async {
      final r = PluginRegistry(features: chain);
      await r.disable('lib');
      expect(r.enabled, isEmpty);
      final turned = await r.enable('top');
      expect(turned.toSet(), {'top', 'mid', 'lib'});
      expect(r.enabled.length, 3);
    });

    test('disableClosure 只列下游，不含自身', () async {
      final r = PluginRegistry(features: chain);
      expect(r.disableClosure('lib').toSet(), {'mid', 'top'});
      expect(r.disableClosure('top'), isEmpty);
      expect(r.dependentsOf('lib'), ['mid']);
    });

    test('软依赖不参与启停联动', () async {
      final r = PluginRegistry(features: const [_Fake('base'), _Fake('deco', opt: ['base'])]);
      expect(r.disableClosure('base'), isEmpty);
      await r.disable('base');
      expect(r.isEnabled('deco'), isTrue);
    });

    test('核心插件停不掉，enable/disable 都返回空', () async {
      final r = PluginRegistry(features: const [_Fake('core', core: true)]);
      expect(await r.disable('core'), isEmpty);
      expect(r.isEnabled('core'), isTrue);
      expect(await r.enable('core'), isEmpty);
    });

    test('未知 id 不报错', () async {
      final r = PluginRegistry(features: const [_Fake('a')]);
      expect(await r.enable('ghost'), isEmpty);
      expect(await r.disable('ghost'), isEmpty);
      expect(r.isEnabled('ghost'), isFalse);
    });
  });

  group('贡献点汇集', () {
    const fakes = [
      _Fake('nav-c', navOrder: 30),
      _Fake('nav-a', navOrder: 10),
      _Fake('nav-b', navOrder: 20),
      _Fake('tool-1', tool: true),
      _Fake('tile-late', tiles: ['晚'], settingsOrder: 70),
      _Fake('tile-early', tiles: ['早'], settingsOrder: 30),
    ];

    test('底栏页面按 order 排序，停用后消失', () async {
      final r = PluginRegistry(features: fakes);
      final tab = ValueNotifier<int>(0);
      expect(r.navPages(tab).map((e) => e.$2.label), ['nav-a', 'nav-b', 'nav-c']);
      await r.disable('nav-b');
      expect(r.navPages(tab).map((e) => e.$2.label), ['nav-a', 'nav-c']);
    });

    test('工具卡片只来自已启用的插件', () async {
      final r = PluginRegistry(features: fakes);
      expect(r.toolCards.map((t) => t.title), ['工具-tool-1']);
      await r.disable('tool-1');
      expect(r.toolCards, isEmpty);
    });

    testWidgets('设置条目按 settingsOrder 排序，停用后消失', (tester) async {
      final r = PluginRegistry(features: fakes);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));
      expect(r.settingsTiles(ctx).map((w) => (w as Text).data), ['早', '晚']);
      await r.disable('tile-early');
      expect(r.settingsTiles(ctx).map((w) => (w as Text).data), ['晚']);
    });
  });

  group('持久化与自愈', () {
    const fakeFeatures = [
      _Fake('lib'),
      _Fake('mid', deps: ['lib']),
      _Fake('core', core: true),
    ];

    /// 主题相关行为要带上真实主题包（core 自己不认识任何主题）。
    PluginRegistry make() => PluginRegistry(features: fakeFeatures, themes: themes);

    test('启停与主题往返', () async {
      final a = make();
      await a.disable('lib');
      await a.setTheme(InkTheme.themeId);

      final b = make();
      await b.load();
      expect(b.isEnabled('lib'), isFalse);
      expect(b.isEnabled('mid'), isFalse); // 连带
      expect(b.theme.id, InkTheme.themeId);
      expect(b.loaded, isTrue);
    });

    test('已删插件留下的记录 / 未知主题被忽略，回落到默认主题', () async {
      SharedPreferences.setMockInitialValues({
        'plugin_disabled': ['ghost', 'core'],
        'plugin_theme': 'theme.ghost',
      });
      final r = make();
      await r.load();
      expect(r.enabled.length, 3, reason: 'ghost 忽略、core 核心不可停');
      expect(r.theme.id, GlassTheme.themeId);
    });

    test('启用的插件其硬依赖关着（旧数据）时，load 会把它一起关掉', () async {
      SharedPreferences.setMockInitialValues({
        'plugin_disabled': ['lib'],
      });
      final r = make();
      await r.load();
      expect(r.isEnabled('mid'), isFalse);
    });

    test('setTheme 不认识的 id 是空操作', () async {
      final r = make();
      await r.setTheme('theme.ghost');
      expect(r.theme.id, GlassTheme.themeId);
    });
  });

  group('工具排序', () {
    const fakes = [_Fake('a', tool: true), _Fake('b', tool: true), _Fake('c', tool: true)];

    test('默认按清单（pubspec 依赖）顺序', () {
      final r = PluginRegistry(features: fakes);
      expect(r.toolCards.map((t) => t.title), ['工具-a', '工具-b', '工具-c']);
    });

    test('排过序的按用户顺序，没排到的排在后面且保持原有相对顺序', () async {
      final r = PluginRegistry(features: fakes);
      await r.setToolOrder(const ['c', 'a']);
      expect(r.toolCards.map((t) => t.title), ['工具-c', '工具-a', '工具-b']);
    });

    test('元素相同只是换了顺序，也要真的存下去（回归）', () async {
      final r = PluginRegistry(features: fakes);
      await r.setToolOrder(const ['b', 'a', 'c']);
      expect(r.toolCards.map((t) => t.title), ['工具-b', '工具-a', '工具-c']);
    });

    test('持久化；已删插件残留的 id 被忽略', () async {
      final a = PluginRegistry(features: fakes);
      await a.setToolOrder(const ['c', 'b', 'a', 'ghost']);
      final b = PluginRegistry(features: fakes);
      await b.load();
      expect(b.toolCards.map((t) => t.title), ['工具-c', '工具-b', '工具-a']);
    });

    test('清空顺序 = 回到清单顺序', () async {
      final r = PluginRegistry(features: fakes);
      await r.setToolOrder(const ['c', 'a']);
      await r.setToolOrder(const []);
      expect(r.toolCards.map((t) => t.title), ['工具-a', '工具-b', '工具-c']);
    });
  });

  group('主题插件', () {
    test('每个主题的浅/深色板都取得出来，isDark 与请求一致', () {
      for (final t in themes) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final p = t.palette(brightness);
          expect(p.isDark, brightness == Brightness.dark, reason: t.id);
          // 派生色板最容易漏的就是文字与强调色被写成半透明，这里挡一下
          // （玻璃主题深色下主文字是白 95%，所以只要求足够实，不要求完全不透明）
          expect(p.textPrimary.a, greaterThan(0.9), reason: '${t.id} 主文字色太透');
          expect(p.accent.a, greaterThan(0.9), reason: '${t.id} 强调色太透');
        }
      }
    });

    test('只有玻璃主题自带场景光斑', () {
      expect(const GlassTheme().wells(Brightness.light), isNotEmpty);
      expect(const GlassTheme().wells(Brightness.dark), isNotEmpty);
      expect(const InkTheme().wells(Brightness.light), isEmpty);
      expect(const BambooTheme().wells(Brightness.dark), isEmpty);
    });

    test('清单里每个主题的 id 唯一', () {
      final ids = themes.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
