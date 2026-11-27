import 'extension_item.dart' show compareVersions;

/// 拓展对外暴露的接口（依赖插件用）：宿主按名字登记，应用插件按名字取用。
///
/// 接口实现留在提供方拓展自己的 main.js 里；本文件只描述「谁能提供什么」与查表规则。
class ExtApiEntry {
  const ExtApiEntry({
    required this.extId,
    required this.name,
    required this.reference,
  });

  /// 提供方拓展 id（= 它的 ext.json id）。
  final String extId;

  /// 接口名（与市场目录条目 `api` 里声明的名字一致）。
  final String name;

  /// 宿主的调用引用（`antiSIT.call` 用的方法名，可空）。
  final String reference;

  @override
  String toString() => '$name（$extId）';
}

/// 依赖插件注册表：已装拓展声明的接口都登记在这。
class ExtApiRegistry {
  ExtApiRegistry();

  /// 宿主启动时换成真实实例；测试里换成干净的。
  static ExtApiRegistry I = ExtApiRegistry();

  final Map<String, ExtApiEntry> _entries = {};

  /// 已注册的全部接口。
  List<ExtApiEntry> get entries => List.unmodifiable(_entries.values);

  /// 某个依赖插件提供的接口名。
  List<String> apisOf(String extId) => [
    for (final e in _entries.values)
      if (e.extId == extId) e.name,
  ];

  /// 按名字取接口；提供方没装 / 已卸载时返回 null，调用方据此降级。
  ExtApiEntry? byName(String name) => _entries[name.trim()];

  /// 登记一个接口（同名覆盖：更新拓展 = 换实现）。
  void register(ExtApiEntry entry) {
    final name = entry.name.trim();
    if (name.isEmpty) return;
    _entries[name] = entry;
  }

  /// 卸载拓展时清掉它登记的全部接口。
  void unregisterOwner(String extId) {
    _entries.removeWhere((_, e) => e.extId == extId);
  }

  void clear() => _entries.clear();
}

/// 应用插件缺哪些接口（依赖插件没装或没声明）：缺了就不算可用。
List<String> missingApisFor({
  required List<String> required,
  required ExtApiRegistry registry,
}) => [
  for (final name in required)
    if (registry.byName(name) == null) name,
];

/// 依赖版本门：已装的依赖插件版本低于要求时，不让装 / 不算满足。
bool satisfiesDependencyVersion({
  required String installedVersion,
  required String required,
}) {
  if (required.isEmpty) return true;
  if (installedVersion.isEmpty) return false;
  return compareVersions(installedVersion, required) >= 0;
}
