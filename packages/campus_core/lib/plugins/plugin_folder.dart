import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 从运行中的 Flutter App（或插件包）目录里，把 `packages/plugin_*` 汇总成「插件文件夹」。
///
/// 这里把「一个插件 = 一个 Dart 包」改造成「一个插件 = 一个文件夹」的读取层：
/// - 文件夹 = 插件（manifest、lib、assets 全在一起）；
/// - 文件夹里可以有多个**部件**（parts）：底栏页 / 工具卡片 / 主题 / AI 提供商，
///   每个部件可以在自己的子目录里写自己的实现；
/// - 部件之间的依赖仍按插件 id 记录，一个文件夹里可以同时提供多个插件 id。
///
/// 运行期：宿主只把「插件文件夹清单」读进来（[PluginFolderCatalog]），各文件夹的
/// 部件实现仍由 pubspec 依赖带进构建（纯 Dart 不能运行期加载代码）。这样目录结构
/// 改了、文档改了、生成器认文件夹，构建与运行都还是同一份包集合。

/// 一个插件文件夹里的一个部件（= 旧结构里一个 `packages/plugin_*/` 的插件类）。
class PluginPartSpec {
  const PluginPartSpec({
    required this.id,
    required this.kind,
    this.file = '',
    this.capabilities = const [],
  });

  /// 部件提供的插件 id（依赖关系、能力 key 都用它）。
  final String id;

  /// `feature` / `theme` / `provider`。
  final String kind;

  /// 部件类所在的 Dart 文件（相对插件文件夹；空 = 由扫描器决定）。
  final String file;

  /// 这个部件对外提供的能力 id（与 [id] 相同的常见，也可额外提供别的 id）。
  final List<String> capabilities;

  factory PluginPartSpec.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    String s(String k) => '${map[k] ?? ''}'.trim();
    final caps = map['capabilities'];
    return PluginPartSpec(
      id: s('id'),
      kind: s('kind'),
      file: s('file'),
      capabilities: [
        if (caps is List)
          for (final c in caps)
            if (c is String && c.trim().isNotEmpty) c.trim(),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    if (file.isNotEmpty) 'file': file,
    if (capabilities.isNotEmpty) 'capabilities': capabilities,
  };
}

/// 一个插件文件夹：名字 + 依赖 + 部件集合。
class PluginFolderSpec {
  const PluginFolderSpec({
    required this.package,
    required this.parts,
    this.dependencies = const [],
    this.optionalDependencies = const [],
    this.path = 'packages',
  });

  /// 文件夹在 `packages/` 下的名字（就是 Dart 包的包名）。
  final String package;

  /// 这部件的依赖（插件 id；文件夹里多个部件取并集，并在生成器里对账）。
  final List<String> dependencies;
  final List<String> optionalDependencies;

  /// 文件夹里的部件（至少一个）。
  final List<PluginPartSpec> parts;

  /// 相对仓库根目录的目录（默认 `packages`）。
  final String path;

  String get dir => path.isEmpty ? package : '$path/$package';

  /// 文件夹里所有部件提供的 id。
  List<String> get ids => [for (final p in parts) p.id];

  /// 这个文件夹的主部件（第一个功能 / 主题 / 提供商部件）：卡片与文档按它归类。
  PluginPartSpec? get primary => parts.isEmpty ? null : parts.first;

  static const List<String> _kinds = ['feature', 'theme', 'provider'];

  factory PluginFolderSpec.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    String s(String k) => '${map[k] ?? ''}'.trim();
    final parts = map['parts'];
    final okParts = <PluginPartSpec>[
      if (parts is List)
        for (final p in parts)
          if (PluginPartSpec.fromJson(p) case final part
              when _kinds.contains(part.kind))
            part,
    ];
    List<String> stringList(String k) {
      final v = map[k];
      return [
        if (v is List)
          for (final e in v)
            if (e is String && e.trim().isNotEmpty) e.trim(),
      ];
    }

    return PluginFolderSpec(
      package: s('package'),
      parts: okParts,
      dependencies: stringList('dependencies'),
      optionalDependencies: stringList('optionalDependencies'),
      path: s('path').isEmpty ? 'packages' : s('path'),
    );
  }

  Map<String, Object?> toJson() => {
    'package': package,
    if (path != 'packages') 'path': path,
    if (dependencies.isNotEmpty) 'dependencies': dependencies,
    if (optionalDependencies.isNotEmpty)
      'optionalDependencies': optionalDependencies,
    'parts': [for (final p in parts) p.toJson()],
  };
}

/// 从一段 folder 清单 JSON 解析出插件文件夹；坏数据跳过（不把整页带崩）。
List<PluginFolderSpec> parsePluginFolders(Object? raw) {
  final list = raw is List ? raw : const [];
  final out = <PluginFolderSpec>[];
  for (final item in list) {
    final spec = PluginFolderSpec.fromJson(item);
    if (spec.package.isEmpty) continue;
    if (spec.path.startsWith('/') || spec.path.contains('..')) continue;
    out.add(spec);
  }
  return out;
}

/// 插件文件夹清单（落盘在文档目录，运行期只读）。
///
/// 宿主启动时先读它：`packages/` 下所有插件文件夹 → 每个文件夹的目录树；
/// 加载顺序按依赖拓扑（被依赖的先），最终交给注册表与文档。
class PluginFolderCatalog {
  PluginFolderCatalog._();
  static final PluginFolderCatalog I = PluginFolderCatalog._();

  static const String _kFolders = 'plugin_folder_specs';

  /// 清单（每个插件文件夹一项）。
  List<PluginFolderSpec> folders = const [];

  /// 最后一次同步时间与错误。
  DateTime? syncedAt;
  String? error;

  bool get loaded => folders.isNotEmpty;

  /// 读清单：缓存优先；读不到再看 bundled assets（`plugin_folders.json`）。
  Future<void> load({String? bundledAsset}) async {
    final sp = await SharedPreferences.getInstance();
    final cached = sp.getString(_kFolders);
    if (cached != null && cached.isNotEmpty) {
      try {
        folders = parsePluginFolders(jsonDecode(cached));
        return;
      } catch (_) {}
    }
    if (bundledAsset != null) {
      try {
        final text = await File(bundledAsset).readAsString();
        folders = parsePluginFolders(jsonDecode(text));
        await sp.setString(
          _kFolders,
          jsonEncode([for (final f in folders) f.toJson()]),
        );
        return;
      } catch (e) {
        error = '$e';
      }
    }
    folders = <PluginFolderSpec>[];
  }

  /// 写一份清单（生成器 / 导入时用）。
  Future<void> save(List<PluginFolderSpec> next) async {
    folders = List.unmodifiable(next);
    syncedAt = DateTime.now();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kFolders,
      jsonEncode([for (final f in folders) f.toJson()]),
    );
  }

  /// 文件夹目录树：按 `packages/<文件夹名>/<子目录>/…` 展开，供文档与生成器使用。
  List<String> treeOf(PluginFolderSpec spec) {
    final lines = <String>['${spec.package}/'];
    for (final part in spec.parts) {
      final where = part.kind == 'feature'
          ? 'lib'
          : (part.kind == 'theme' ? 'lib/themes' : 'lib/providers');
      final file = part.file.isEmpty ? '${part.id}.dart' : part.file;
      lines.add('$where/$file');
    }
    if (spec.parts.any((p) => p.kind == 'feature')) lines.add('lib/pages/');
    return lines;
  }
}
