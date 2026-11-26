import 'plugin.dart';

// 插件依赖图：纯函数，启用判定由调用方传入，便于脱离注册表状态单独使用。

/// 直接依赖 [id] 的插件（硬依赖，即关掉 [id] 会牵连谁）。
List<String> hardDependentsOf(List<FeaturePlugin> features, String id) => [
      for (final p in features)
        if (p.dependencies.contains(id)) p.id,
    ];

/// 传递闭包：停用 [id] 会连带停用的插件（不含自身，按依赖方向展开）。
List<String> dependencyDisableClosure(
  List<FeaturePlugin> features,
  String id,
  bool Function(String id) enabled,
) {
  final out = <String>{};
  var frontier = <String>{id};
  while (frontier.isNotEmpty) {
    final next = <String>{};
    for (final p in features) {
      if (!enabled(p.id) || out.contains(p.id)) continue;
      if (p.dependencies.any(frontier.contains)) {
        out.add(p.id);
        next.add(p.id);
      }
    }
    frontier = next;
  }
  return out.toList();
}
