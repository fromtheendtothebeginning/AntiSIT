import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_page.dart';

/// 学生评教（原生界面）：App 自己经校园代理连教务，逐位老师打分，协议细节见 [EvaluateApi]。
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

/// 插件包入口：清单生成器按包名登记；EXCLUDE_EVALUATE 开关为真时整包被摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [EvaluatePlugin()]);