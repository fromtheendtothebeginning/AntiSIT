import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/common.dart';
import 'plugin.dart';

/// 插件注册表：插件集合 + 运行期启停状态 + 依赖关系查询 / 校验。
///
/// * 插件集合由**宿主**注入（见本包 README / 宿主 tool/gen_plugins.dart）：
///   core 不认识具体插件包，插件包都依赖 core，反向引用就成环了；
/// * 启停状态与当前主题落在 SharedPreferences 的 `plugin_*` 键上；
/// * 插件自己的数据请按 `plugin.<id>.*` 前缀另存，删插件时才不会互相牵连；
/// * [I] 可整体替换——测试里换成只含被测插件的小清单，不必动全局状态。
class PluginRegistry extends ChangeNotifier {
  PluginRegistry({
    List<FeaturePlugin> features = const <FeaturePlugin>[],
    List<ThemePlugin> themes = const <ThemePlugin>[],
    this.defaultThemeId = PluginIds.themeGlass,
    String? themeId,
  })  : features = List<FeaturePlugin>.unmodifiable(features),
        themes = List<ThemePlugin>.unmodifiable(themes) {
    problems = validate(this.features);
    _themeId = themeId ?? defaultThemeId;
  }

  /// 宿主启动时用真实插件集合替换掉这个空壳（见 main.dart）。
  static PluginRegistry I = PluginRegistry();

  static const String _kDisabled = 'plugin_disabled';
  static const String _kTheme = 'plugin_theme';
  static const String _kToolOrder = 'plugin_tool_order';

  final List<FeaturePlugin> features;
  final List<ThemePlugin> themes;
  final String defaultThemeId;

  final Set<String> _disabled = <String>{};

  /// 用户排过的工具顺序（插件 id；没列到的按清单顺序排在后面）。
  final List<String> _toolOrder = <String>[];
  late String _themeId;
  bool loaded = false;

  /// 清单自检结果：重复 id / 依赖不存在的插件 / 硬依赖成环。
  /// 非空说明清单本身写错了，管理页顶部原样展示，别的功能照常跑。
  late List<String> problems;

  // ==================== 查询 ====================

  FeaturePlugin? byId(String id) {
    for (final p in features) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 插件存在且没被停用。清单里根本没有这个 id 时返回 false——
  /// 「功能被删掉」和「功能被关掉」对被依赖方是同一件事：别干活。
  bool isEnabled(String id) => byId(id) != null && !_disabled.contains(id);

  bool isDisabled(String id) => byId(id) != null && _disabled.contains(id);

  /// 已启用的功能插件（清单顺序）。
  List<FeaturePlugin> get enabled => [
        for (final p in features)
          if (isEnabled(p.id)) p,
      ];

  /// 底栏页面：已启用插件贡献的导航项，按 [PluginNavItem.order] 排。
  List<(FeaturePlugin, PluginNavItem)> navPages(ValueListenable<int> tab) {
    final out = <(FeaturePlugin, PluginNavItem)>[];
    for (final p in enabled) {
      for (final item in p.navItems(this, tab)) {
        out.add((p, item));
      }
    }
    out.sort((a, b) => a.$2.order.compareTo(b.$2.order));
    return out;
  }

  /// 工具卡片 + 归属插件 id。顺序 = 用户在「工具 → 排序」里排过的顺序，
  /// 没排过的插件按清单顺序排在后面（新增插件不会打乱用户已排好的位置）。
  List<(String, PluginTool)> get toolEntries {
    final entries = <(String, PluginTool)>[
      for (final p in enabled)
        for (final t in p.tools(this)) (p.id, t),
    ];
    if (_toolOrder.isEmpty) return entries;
    final rank = <String, int>{
      for (var i = 0; i < _toolOrder.length; i++) _toolOrder[i]: i,
    };
    final keyed = <(int, int, (String, PluginTool))>[
      for (var i = 0; i < entries.length; i++)
        (rank[entries[i].$1] ?? (_toolOrder.length + i), i, entries[i]),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [
      for (final e in keyed) e.$3,
    ];
  }

  /// 工具宫格卡片（已按用户的排序）。
  List<PluginTool> get toolCards => [
        for (final e in toolEntries) e.$2,
      ];

  /// 保存用户排好的工具顺序（只存还存在的插件 id，避免残留越来越多）。
  Future<void> setToolOrder(List<String> pluginIds) async {
    final alive = [
      for (final id in pluginIds)
        if (byId(id) != null) id,
    ];
    // 逐项比较：只比集合会把「换了个顺序」当成没变化，那样排序就存不下去了
    var same = alive.length == _toolOrder.length;
    if (same) {
      for (var i = 0; i < alive.length; i++) {
        if (alive[i] != _toolOrder[i]) {
          same = false;
          break;
        }
      }
    }
    if (same) return;
    _toolOrder
      ..clear()
      ..addAll(alive);
    await _persist();
    notifyListeners();
  }

  /// 「我的 → 设置」里由插件贡献的条目（按 [FeaturePlugin.settingsOrder]）。
  List<Widget> settingsTiles(BuildContext context) {
    final groups = <(int, List<Widget>)>[];
    for (final p in enabled) {
      final tiles = p.settingsTiles(context, this);
      if (tiles.isNotEmpty) groups.add((p.settingsOrder, tiles));
    }
    groups.sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (final g in groups) ...g.$2,
    ];
  }

  /// 当前生效的主题：选中的被删掉时回落到默认主题，再不行用第一个。
  ThemePlugin get theme {
    for (final t in themes) {
      if (t.id == _themeId) return t;
    }
    for (final t in themes) {
      if (t.id == defaultThemeId) return t;
    }
    return themes.isEmpty ? const FallbackTheme() : themes.first;
  }

  // ==================== 依赖 ====================

  /// 直接依赖 [id] 的插件（硬依赖，即关掉 [id] 会牵连谁）。
  List<String> dependentsOf(String id) => [
        for (final p in features)
          if (p.dependencies.contains(id)) p.id,
      ];

  /// 传递闭包：停用 [id] 会连带停用的插件（不含自身，按依赖方向展开）。
  List<String> disableClosure(String id) {
    final out = <String>{};
    var frontier = <String>{id};
    while (frontier.isNotEmpty) {
      final next = <String>{};
      for (final p in features) {
        if (!isEnabled(p.id) || out.contains(p.id)) continue;
        if (p.dependencies.any(frontier.contains)) {
          out.add(p.id);
          next.add(p.id);
        }
      }
      frontier = next;
    }
    return out.toList();
  }

  /// 启用 [id] 及其硬依赖闭包；返回本次真正被打开的 id（含自身）。
  Future<List<String>> enable(String id) async {
    final turned = <String>[];
    final seen = <String>{};
    void open(String x) {
      if (!seen.add(x)) return; // 硬依赖成环时也不会转不出来
      final p = byId(x);
      if (p == null) return;
      if (_disabled.remove(x)) turned.add(x);
      for (final d in p.dependencies) {
        open(d);
      }
    }

    open(id);
    if (turned.isEmpty) return turned;
    await _persist();
    notifyListeners();
    return turned;
  }

  /// 停用 [id] 及所有依赖它的插件；核心插件不动。返回真正被停用的 id。
  Future<List<String>> disable(String id) async {
    final p = byId(id);
    if (p == null || !p.removable) return const [];
    final turned = <String>[];
    if (_disabled.add(id)) turned.add(id);
    for (final d in disableClosure(id)) {
      if (_disabled.add(d)) turned.add(d);
    }
    await _persist();
    notifyListeners();
    return turned;
  }

  Future<void> setTheme(String id) async {
    if (!themes.any((t) => t.id == id) || id == _themeId) return;
    _themeId = id;
    await _persist();
    notifyListeners();
  }

  // ==================== 持久化 / 生命周期 ====================

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _disabled
      ..clear()
      ..addAll((sp.getStringList(_kDisabled) ?? const <String>[])
          .where((id) => byId(id) != null)); // 已删插件留下的记录直接忽略
    _disabled.removeWhere((id) => byId(id)!.removable == false); // 核心插件不给关
    _toolOrder
      ..clear()
      ..addAll((sp.getStringList(_kToolOrder) ?? const <String>[])
          .where((id) => byId(id) != null));
    final savedTheme = sp.getString(_kTheme);
    if (savedTheme != null && themes.any((t) => t.id == savedTheme)) _themeId = savedTheme;
    problems = validate(features);
    _repair();
    loaded = true;
    notifyListeners();
  }

  /// 启动初始化：只跑已启用的插件，单个失败不拖垮启动。
  Future<void> initAll() async {
    for (final p in enabled) {
      try {
        await p.init();
      } catch (e) {
        debugPrint('[插件] ${p.id} 初始化失败：$e');
      }
    }
  }

  /// 预取工具卡面速览（电费余额、二课学分…），拿不到就保持默认副标题。
  Future<void> prefetchTools() async {
    for (final p in enabled) {
      try {
        await p.prefetch();
      } catch (_) {}
    }
  }

  /// 启用的插件其硬依赖却关着（清单改动 / 旧版本数据）→ 关掉依赖它的插件，
  /// 别让界面停在「一半有、一半没有」的半残状态。
  void _repair() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final p in features) {
        if (!isEnabled(p.id)) continue;
        if (p.dependencies.any(isDisabled)) {
          _disabled.add(p.id);
          changed = true;
        }
      }
    }
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kDisabled, _disabled.toList());
    await sp.setString(_kTheme, _themeId);
    await sp.setStringList(_kToolOrder, _toolOrder);
  }

  // ==================== 清单自检 ====================

  /// 重复 id / 依赖不存在的插件 / 硬依赖成环 → 人话描述，空 = 清单没问题。
  static List<String> validate(List<FeaturePlugin> features) {
    final out = <String>[];
    final ids = <String>{};
    for (final p in features) {
      if (!ids.add(p.id)) out.add('插件 id 重复：${p.id}');
    }
    for (final p in features) {
      // 只查硬依赖：软依赖的语义就是「有则增强、没有就算了」，
      // 插件被删掉之后不该留一条永久告警（删依赖方才是要修的东西）。
      for (final d in p.dependencies) {
        if (!ids.contains(d)) out.add('${p.id} 依赖了不存在的插件：$d');
      }
    }
    for (final cycle in hardCycles(features)) {
      out.add('硬依赖成环：${cycle.join(' → ')}');
    }
    return out;
  }

  /// 找硬依赖环；每个环返回一条 id 路径（首尾同 id）。没有环返回空。
  static List<List<String>> hardCycles(List<FeaturePlugin> features) {
    final byId = {for (final p in features) p.id: p};
    final done = <String>{};
    final out = <List<String>>[];
    for (final root in features) {
      final path = <String>[];
      final onPath = <String>{};
      void visit(String id) {
        if (done.contains(id) || onPath.contains(id)) return;
        final p = byId[id];
        if (p == null) return;
        path.add(id);
        onPath.add(id);
        for (final d in p.dependencies) {
          if (onPath.contains(d)) {
            out.add([...path.sublist(path.indexOf(d)), d]);
          } else {
            visit(d);
          }
        }
        onPath.remove(id);
        path.removeLast();
        done.add(id);
      }

      visit(root.id);
    }
    return out;
  }
}

/// 一个主题包都没装时的兜底主题（正常构建里不会用到，见 [PluginRegistry.theme]）。
/// 放在 core 而不是某个主题包里：core 不认识主题包。
class FallbackTheme extends ThemePlugin {
  const FallbackTheme();

  @override
  String get id => 'theme.fallback';
  @override
  String get name => '默认';
  @override
  String get description => '兜底主题：没有安装任何主题插件时使用';
  @override
  GlassPalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? GlassPalette.dark : GlassPalette.light;
  @override
  List<GlassWell> wells(Brightness brightness) =>
      brightness == Brightness.dark ? kGlassWellsDark : kGlassWellsLight;
}
