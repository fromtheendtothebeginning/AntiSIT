import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import '../update_download.dart';

/// 「配置」页：刷新行为与需要长期调整的偏好（二课达标线由插件贡献到这里）。
///
/// 「我的 → 设置」里只留一个入口；插件停用 / 删掉时它贡献的条目自动消失。
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const _intervals = <int>[5, 10, 15, 20, 30];

  /// 应用内更新下载留下的安装包占了多大（null = 还在算）。
  int? _apkBytes;

  @override
  void initState() {
    super.initState();
    _loadApkBytes();
  }

  Future<void> _loadApkBytes() async {
    final bytes = await UpdateDownloader.cachedBytes();
    if (mounted) setState(() => _apkBytes = bytes);
  }

  /// 「清理更新安装包」：每升一版都会在缓存里留一个 80MB 上下的 APK，装完之后
  /// 它在手机上没有任何用处，攒几次就能占掉几个 G。
  Future<void> _purgeApks() async {
    final wasBusy = UpdateDownloader.I.busy;
    final freed = await UpdateDownloader.I.purgeCache();
    await _loadApkBytes();
    if (!mounted) return;
    final text = wasBusy
        ? '已取消下载并清理'
        : (freed <= 0 ? '没有需要清理的安装包' : '已清理 ${formatBytes(freed)}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

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
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已扣掉状态栏）
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('配置')),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
            padding: EdgeInsets.fromLTRB(12, 4 + topInset, 12, 24),
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
                    // 应用内更新每升一版都会在缓存里留一个 80MB 上下的 APK，
                    // 装完就没用；这里给个能看到大小、能一键清掉的地方。
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('更新安装包'),
                      subtitle: Text(
                        _apkBytes == null
                            ? '正在统计…'
                            : (_apkBytes! <= 0
                                ? '没有残留的安装包'
                                : '占用 ${formatBytes(_apkBytes!)}，装完就不用留了'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: (_apkBytes ?? 0) <= 0 ? null : _purgeApks,
                        child: const Text('清理'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const PageNotes(
                lines: [
                  '工具页会保留上一次成功拉取的数据：进入页面先显示本地缓存，新数据到达后自动替换。',
                  '关闭自动刷新后，数据只在点页面顶部的刷新按钮时更新；退出登录会清空这些缓存。',
                  '应用内更新的安装包只用来装一次：装完后 App 会自己删掉，也可以在这里手动清理。',
                ],
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
