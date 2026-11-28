import 'extension_item.dart';

/// **编译前固定的拓展**：发行方在这里加，随包一起发布（用户端当「内置」：不能删改）。
///
/// 它们不落盘（用户的清单里没有），改完清单升级 App 就生效；内置 Cordis 拓展的
/// `url` 写成 `asset:<main.js 的 asset key>`，文件放在 `assets/builtin/<name>/`。
const List<ExtensionItem> kBuiltinExtensions = [
  ExtensionItem(
    id: 'builtin.workshop',
    name: '拓展工坊',
    desc: '和 Agent 一起写 Cordis 拓展：改代码、预览、安装',
    url: 'asset:packages/plugin_ext/assets/builtin/workshop/main.js',
    bundled: true,
    builtin: true,
    runtime: ExtensionItem.runtimeCordis,
    version: '1.2.0',
    // files：从「技能」面板导入 SKILL.md / 粘贴文本要用文件选择器；
    // voice：输入框旁边的麦克风（系统识别的结果只回填输入框）
    permissions: ['storage', 'ai', 'files', 'voice'],
  ),
];
