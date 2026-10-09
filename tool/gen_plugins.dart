// 插件清单生成器：扫描 pubspec.yaml 里以 `plugin_` 开头的依赖，生成 lib/plugins/manifest.g.dart。
//
//   dart run tool/gen_plugins.dart
//
// 「导入插件」= 往依赖里加一行 + 跑这个脚本；「删除插件」= 去掉那一行 + 跑这个脚本。
// 纯 Dart（不依赖 Flutter），所以可以直接 dart run。
import 'dart:io';

const _manifestPath = 'lib/plugins/manifest.g.dart';

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

  final text = _render(plugins);
  final file = File(_manifestPath);
  final old = file.existsSync() ? file.readAsStringSync() : null;
  if (old == text) {
    stdout.writeln('清单没变化（${plugins.length} 个插件包）：$_manifestPath');
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('已生成 $_manifestPath：${plugins.length} 个插件包');
  for (final p in plugins) {
    stdout.writeln('  ${p.name.padRight(26)} EXCLUDE_${p.flag}');
  }
}

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
