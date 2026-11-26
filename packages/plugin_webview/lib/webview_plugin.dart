import 'package:campus_core/campus_core.dart';

import 'webview_capability_impl.dart';

/// WebView 内核：以网页（HTML/JS）为前端的热插拔插件的运行基座。
/// 只实现内核（可嵌入网页视图 + 整页打开），没有底栏页、工具卡片与设置条目。
/// 默认开启：关掉会把依赖它的「拓展」一起停掉，用户可在插件管理里改。
class WebViewPlugin extends FeaturePlugin {
  const WebViewPlugin();

  static const pluginId = 'webview';

  @override
  String get id => pluginId;
  @override
  String get name => 'WebView 内核';
  @override
  String get description =>
      '网页插件（热插拔）的运行内核：为「拓展」提供可嵌入的网页视图与整页打开能力';
  @override
  bool get defaultEnabled => true;
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；能力 key 为 PluginIds.webview，
/// 热插拔插件按「WebViewCapability 接口 + 该 id」取用，停用时查不到能力；EXCLUDE_WEBVIEW 为真时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [WebViewPlugin()],
  capabilities: {PluginIds.webview: WebViewCapabilityImpl()},
);
