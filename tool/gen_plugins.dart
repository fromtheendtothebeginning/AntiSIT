// 插件清单 + 依赖关系生成器。
//
//   dart run tool/gen_plugins.dart
//
// 三件事：
//   1. 扫描宿主 pubspec.yaml 里以 `plugin_` 开头的依赖 → lib/plugins/manifest.g.dart；
//   2. 扫描各插件包与宿主核心插件的**源码**，把「依赖关系」表写回 docs/plugins.md
//      的两行标记之间（勿手改那张表）；
//   3. 校验依赖引用：不存在的 id / 自依赖 / 硬依赖成环直接报错退出——这类错误
//      不生成的话要等运行时才在插件管理页顶部看到告警。
//
// 「导入插件」= 往依赖里加一行 + 跑这个脚本；「删除插件」= 去掉那一行 + 跑这个脚本。
// 纯 Dart（不依赖 Flutter），所以可以直接 dart run。
import 'dart:io';

const _manifestPath = 'lib/plugins/manifest.g.dart';
const _docPath = 'docs/plugins.md';
const _coreIdsPath = 'packages/campus_core/lib/plugins/plugin.dart';
const _coreBundlesPath = 'lib/plugins/core_bundles.dart';
const _beginMarker = '<!-- BEGIN GENERATED plugin-deps -->';
const _endMarker = '<!-- END GENERATED plugin-deps -->';

void main() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('找不到 pubspec.yaml：请在宿主包根目录下运行');
    exit(2);
  }

  final plugins = _scanPluginDeps(pubspec.readAsStringSync());
  final missing = [
    for (final p in plugins)
      if (!File('packages/${p.name}/lib/${p.name}.dart').existsSync()) p.name,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('这些依赖看着是插件包，但找不到它们的 barrel：');
    for (final m in missing) {
      stderr.writeln('  packages/$m/lib/$m.dart');
    }
    stderr.writeln('约定：插件包的入口库必须叫 <包名>.dart，并暴露 `pluginBundle`。');
    exit(1);
  }

  final pluginIds = _scanPluginIds();
  final metas = <_PluginMeta>[
    ..._parseSource('（宿主）', File(_coreBundlesPath), pluginIds),
    for (final p in plugins)
      ..._parseSource('`${p.name}`', _pluginClassFile(p.name), pluginIds,
          uses: _capabilityUses(p.name, pluginIds)),
  ];

  final problems = _validate(metas);
  if (problems.isNotEmpty) {
    stderr.writeln('插件依赖有问题，先改源码再生成：');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
    exit(1);
  }

  var changed = false;
  changed |= _writeIfChanged(File(_manifestPath), _render(plugins));
  changed |= _writeIfChanged(File(_docPath), _renderDoc(File(_docPath).readAsStringSync(), metas));

  stdout.writeln('${plugins.length} 个插件包${changed ? '：已更新生成物' : '：生成物无变化'}');
  _printEdges(metas);
  for (final w in _warnings(metas)) {
    stdout.writeln('  提醒：$w');
  }
}

// ==================== 清单：pubspec → manifest.g.dart ====================

class _Plugin {
  const _Plugin(this.name, this.flag);

  final String name;
  final String flag;
}

/// 取 pubspec.yaml `dependencies:` 段里 top-level 的 `plugin_*` 键，保持书写顺序。
List<_Plugin> _scanPluginDeps(String yaml) {
  final out = <_Plugin>[];
  var inDeps = false;
  for (final raw in yaml.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (!inDeps) {
      if (line.startsWith('dependencies:')) inDeps = true;
      continue;
    }
    // 缩进回到 0 列 = 这一段结束（dev_dependencies / flutter: 等）
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) break;
    final m = RegExp(r'^  (plugin_[a-z0-9_]+):').firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!;
    out.add(_Plugin(name, name.substring('plugin_'.length).toUpperCase()));
  }
  return out;
}

/// 插件包的实现文件：包内第一个声明了 FeaturePlugin / ThemePlugin 子类的库。
/// 约定是 `lib/<包名>_plugin.dart`，但主题包直接写在 barrel 里，所以按内容找更稳。
File _pluginClassFile(String pkg) {
  final dir = Directory('packages/$pkg/lib');
  final files = [
    for (final f in dir.listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart') && !f.path.endsWith('.g.dart')) f,
  ]..sort((a, b) => a.path.compareTo(b.path)); // 稳定顺序：同一个包不会随机挑文件
  for (final f in files) {
    final src = f.readAsStringSync();
    if (_classHeader.hasMatch(src) && src.contains('String get id')) return f;
  }
  stderr.writeln('$pkg：包内找不到 `class Xxx extends FeaturePlugin / ThemePlugin`');
  stderr.writeln('约定：插件类要显式写 extends FeaturePlugin 或 extends ThemePlugin。');
  exit(1);
}

String _render(List<_Plugin> plugins) {
  final b = StringBuffer()
    ..writeln('// GENERATED FILE —— 不要手改。')
    ..writeln('//')
    ..writeln('// 插件集合 = pubspec.yaml 里以 plugin_ 开头的依赖；改完依赖后运行：')
    ..writeln('//   dart run tool/gen_plugins.dart')
    ..writeln('//')
    ..writeln('// 每个 if 都是编译期常量判断：--dart-define=EXCLUDE_XXX=true 构建时该分支')
    ..writeln('// 不可达，插件包代码被 AOT 摇树丢弃（真正减小包体）。')
    ..writeln('//')
    ..writeln('// ignore_for_file: unused_import, prefer_single_quotes')
    ..writeln()
    ..writeln("import 'package:campus_core/campus_core.dart';")
    ..writeln();
  for (final p in plugins) {
    b.writeln("import 'package:${p.name}/${p.name}.dart' as ${p.name};");
  }
  b
    ..writeln()
    ..writeln('/// 本次构建包含的插件包（顺序 = pubspec.yaml 里的书写顺序）。')
    ..writeln('List<PluginBundle> get pluginBundles => [');
  for (final p in plugins) {
    b.writeln(
        "      if (!const bool.fromEnvironment('EXCLUDE_${p.flag}')) ${p.name}.pluginBundle,");
  }
  b.writeln('    ];');
  return b.toString();
}

// ==================== 依赖关系：插件源码 → docs/plugins.md 的表 ====================

class _PluginMeta {
  _PluginMeta(this.pkg, this.id, this.kind, this.hard, this.soft, this.removable,
      this.contributions, this.uses);

  final String pkg; // 生成表格第一列（含反引号）
  final String id;
  final _Kind kind;
  final List<String> hard;
  final List<String> soft;
  final bool removable;
  final String contributions;

  /// 本包源码里通过注册表用到的能力（`capability<X>(PluginIds.y)` 里的 y）。
  /// 这就是「代码耦合」；必须与 hard/soft 里的声明对得上。
  final List<String> uses;
}

enum _Kind { feature, theme, provider }

final _classHeader = RegExp(
    r'^class (\w+) extends (FeaturePlugin|ThemePlugin|AiProviderPlugin) \{',
    multiLine: true);

/// campus_core 里 `PluginIds` 的常量表：插件源码按 `PluginIds.network` 引用别的插件。
Map<String, String> _scanPluginIds() {
  final file = File(_coreIdsPath);
  if (!file.existsSync()) {
    stderr.writeln('找不到 $_coreIdsPath（插件 id 常量表）');
    exit(1);
  }
  final out = <String, String>{};
  for (final m in RegExp(r"static const (\w+) = '([^']*)';").allMatches(file.readAsStringSync())) {
    out[m.group(1)!] = m.group(2)!;
  }
  if (out.isEmpty) {
    stderr.writeln('$_coreIdsPath 里没解析到 PluginIds 常量，生成器要跟着改');
    exit(1);
  }
  return out;
}

/// 解析一个库里所有插件类：id / 硬依赖 / 软依赖 / 可停用 / 贡献点。
List<_PluginMeta> _parseSource(String pkg, File file, Map<String, String> pluginIds,
    {List<String> uses = const []}) {
  final source = file.readAsStringSync();
  final headers = _classHeader.allMatches(source).toList();
  final out = <_PluginMeta>[];
  for (var i = 0; i < headers.length; i++) {
    final h = headers[i];
    // 类体 = 到下一个顶层 class 为止（同文件里的私有 Widget 不算这个插件的一部分）
    final rest = source.substring(h.end, i + 1 < headers.length ? headers[i + 1].start : source.length);
    final next = RegExp(r'^class ', multiLine: true).firstMatch(rest);
    final body = source.substring(h.start, h.end + (next?.start ?? rest.length));

    final symbols = <String, String>{
      for (final m in RegExp(r'static const (\w+) = ([^;]+);').allMatches(body))
        m.group(1)!: m.group(2)!.trim(),
    };
    final id = _resolve(RegExp(r'String get id => ([^;]+);').firstMatch(body)?.group(1), symbols, pluginIds);
    if (id == null) {
      stderr.writeln('$pkg：${h.group(1)} 的 `String get id` 认不出来，生成器就没法记依赖关系');
      exit(1);
    }
    final kind = switch (h.group(2)) {
      'ThemePlugin' => _Kind.theme,
      'AiProviderPlugin' => _Kind.provider,
      _ => _Kind.feature,
    };
    out.add(_PluginMeta(
      pkg,
      id,
      kind,
      _depList(body, 'dependencies', symbols, pluginIds),
      _depList(body, 'optionalDependencies', symbols, pluginIds),
      !body.contains('get removable => false'),
      _contributions(body, kind),
      uses,
    ));
  }
  if (out.isEmpty) {
    stderr.writeln('$pkg：${file.path} 里没找到插件类');
    exit(1);
  }
  return out;
}

/// 扫一个插件包里所有源码，找出它**通过注册表用到的能力**：
/// `PluginRegistry.I.capability<X>(PluginIds.y)` 里的那个 y。
/// 取用处的这个 id 就是代码耦合关系，必须与该插件声明的依赖对得上。
List<String> _capabilityUses(String pkg, Map<String, String> pluginIds) {
  final dir = Directory('packages/$pkg/lib');
  if (!dir.existsSync()) return const [];
  final re = RegExp(r"capability<[^>()]*>\(\s*(?:PluginIds\.(\w+)|'([^']*)')");
  final out = <String>[];
  for (final f in dir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      final id = m.group(1) != null ? pluginIds[m.group(1)!] : m.group(2);
      if (id != null && !out.contains(id)) out.add(id);
    }
  }
  out.sort();
  return out;
}

/// `pluginId` / `themeId` / `PluginIds.xxx` / `'字面量'` 都还原成真正的 id。
String? _resolve(String? token, Map<String, String> symbols, Map<String, String> pluginIds) {
  var t = token?.trim();
  for (var i = 0; i < 4 && t != null; i++) {
    final literal = RegExp(r"^'([^']*)'$").firstMatch(t);
    if (literal != null) return literal.group(1);
    final known = RegExp(r'^PluginIds\.(\w+)$').firstMatch(t);
    if (known != null) return pluginIds[known.group(1)];
    t = symbols[t];
  }
  return null;
}

/// 取 `List<String> get <getter> => const [...];` 里的 id 列表；没写这个 getter = 空。
List<String> _depList(String body, String getter, Map<String, String> symbols, Map<String, String> pluginIds) {
  // 注意 `get optionalDependencies` 不会匹配 `get dependencies`：中间隔着 optional
  final m = RegExp('get $getter =>').firstMatch(body);
  if (m == null) return const [];
  var list = body.substring(m.end);
  final semi = list.indexOf(';');
  if (semi >= 0) list = list.substring(0, semi);
  list = list.replaceAll(RegExp(r'//[^\n]*'), ''); // 注释掉的依赖不算
  return [
    for (final t in RegExp(r"PluginIds\.(\w+)|'([^']*)'").allMatches(list))
      if (_resolve(t.group(0), symbols, pluginIds) case final id?) id,
  ];
}

/// 贡献点：按插件类里重写了哪些方法推出来（人话细节在文档表下面手写）。
String _contributions(String body, _Kind kind) {
  if (kind == _Kind.provider) return 'AI 提供商（一家一个包）';
  if (kind == _Kind.theme) {
    return body.contains('wells(') ? '主题色板 + 场景光斑' : '主题色板';
  }
  final ui = <String>[
    if (body.contains('navItems(')) '底栏页',
    if (body.contains('tools(')) '工具卡片',
    if (body.contains('settingsTiles(')) '设置条目',
  ];
  return [
    if (ui.isEmpty) '无界面' else ...ui,
    if (body.contains('prefetch(')) '卡面预取',
    if (RegExp(r'Future<void> init\(\)').hasMatch(body)) '启动初始化',
  ].join(' + ');
}

String _renderDoc(String doc, List<_PluginMeta> metas) {
  final b = StringBuffer()
    ..writeln(_beginMarker)
    ..writeln('| 插件包 | 插件 id | 硬依赖 | 软依赖 | 用到的能力 | 可停用 | 贡献点 |')
    ..writeln('|---|---|---|---|---|---|---|');
  for (final m in metas) {
    final removable = switch (m.kind) {
      _Kind.theme => '主题只选不关',
      _Kind.feature || _Kind.provider => m.removable ? '✓' : '✗ 核心',
    };
    final uses = m.uses.isEmpty ? '—' : m.uses.map((e) => '`$e`').join('、');
    b.writeln('| ${m.pkg} | `${m.id}` | ${_cell(m.hard)} | ${_cell(m.soft)} | $uses | $removable | ${m.contributions} |');
  }
  b.write(_endMarker);

  final begin = doc.indexOf(_beginMarker);
  final end = doc.indexOf(_endMarker);
  if (begin < 0 || end < begin) {
    stderr.writeln('$_docPath 里找不到依赖关系生成块（$_beginMarker … $_endMarker）');
    exit(1);
  }
  return doc.replaceRange(begin, end + _endMarker.length, b.toString());
}

String _cell(List<String> ids) => ids.isEmpty ? '—' : ids.map((e) => '`$e`').join('、');

// ==================== 依赖校验 ====================

List<String> _validate(List<_PluginMeta> metas) {
  final out = <String>[];
  final ids = <String>{};
  for (final m in metas) {
    if (!ids.add(m.id)) out.add('插件 id 重复：${m.id}（${m.pkg}）');
  }
  for (final m in metas) {
    for (final d in m.hard) {
      if (d == m.id) out.add('${m.pkg} 硬依赖了自己');
      if (!ids.contains(d)) out.add('${m.pkg} 硬依赖了不存在的插件：$d');
    }
    // 代码里按 id 取用了别人的能力，就得声明依赖——两者不一致说明图和代码对不上，
    // 生成阶段直接拦下来（不然图上少一条边，改动别人时看不到牵连）。
    for (final u in m.uses) {
      if (!m.hard.contains(u) && !m.soft.contains(u)) {
        out.add('${m.pkg} 用了 $u 的能力（capability<...>(PluginIds.$u)）但没声明依赖：'
            '加到 dependencies 或 optionalDependencies 里');
      }
    }
  }
  for (final cycle in _hardCycles(metas)) {
    out.add('硬依赖成环：${cycle.join(' → ')}');
  }
  return out;
}

/// 软依赖不校验存在性（语义就是「有则增强、删了拉倒」），只提醒一句。
List<String> _warnings(List<_PluginMeta> metas) {
  final ids = {for (final m in metas) m.id};
  return [
    for (final m in metas)
      for (final d in m.soft)
        if (!ids.contains(d)) '${m.pkg} 软依赖指向不存在的插件：$d（不算错误）',
  ];
}

List<List<String>> _hardCycles(List<_PluginMeta> metas) {
  final byId = {for (final m in metas) m.id: m};
  final done = <String>{};
  final out = <List<String>>[];
  for (final root in metas) {
    final path = <String>[];
    final onPath = <String>{};
    void visit(String id) {
      if (done.contains(id) || onPath.contains(id)) return;
      final m = byId[id];
      if (m == null) return;
      path.add(id);
      onPath.add(id);
      for (final d in m.hard) {
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

// ==================== 输出 ====================

/// 内容没变化就不重写，避免无意义的 diff。
bool _writeIfChanged(File file, String text) {
  if (file.existsSync() && file.readAsStringSync() == text) return false;
  file.writeAsStringSync(text);
  stdout.writeln('已更新 ${file.path}');
  return true;
}

void _printEdges(List<_PluginMeta> metas) {
  for (final m in metas) {
    final deps = [
      if (m.hard.isNotEmpty) '硬 → ${m.hard.join('、')}',
      if (m.soft.isNotEmpty) '软 → ${m.soft.join('、')}',
    ];
    stdout.writeln('  ${m.id.padRight(14)} ${deps.isEmpty ? '无依赖' : deps.join('   ')}');
  }
}
