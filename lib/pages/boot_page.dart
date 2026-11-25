import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import '../update_download.dart';
import 'home_page.dart';

/// 启动页：加载本地设置与插件清单后直接进主页，不强制登录。
///
/// 有 token 直接用（401 时请求层自动续期 / 重登），未登录由各页面的门控引导。
class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// 依次加载设置、插件清单、课表与插件初始化，然后跳主页。
  Future<void> _boot() async {
    await AppState.I.load();
    // 插件清单：读启停状态与当前主题，此后底栏、工具宫格、设置项都按启用集合组装
    await PluginRegistry.I.load();
    // 课表要在插件初始化前读出来：流体云 / 上课提醒 / 桌面卡片都靠它在启动时排期
    await TimetableStore.instance.load();
    await PluginRegistry.I.initAll();
    // 上一次更新下载的安装包装完就没用了，启动时顺手清扫；不阻塞首屏
    unawaited(UpdateDownloader.I.sweepCache());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/sit-mark.png', width: 96, height: 96),
            const SizedBox(height: 16),
            Text('AntiSIT', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
