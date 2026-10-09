import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'score_page.dart';

/// 二课分数：达标分数与明细；顺手把学籍信息缓存给「我的」页用。
class ScorePlugin extends FeaturePlugin {
  const ScorePlugin();

  static const pluginId = 'score';

  @override
  String get id => pluginId;
  @override
  String get name => '二课分数';
  @override
  String get description => '达标进度与明细分项';
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.military_tech_rounded,
          color: Colors.green,
          title: '二课分数',
          subtitle: _subtitle,
          open: () => const ScorePage(),
        ),
      ];

  static String _subtitle() {
    final s = ToolCache.score;
    if (s == null) return '达标进度与明细';
    return '${s['credit']} / ${s['total']} 分';
  }

  /// 「我的 → 学籍信息」也读这份缓存，所以取到后一并写进 AppState。
  @override
  Future<void> prefetch() async {
    final r = await ApiClient.I.score();
    ToolCache.score = r['data'] as Map<String, dynamic>?;
    AppState.I.studentInfo = ToolCache.score?['student'] as Map<String, dynamic>?;
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ScorePlugin()]);
