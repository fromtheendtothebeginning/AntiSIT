import 'package:campus_core/campus_core.dart';

import 'webview_capability_impl.dart';

/// WebView 内核：自定义「热插拔插件」的运行基座。
///
/// 热插拔插件 = 以网页（HTML/JS）为前端的插件，内容可以不随 App 发版更新。
/// 本插件只实现**内核**——引擎封装（[WebViewCapabilityImpl]：可嵌入网页视图 +
/// 整页打开网页），不实现任何前端页面；所以它没有底栏页、没有工具卡片、
/// 没有设置条目，插件列表里只是安静地躺着。
///
/// **默认关闭**（[defaultEnabled]）：内核就绪但还没有消费方，等第一批
/// 网页插件就绪后由用户在「插件管理」里打开；打开与否会被记住。
class WebViewPlugin extends FeaturePlugin {
  const WebViewPlugin();

  static const pluginId = 'webview';

  @override
  String get id => pluginId;
  @override
  String get name => 'WebView 内核';
  @override
  String get description =>
      '网页形态自定义插件（热插拔）的运行内核：可嵌入网页视图、整页打开网页。'
      '暂无功能界面，启用后供将来的插件使用';
  @override
  bool get defaultEnabled => false;
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// `capabilities` 的 key 就是本插件 id：将来的热插拔插件按「WebViewCapability 接口
/// + PluginIds.webview 这个 id」取用内核，不 import 本包；本插件被停用（默认态）
/// 时查不到能力。（注释里不写完整的取用调用式——生成器按源码字面扫描能力引用。）
/// 编译期常量开关为真时（--dart-define=EXCLUDE_WEBVIEW=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [WebViewPlugin()],
  capabilities: {PluginIds.webview: WebViewCapabilityImpl()},
);
