import 'extension_item.dart';

/// **编译前固定的拓展**：发行方在这里加，随包一起发布。
///
/// 用户端把它们当「内置」看待：卡片上有「内置」标记，不能删、不能改。
/// 想在某个版本里临时下线一条，把对应的那一行注释掉再出包即可——
/// 它们不落盘（用户的清单里没有它们），所以改完清单升级 App 就生效。
///
/// 内置 Cordis 拓展的 `url` 写成 `asset:<main.js 的 asset key>`，
/// 文件放在 `assets/builtin/<name>/`（见 pubspec 的 assets）。
///
/// ```dart
/// const List<ExtensionItem> kBuiltinExtensions = [
///   ExtensionItem(
///     id: 'builtin.demo',
///     name: '示例拓展',
///     url: 'asset:packages/plugin_ext/assets/builtin/demo/main.js',
///     bundled: true,
///     builtin: true,
///     runtime: ExtensionItem.runtimeCordis,
///   ),
/// ];
/// ```
const List<ExtensionItem> kBuiltinExtensions = [
  ExtensionItem(
    id: 'builtin.workshop',
    name: '拓展工坊',
    desc: '和 Agent 一起写 Cordis 拓展：改代码、预览、安装',
    url: 'asset:packages/plugin_ext/assets/builtin/workshop/main.js',
    bundled: true,
    builtin: true,
    runtime: ExtensionItem.runtimeCordis,
    version: '1.0.0',
    permissions: ['storage', 'ai'],
  ),
];
