import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 「配置」页：刷新行为与需要长期调整的偏好（二课达标线由插件贡献到这里）。
///
/// 「我的 → 设置」里只留一个入口；插件停用 / 删掉时它贡献的条目自动消失。
class ConfigPage extends StatelessWidget {
  const ConfigPage({super.key});

  static const _intervals = <int>[5, 10, 15, 20, 30];

  Future<void> _pickInterval(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '校园码刷新间隔',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            for (final s in _intervals)
              ListTile(
                title: Text('每 $s 秒换一张'),
                subtitle: s == 10
                    ? const Text(
                        '推荐：付款码保持新鲜，也不会频繁请求',
                        style: TextStyle(fontSize: 11.5),
                      )
                    : null,
                trailing: AppState.I.ecardRefreshSeconds == s
                    ? Icon(Icons.check, color: SemColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await AppState.I.setEcardRefreshSeconds(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, PluginRegistry.I]),
      builder: (context, _) {
        final st = AppState.I;
        return Scaffold(
          appBar: AppBar(title: const Text('配置')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew_rounded),
                      title: const Text('工具页自动刷新'),
                      subtitle: const Text(
                        '进入电费 / 二课 / 活动 / 考试 / 成绩页时自动拉取最新数据；'
                        '关闭后只显示本地缓存（没有缓存时仍会拉取一次）',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: st.autoRefreshTools,
                      onChanged: (v) => AppState.I.setAutoRefreshTools(v),
                    ),
                    ListTile(
                      leading: const Icon(Icons.qr_code_2_rounded),
                      title: const Text('校园码刷新间隔'),
                      subtitle: Text(
                        '每 ${st.ecardRefreshSeconds} 秒换一张码（服务端有效期更短时以服务端为准）',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickInterval(context),
                    ),
                    // 二课达标线等长期偏好由各插件贡献（停用插件则自动消失）
                    ...PluginRegistry.I.configTiles(context),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const PageNotes(
                lines: [
                  '工具页会保留上一次成功拉取的数据：进入页面先显示本地缓存，新数据到达后自动替换。',
                  '关闭自动刷新后，数据只在点页面顶部的刷新按钮时更新；退出登录会清空这些缓存。',
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
