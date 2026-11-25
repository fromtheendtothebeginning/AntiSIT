import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/flexible_grid.dart';
import 'capability.dart';
import 'json_theme.dart';
import 'plugin.dart';
import 'plugin_fallbacks.dart';
import 'plugin_graph.dart';
import 'plugin_manifest.dart';

// 兜底主题 / 兜底提供商随本文件一并暴露，外部仍可从 campus_core.dart 取到。
export 'plugin_fallbacks.dart';

/// 插件注册表：插件集合 + 运行期启停状态 + 依赖关系查询 / 校验。
///
/// 插件集合由宿主注入（core 不认识具体插件包）；启停状态与主题落在 `plugin_*` 键上，
/// 插件自己的数据请按 `plugin.<id>.*` 前缀另存。[I] 可整体替换，测试换成小清单即可。
class PluginRegistry extends ChangeNotifier {
  PluginRegistry({
    List<FeaturePlugin> features = const <FeaturePlugin>[],
    List<ThemePlugin> themes = const <ThemePlugin>[],
    List<AiProviderPlugin> providers = const <AiProviderPlugin>[],
    Map<String, PluginCapability> capabilities = const {},
    this.defaultThemeId = PluginIds.themeGlass,
    String? themeId,
  })  : features = List<FeaturePlugin>.unmodifiable(features),
        _themes = List<ThemePlugin>.unmodifiable(themes),
        providers = List<AiProviderPlugin>.unmodifiable(providers),
        capabilities = Map<String, PluginCapability>.unmodifiable(capabilities) {
    problems = [
      ...validate(this.features),
      ...validateProviders(this.providers),
      ...validateCapabilities(this),
    ];
    _themeId = themeId ?? defaultThemeId;
  }

  /// 宿主启动时用真实插件集合替换掉这个空壳（见 main.dart）。
  static PluginRegistry I = PluginRegistry();

  static const String _kDisabled = 'plugin_disabled';
  static const String _kTheme = 'plugin_theme';
  static const String _kToolOrder = 'plugin_tool_order';
  static const String _kToolSizes = 'plugin_tool_sizes';

  /// 默认关闭的插件只有出现在这里（且不在 [_disabled]）才算启用。
  static const String _kUserEnabled = 'plugin_user_enabled';

  final List<FeaturePlugin> features;

  /// 内置主题；运行期导入的自定义主题见 [_extraThemes]，读取方一律走 [themes]。
  final List<ThemePlugin> _themes;
  final List<ThemePlugin> _extraThemes = <ThemePlugin>[];

  /// 全部可用主题 = 内置 + 运行期导入的自定义主题。
  List<ThemePlugin> get themes => [..._themes, ..._extraThemes];

  /// 已装进来的 AI 提供商（顺序 = 清单顺序）。
  final List<AiProviderPlugin> providers;

  /// 各插件对外提供的能力（key = 提供方的插件 id）。
  final Map<String, PluginCapability> capabilities;
  final String defaultThemeId;

  final Set<String> _disabled = <String>{};

  /// 用户显式打开过的「默认关闭」插件。
  final Set<String> _userEnabled = <String>{};

  /// 用户排过的工具顺序（插件 id；没列到的按清单顺序排在后面）。
  final List<String> _toolOrder = <String>[];

  /// 用户改过的工具卡片尺寸（插件 id → 网格占位）；没改过就是默认的 2x3。
  final Map<String, GridCardSize> _toolSizes = <String, GridCardSize>{};
  late String _themeId;
  bool loaded = false;

  /// 清单自检结果：非空说明清单写错了，管理页顶部原样展示，别的功能照常跑。
  late List<String> problems;

  // ── 查询 ──

  FeaturePlugin? byId(String id) {
    for (final p in features) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 插件存在且没被停用：「功能被删掉」与「被关掉」对被依赖方是同一件事。
  /// 默认关闭的插件还要求用户显式打开过（[_userEnabled]）。
  bool isEnabled(String id) {
    final p = byId(id);
    if (p == null || _disabled.contains(id)) return false;
    if (!p.defaultEnabled && !_userEnabled.contains(id)) return false;
    return true;
  }

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

  /// 工具卡片 + 归属插件 id：用户排过的在前，没排过的按清单顺序排在后面。
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

  /// 保存用户排好的工具顺序（只存还存在的插件 id）。
  Future<void> setToolOrder(List<String> pluginIds) async {
    final alive = [
      for (final id in pluginIds)
        if (byId(id) != null) id,
    ];
    // 逐项比较：只比集合会把「换了个顺序」当成没变化
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

  /// 工具卡片的网格尺寸：没改过就是默认的 2x3。
  GridCardSize toolSize(String pluginId) =>
      _toolSizes[pluginId] ?? GridCardSize.standard;

  /// 是否有用户改过尺寸的工具卡片（排序页据此决定要不要露出「重置大小」）。
  bool get hasCustomToolSizes => _toolSizes.isNotEmpty;

  /// 保存某张工具卡片的尺寸；传 [GridCardSize.standard] = 恢复默认。
  Future<void> setToolSize(String pluginId, GridCardSize size) async {
    if (byId(pluginId) == null) return;
    final next = Map<String, GridCardSize>.of(_toolSizes);
    if (size == GridCardSize.standard) {
      next.remove(pluginId);
    } else {
      next[pluginId] = size;
    }
    final same = next.length == _toolSizes.length &&
        next.entries.every((e) => _toolSizes[e.key] == e.value);
    if (same) return;
    _toolSizes
      ..clear()
      ..addAll(next);
    await _persistToolSizes();
    notifyListeners();
  }

  /// 把所有工具卡片恢复到默认尺寸。
  Future<void> resetToolSizes() async {
    if (_toolSizes.isEmpty) return;
    _toolSizes.clear();
    await (await SharedPreferences.getInstance()).remove(_kToolSizes);
    notifyListeners();
  }

  Future<void> _persistToolSizes() async {
    final sp = await SharedPreferences.getInstance();
    if (_toolSizes.isEmpty) {
      await sp.remove(_kToolSizes);
      return;
    }
    await sp.setString(_kToolSizes, jsonEncode({
      for (final entry in _toolSizes.entries) entry.key: entry.value.key,
    }));
  }

  /// 读尺寸表：坏数据 / 认不出的尺寸都按默认处理，不把整页带崩。
  static Map<String, GridCardSize> _parseToolSizes(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is String)
            '${entry.key}': GridCardSize.parse(entry.value),
      };
    } catch (e) {
      debugPrint('[registry] 工具卡片尺寸解析失败已忽略：$e');
      return const {};
    }
  }

  /// 「我的 → 设置」里由插件贡献的条目（按 [FeaturePlugin.settingsOrder]）。
  List<Widget> settingsTiles(BuildContext context) =>
      _tilesOrdered((p) => p.settingsTiles(context, this));

  /// 「我的 → 配置」里由插件贡献的条目。
  List<Widget> configTiles(BuildContext context) =>
      _tilesOrdered((p) => p.configTiles(context, this));

  /// 「课程表设置」二级页里由插件贡献的条目。
  List<Widget> timetableSettingsTiles(BuildContext context) =>
      _tilesOrdered((p) => p.timetableSettingsTiles(context, this));

  /// 收集各插件贡献的设置条目：按 [FeaturePlugin.settingsOrder] 排，没贡献的跳过。
  List<Widget> _tilesOrdered(List<Widget> Function(FeaturePlugin) tilesOf) {
    final groups = <(int, List<Widget>)>[];
    for (final p in enabled) {
      final tiles = tilesOf(p);
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

  // ── AI 提供商 ──

  /// 按 id 取提供商；没装这家时返回 null。**停用的照样返回**，能不能用看 [isProviderEnabled]。
  AiProviderPlugin? providerById(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 这家装着、且没被用户停用（停用 = 不进选择器、AI 视同没配这家）。
  bool isProviderEnabled(String id) => providerById(id) != null && !_disabled.contains(id);

  /// 启用中的提供商（清单顺序）。停用记录与功能插件共用 `plugin_disabled` 键。
  List<AiProviderPlugin> get enabledProviders =>
      [for (final p in providers) if (isProviderEnabled(p.id)) p];

  /// 界面里列提供商的顺序：普通提供商按清单顺序，内置的「自定义」排最后。
  static List<AiProviderPlugin> _customLast(List<AiProviderPlugin> list) => [
        ...list.where((p) => !p.isCustom),
        ...list.where((p) => p.isCustom),
      ];

  /// AI 设置的选择器用：只列启用中的。
  List<AiProviderPlugin> get providerChoices => _customLast(enabledProviders);

  /// 插件管理页用：连被停用的一起列（那里要给每行开关）。
  List<AiProviderPlugin> get providerList => _customLast(providers);

  /// 停用 / 启用某家提供商（只影响它自己）。停用后 AI 按「未配置」处理，Key 仍留着。
  Future<void> setProviderEnabled(String id, bool enabled) async {
    final p = providerById(id);
    if (p == null || !p.removable) return;
    if (_disabled.contains(id) == !enabled) return; // 状态没变，不必写盘
    if (enabled) {
      _disabled.remove(id);
    } else {
      _disabled.add(id);
    }
    await _persist();
    notifyListeners();
  }

  /// 解析配置里存的 providerId：停用与没装都算不可用，于是回退到第一个启用中的
  /// 非自定义提供商，再退到第一个启用中的，一个都没有就用 [FallbackAiProvider]。
  AiProviderPlugin resolveProvider(String id) {
    if (isProviderEnabled(id)) return providerById(id)!;
    final usable = enabledProviders;
    for (final p in usable) {
      if (!p.isCustom) return p;
    }
    return usable.isEmpty ? const FallbackAiProvider() : usable.first;
  }

  /// 提供商 id 重复 → 人话描述；与 [validate] 的结果一起并进 [problems]。
  static List<String> validateProviders(List<AiProviderPlugin> providers) =>
      validateAiProviderIds(providers);

  /// 能力必须挂在一个**真实存在的插件 id** 上（写错 id 就永远查不到，静默失效）。
  static List<String> validateCapabilities(PluginRegistry r) => validateCapabilityOwners(
        features: r.features,
        themes: r.themes,
        providers: r.providers,
        capabilities: r.capabilities,
      );

  // ── 能力 ──

  /// 按「接口 + 提供方插件 id」取能力：提供方没装 / 被停用 / 类型不符都返回 null。
  /// 取用处写的这个 id 同时也是依赖关系（生成器会对账）。
  T? capability<T extends PluginCapability>(String ownerId) {
    if (!isEnabled(ownerId)) return null;
    final c = capabilities[ownerId];
    return c is T ? c : null;
  }

  // ── 依赖（图算法见 plugin_graph.dart）──

  /// 直接依赖 [id] 的插件（硬依赖，即关掉 [id] 会牵连谁）。
  List<String> dependentsOf(String id) => hardDependentsOf(features, id);

  /// 传递闭包：停用 [id] 会连带停用的插件（不含自身，按依赖方向展开）。
  List<String> disableClosure(String id) => dependencyDisableClosure(features, id, isEnabled);

  /// 启用 [id] 及其硬依赖闭包；返回本次真正被打开的 id（含自身）。
  Future<List<String>> enable(String id) async {
    final turned = <String>[];
    final seen = <String>{};
    void open(String x) {
      if (!seen.add(x)) return; // 硬依赖成环时也不会转不出来
      final p = byId(x);
      if (p == null) return;
      if (_disabled.remove(x)) turned.add(x);
      // 默认关闭的插件：显式打开 = 记进 userEnabled（否则 isEnabled 永远为假）
      if (!p.defaultEnabled && _userEnabled.add(x)) turned.add(x);
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
    _userEnabled.remove(id); // 关掉就回到默认关闭状态
    for (final d in disableClosure(id)) {
      if (_disabled.add(d)) turned.add(d);
      _userEnabled.remove(d);
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

  // ── 自定义主题（导入 JSON）──

  static const String _kCustomThemes = 'plugin_custom_themes';

  /// 导入（同 id 覆盖）一个自定义主题，并切换过去。
  Future<void> addTheme(JsonThemePlugin theme) async {
    final i = _extraThemes.indexWhere((t) => t.id == theme.id);
    if (i >= 0) {
      _extraThemes[i] = theme;
    } else {
      _extraThemes.add(theme);
    }
    await _persistCustomThemes();
    _themeId = theme.id;
    await _persist(); // 选中态也落盘：重启后还停在导入的主题上
    notifyListeners();
  }

  /// 删除一个导入的主题；正在用它则回落默认主题。内置主题不受影响。
  Future<void> removeTheme(String id) async {
    if (!_extraThemes.any((t) => t.id == id)) return;
    _extraThemes.removeWhere((t) => t.id == id);
    if (_themeId == id) {
      _themeId = defaultThemeId;
      await _persist();
    }
    await _persistCustomThemes();
    notifyListeners();
  }

  Future<void> _persistCustomThemes() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kCustomThemes, [
      for (final t in _extraThemes) jsonEncode((t as JsonThemePlugin).toJson()),
    ]);
  }

  // ── 持久化 / 生命周期 ──

  /// 读回启停、主题、工具顺序 / 尺寸与导入的自定义主题，并修复悬空依赖。
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    // 停用记录里混着功能插件与 AI 提供商的 id（同一个键 `plugin_disabled`）：
    // 只留还装着的，已删插件留下的记录直接忽略
    _disabled
      ..clear()
      ..addAll((sp.getStringList(_kDisabled) ?? const <String>[])
          .where((id) => byId(id) != null || providerById(id) != null));
    // 声明不可停用的（核心功能插件 / 提供商）从记录里剔掉
    _disabled.removeWhere((id) {
      final f = byId(id);
      if (f != null) return !f.removable;
      final p = providerById(id);
      return p != null && !p.removable;
    });
    _toolOrder
      ..clear()
      ..addAll((sp.getStringList(_kToolOrder) ?? const <String>[])
          .where((id) => byId(id) != null));
    // 卡片尺寸：只留还装着的插件；认不出的尺寸在解析时已回落默认，别把默认再存回去
    _toolSizes
      ..clear()
      ..addEntries(_parseToolSizes(sp.getString(_kToolSizes))
          .entries
          .where((e) =>
              byId(e.key) != null && e.value != GridCardSize.standard));
    // 用户显式打开过的默认关闭插件：只留还装着且仍是默认关闭的
    _userEnabled
      ..clear()
      ..addAll((sp.getStringList(_kUserEnabled) ?? const <String>[])
          .where((id) => byId(id)?.defaultEnabled == false));
    // 运行期导入的自定义主题：逐条解析，坏的跳过（不影响其余主题）
    _extraThemes.clear();
    for (final raw in sp.getStringList(_kCustomThemes) ?? const <String>[]) {
      try {
        _extraThemes.add(JsonThemePlugin.parse(raw));
      } catch (e) {
        debugPrint('[registry] 自定义主题解析失败已跳过：$e');
      }
    }
    final savedTheme = sp.getString(_kTheme);
    if (savedTheme != null && themes.any((t) => t.id == savedTheme)) _themeId = savedTheme;
    problems = [...validate(features), ...validateProviders(providers), ...validateCapabilities(this)];
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

  /// 启用的插件其硬依赖却不可用（清单改动 / 旧版本数据 / 依赖是默认关闭插件）→
  /// 关掉依赖它的插件，别让界面停在半残状态。
  void _repair() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final p in features) {
        if (!isEnabled(p.id)) continue;
        // 注意用 isEnabled 而不是 isDisabled：依赖可能是「默认关闭」，它不在 _disabled 里。
        if (p.dependencies.any((d) => !isEnabled(d))) {
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
    await sp.setStringList(_kUserEnabled, _userEnabled.toList());
  }

  // ── 清单自检：实现见 plugin_manifest.dart ──

  /// 重复 id / 依赖不存在的插件 / 硬依赖成环 → 人话描述，空 = 清单没问题。
  static List<String> validate(List<FeaturePlugin> features) =>
      validateFeatureManifest(features);

  /// 找硬依赖环；每个环返回一条 id 路径（首尾同 id）。没有环返回空。
  static List<List<String>> hardCycles(List<FeaturePlugin> features) =>
      hardDependencyCycles(features);
}
