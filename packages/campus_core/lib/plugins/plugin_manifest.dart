import 'capability.dart';
import 'plugin.dart';

// 插件清单的静态自检：纯函数，只看清单本身，不碰注册表状态。

/// 重复 id / 硬依赖不存在的插件 / 硬依赖成环 → 人话描述，空 = 清单没问题。
List<String> validateFeatureManifest(List<FeaturePlugin> features) {
  final out = <String>[];
  final ids = <String>{};
  for (final p in features) {
    if (!ids.add(p.id)) out.add('插件 id 重复：${p.id}');
  }
  for (final p in features) {
    // 只查硬依赖：软依赖的语义就是「有则增强、没有就算了」。
    for (final d in p.dependencies) {
      if (!ids.contains(d)) out.add('${p.id} 依赖了不存在的插件：$d');
    }
  }
  for (final cycle in hardDependencyCycles(features)) {
    out.add('硬依赖成环：${cycle.join(' → ')}');
  }
  return out;
}

/// 找硬依赖环；每个环返回一条 id 路径（首尾同 id）。没有环返回空。
List<List<String>> hardDependencyCycles(List<FeaturePlugin> features) {
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

/// 提供商 id 重复 → 人话描述。
List<String> validateAiProviderIds(List<AiProviderPlugin> providers) {
  final out = <String>[];
  final ids = <String>{};
  for (final p in providers) {
    if (!ids.add(p.id)) out.add('AI 提供商 id 重复：${p.id}');
  }
  return out;
}

/// 能力必须挂在一个**真实存在的插件 id** 上（写错 id 就永远查不到，静默失效）。
List<String> validateCapabilityOwners({
  required List<FeaturePlugin> features,
  required List<ThemePlugin> themes,
  required List<AiProviderPlugin> providers,
  required Map<String, PluginCapability> capabilities,
}) {
  final known = {
    for (final p in features) p.id,
    for (final t in themes) t.id,
    for (final p in providers) p.id,
  };
  return [
    for (final id in capabilities.keys)
      if (!known.contains(id)) '能力挂在不存在的插件 id 上：$id',
  ];
}
