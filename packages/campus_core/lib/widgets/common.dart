import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../pages/connect_page.dart';
import 'theme_palette.dart';

// 色板 / 主题场景、玻璃组件、底栏拆到了同目录三个文件，
// 这里 re-export 保持 `common.dart` 的原有出口不变（campus_core.dart 只导出本文件）。
export 'glass_nav.dart';
export 'glass_widgets.dart';
export 'theme_palette.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// 已有错误弹窗时（多周课表并发失败等）不叠弹：同一轮失败原因通常相同，
/// 关掉当前这个再让下一次失败重新弹即可。
bool _errDialogOpen = false;

/// 统一错误弹窗：把学校 / 服务器返回的原文完整展示出来（可长按复制）。
/// SnackBar 4 秒就消失，失败原因很容易错过；各组件加载 / 刷新 / 导入 / 报名 / 安装失败
/// 都走这里，页面背后仍保留整页错误态与「重试」，弹窗只负责把原因讲清楚。
void showErr(BuildContext context, Object e, {String title = '操作失败', StackTrace? st}) {
  final msg = e is ApiError ? e.message : e.toString();
  if (!context.mounted || _errDialogOpen) return;
  _errDialogOpen = true;
  unawaited(showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: SelectableText(msg, style: const TextStyle(fontSize: 13.5, height: 1.6)),
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
      ],
    ),
  ).whenComplete(() => _errDialogOpen = false));
}

/// 页面级加载中 / 出错重试 / 空数据 三态容器。
class PageStateView extends StatelessWidget {
  const PageStateView({
    super.key,
    required this.loading,
    this.error,
    this.empty = false,
    required this.onRetry,
    this.emptyText = '暂无数据',
    required this.child,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final VoidCallback onRetry;
  final String emptyText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              // 服务器模式第一次查询要建校园网隧道（几十秒）：只给一个转圈会被当成卡死，
              // 这里把「在等什么」说出来（见 ApiClient.tunnelWarmup）。
              ValueListenableBuilder<int>(
                valueListenable: ApiClient.tunnelWarmup,
                builder: (_, waiting, __) => waiting == 0
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text('正在建立校园网隧道…首次查询可能要几十秒，请稍候',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12.5, color: SemColors.textMuted, height: 1.6)),
                      ),
              ),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: SemColors.textMuted),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(error!, textAlign: TextAlign.center,
                  style: TextStyle(color: SemColors.textMuted)),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyText, style: TextStyle(color: SemColors.textMuted)),
        ),
      );
    }
    return child;
  }
}

/// 未登录提示卡：数据页在游客模式下的占位内容（文案随数据来源模式变化）。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, this.title = '未登录'});

  final String title;

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_circle_outlined, size: 56, color: SemColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              st.direct
                  ? '直连模式：填写学号与统一身份认证密码后\n由本机直接访问学校系统（需在校园网 / 校内 VPN 内）'
                  : '登录服务器账号后查看校园数据\n校园凭据在该服务器网站「我的 → 校园服务」配置一次即可',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: SemColors.textMuted, height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConnectPage()),
              ),
              child: Text(st.direct ? '去填写校园凭据' : '去登录 / 设置服务器'),
            ),
            const SizedBox(height: 10),
            if (kDebugMode)
              OutlinedButton(
                onPressed: () => AppState.I.setDemo(true),
                child: const Text('演示模式（本地假数据）'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 登录门控：未登录时显示 [LoginPrompt]；登录态变化时重建 child（页面重新拉数据）。
class LoginGate extends StatelessWidget {
  const LoginGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        if (!st.loggedIn) return const LoginPrompt();
        return KeyedSubtree(
          key: ValueKey('gate_${st.demo}_${st.direct}_${st.token != null}_${st.creds.hasLogin}'),
          child: child,
        );
      },
    );
  }
}

/// 二维码 / 动态码底板（校园码用）：
/// **浅色主题不画白底**——玻璃卡上再叠一块白方块就是用户报过的「背后一个白色正方形」；
/// 深色主题垫圆角白底，否则深色模块在深色卡面上辨认不出、扫不出来。
/// 两种主题都做圆角裁剪：万一服务端返回的是带白底的旧式 PNG，也只看到圆角而非方角。
class QrPlate extends StatelessWidget {
  const QrPlate({super.key, required this.child, this.side = 220});

  final Widget child;
  final double side;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : null,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: child,
    );
  }
}
