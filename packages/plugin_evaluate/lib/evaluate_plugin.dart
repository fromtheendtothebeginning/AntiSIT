import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_page.dart';

/// 学生评教助手：教务评教页（正方 `xspjgl`）里一键同分 / 逐项滑块调分。
///
/// * **依赖 WebView 内核**（[dependencies]）：评教页是嵌在 App 里的网页，内核被停用
///   （或当前平台不支持）时工具卡片直接不出现——没有网页可填，留着入口只会点进去报错。
/// * **只改分、不代提交**：填完分仍在网页里自己点「提交」，评教一旦提交不可撤。
class EvaluatePlugin extends FeaturePlugin {
  const EvaluatePlugin();

  static const pluginId = 'evaluate';

  @override
  String get id => pluginId;
  @override
  String get name => '学生评教';
  @override
  String get description => '评教助手：一键给所有评分项打同一分，或逐项用滑块调分';
  @override
  List<String> get dependencies => const [PluginIds.webview];

  @override
  List<PluginTool> tools(PluginRegistry registry) {
    // 演示模式是本地假数据：评教要真教务页，这里不出现入口
    if (AppState.I.demo) return const [];
    // 内核没启用 / 平台不支持：没有可填的网页，卡片不出现
    final cap = registry.capability<WebViewCapability>(PluginIds.webview);
    if (cap == null || !cap.available) return const [];
    return [
      PluginTool(
        icon: Icons.rate_review_outlined,
        color: Colors.indigo,
        title: '学生评教',
        subtitle: () => '一键同分 / 逐项调分（滑块）',
        open: () => const EvaluatePage(),
      ),
    ];
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_EVALUATE=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [EvaluatePlugin()]);
