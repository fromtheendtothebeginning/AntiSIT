import 'extension_item.dart';

/// **编译前固定的拓展**：发行方在这里加，随包一起发布。
///
/// 用户端把它们当「内置」看待：卡片上有「内置」标记，不能删、不能改。
/// 想在某个版本里临时下线一条，把对应的那一行注释掉再出包即可——
/// 它们不落盘（用户的清单里没有它们），所以改完清单升级 App 就生效。
///
/// 加一条就是加一行：
///
/// ```dart
/// const List<ExtensionItem> kBuiltinExtensions = [
///   ExtensionItem(
///     id: 'builtin.demo',                    // 全局唯一，别改（改了等于换了一条）
///     name: '示例拓展',                       // 卡片标题
///     url: 'https://example.com/app',        // 打开哪个网页
///     desc: '一句话简介，显示在卡片名称下方',      // 可空
///     icon: '',                              // 图片网址或 emoji；空 = 用网站 favicon
///   ),
/// ];
/// ```
const List<ExtensionItem> kBuiltinExtensions = [];
