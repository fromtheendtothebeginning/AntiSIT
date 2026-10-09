import 'package:campus_core/campus_core.dart';

import 'core_bundles.dart';
import 'manifest.g.dart';

/// 组装插件注册表：宿主自带的核心插件 + 各插件包（清单由 tool/gen_plugins.dart 生成）。
///
/// 换插件集合只改 pubspec.yaml 的依赖，然后重跑生成器；具体插件包不在这里出现，
/// 删掉某个包也不会留下悬空引用（依赖关系由清单自检兜底）。
PluginRegistry buildAppRegistry() {
  final bundles = <PluginBundle>[appCoreBundle, ...pluginBundles];
  return PluginRegistry(
    features: [for (final b in bundles) ...b.features],
    themes: [for (final b in bundles) ...b.themes],
  );
}
