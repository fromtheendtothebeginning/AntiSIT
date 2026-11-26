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
  ///
  /// 每一步都可能因为本机数据损坏 / 单个插件 init 抛错而失败。启动页是唯一入口，
  /// **任何一步失败都不能把用户永久锁在转圈页**：记下第一个失败、继续往下走，
  /// 保证「打开 App 至少能进主页」。
  Future<void> _boot() async {
    Object? bootError;
    StackTrace? bootStack;
    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } catch (e, s) {
        bootError ??= e;
        bootStack ??= s;
        debugPrint('[启动] $name 失败，继续启动：$e\n$s');
      }
    }

    await step('设置', () => AppState.I.load());
    // 插件清单：读启停状态与当前主题，此后底栏、工具宫格、设置项都按启用集合组装
    await step('插件清单', () => PluginRegistry.I.load());
    // 课表要在插件初始化前读出来：流体云 / 上课提醒 / 桌面卡片都靠它在启动时排期
    await step('课表', () => TimetableStore.instance.load());
    await step('插件初始化', () => PluginRegistry.I.initAll());
    // 上一次更新下载的安装包装完就没用了，启动时顺手清扫；不阻塞首屏
    unawaited(UpdateDownloader.I.sweepCache());
    if (!mounted) return;
    if (bootError != null) {
      // 报给崩溃日志（release 下不进 UI），但不拦启动
      FlutterError.reportError(FlutterErrorDetails(
        exception: bootError!,
        stack: bootStack,
        library: 'antisit boot',
        context: ErrorDescription('启动初始化'),
      ));
    }
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
