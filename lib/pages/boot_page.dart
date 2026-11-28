import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import '../update_download.dart';
import 'boot_splash.dart';
import 'home_page.dart';

/// 启动动画的分层装配约 1.3s：至少让它播完再进主页（否则最后一层绿环刚弹出就切走）。
const Duration bootMinShow = Duration(milliseconds: 1100);

/// 关掉启动动画时不久等：初始化本来就跑完大半，等下去只是对着纯色底发呆。
const Duration bootMinShowWhenOff = Duration(milliseconds: 120);

/// 启动页至少停留多久：开动画就等装配播完，关了只留一帧过渡。
@visibleForTesting
Duration bootMinShowFor(bool animationOn) =>
    animationOn ? bootMinShow : bootMinShowWhenOff;

/// 启动页：播启动动画，同时异步加载本地设置、插件清单、课表与插件初始化，然后进主页。
///
/// 有 token 直接用（401 时请求层自动续期 / 重登），未登录由各页面的门控引导。
class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  /// 动画上那行「正在做什么」：每一步开始前更新，让等待有反馈。
  String _stage = '正在启动…';

  /// 进主页的最早时刻：动画至少播这么久，避免一闪而过。
  final DateTime _startedAt = DateTime.now();
  static const Duration _minShow = bootMinShow;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  void _setStage(String text) {
    if (!mounted || _stage == text) return;
    setState(() => _stage = text);
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
      _setStage(name);
      try {
        await run();
      } catch (e, s) {
        bootError ??= e;
        bootStack ??= s;
        debugPrint('[启动] $name 失败，继续启动：$e\n$s');
      }
    }

    await step('正在读取设置…', () => AppState.I.load());
    // 插件清单：读启停状态与当前主题，此后底栏、工具宫格、设置项都按启用集合组装
    await step('正在加载插件…', () => PluginRegistry.I.load());
    // 插件文件夹清单（生成物）：文档 / 目录树按它展示「一个插件 = 一个文件夹」
    await step('正在读取插件目录…', () => PluginFolderCatalog.I.load());

    // 课表要在插件初始化前读出来：流体云 / 上课提醒 / 桌面卡片都靠它在启动时排期
    await step('正在读取课表…', () => TimetableStore.instance.load());
    await step('正在初始化功能…', () => PluginRegistry.I.initAll());
    // 上一次更新下载的安装包装完就没用了，启动时顺手清扫；不阻塞首屏
    unawaited(UpdateDownloader.I.sweepCache());
    // 动画至少播完一轮再进主页（剩下的初始化本来就已经异步跑完了）；
    // 用户关掉了启动动画就只留一帧过渡，别让人对着空白等。
    final minShow = bootMinShowFor(AppState.I.bootAnimation);
    final elapsed = DateTime.now().difference(_startedAt);
    if (elapsed < minShow) {
      await Future<void>.delayed(minShow - elapsed);
    }
    if (!mounted) return;
    if (bootError != null) {
      // 报给崩溃日志（release 下不进 UI），但不拦启动
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: bootError!,
          stack: bootStack,
          library: 'antisit boot',
          context: ErrorDescription('启动初始化'),
        ),
      );
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    // 关掉启动动画：只留一层纯色底（同一块背景色，不闪白），马上进主页。
    if (!AppState.I.bootAnimation) {
      return ColoredBox(
        color: SemColors.bg,
        child: Center(
          child: Text(
            _stage,
            style: TextStyle(fontSize: 12, color: SemColors.textMuted),
          ),
        ),
      );
    }
    return Scaffold(
      body: BootSplash(stage: _stage, minShow: _minShow),
    );
  }
}
