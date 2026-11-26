import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'score_page.dart';
import 'score_target_settings_page.dart';

/// 二课分数：达标分数与明细；顺手把学籍信息缓存给「我的」页用。
class ScorePlugin extends FeaturePlugin {
  const ScorePlugin();

  static const pluginId = 'score';

  @override
  String get id => pluginId;
  @override
  String get name => '二课分数';
  @override
  String get description => '第二课堂学分：达标进度与分项明细';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.military_tech_outlined,
          color: Colors.green,
          title: '二课分数',
          subtitle: _subtitle,
          open: () => const ScorePage(),
        ),
      ];

  @override
  int get settingsOrder => 48;

  /// 达标线属于长期偏好，入口收在「我的 → 配置」页里（二课页里也留了快捷按钮）。
  @override
  List<Widget> configTiles(BuildContext context, PluginRegistry registry) => [
        ListTile(
          leading: const Icon(Icons.military_tech_outlined),
          title: const Text('第二课堂达标线'),
          subtitle: const Text('按年级调整各板块的达标分数'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScoreTargetSettingsPage()),
          ),
        ),
      ];

  static String _subtitle() {
    final s = ToolCache.score;
    if (s == null) return '达标进度与明细';
    return '${s.credit} / ${s.total} 分';
  }

  /// 预取分数：同时写 AppState（「我的 → 学籍信息」也读这份）与工具页缓存（二级页先显示缓存）。
  @override
  Future<void> prefetch() async {
    final r = await ApiClient.I.score();
    ToolCache.score = ToolCache.scoreOf(r['data']);
    AppState.I.studentInfo = ToolCache.score?.student;
    await ToolPageCache.write('score', {'data': r['data']});
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 保持 const：EXCLUDE 开关为真时整条连同包内代码一起被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ScorePlugin()]);
