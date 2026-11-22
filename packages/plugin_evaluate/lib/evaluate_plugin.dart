import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_page.dart';

/// 学生评教（原生界面）：App 自己经校园代理连教务，逐位老师打分。
///
/// 与旧版（内嵌 WebView）的区别：**不再嵌套网页**，所有交互都在 App 里完成；
/// 协议细节见 [EvaluateApi]。
class EvaluatePlugin extends FeaturePlugin {
  const EvaluatePlugin();

  static const pluginId = 'evaluate';

  @override
  String get id => pluginId;
  @override
  String get name => '学生评教';
  @override
  String get description => '原生评教：一键给全部老师同分，逐条确认提交（不再内嵌网页）';

  @override
  List<PluginTool> tools(PluginRegistry registry) {
    // 演示模式也给入口（假数据走一遍 UI）；真实提交 / 保存由页面自己拦截
    return [
      PluginTool(
        icon: Icons.rate_review_outlined,
        color: Colors.indigo,
        title: '学生评教',
        subtitle: () => '一键打分 / 逐条提交',
        open: () => const EvaluatePage(),
      ),
    ];
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_EVALUATE=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [EvaluatePlugin()]);