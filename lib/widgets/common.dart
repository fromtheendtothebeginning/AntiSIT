import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../pages/login_page.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// 统一错误处理：snackbar 提示；401 只提示不跳转——保留导航界面，
/// 用户通过「我的 → 点击登录」主动重新登录。
void showErr(BuildContext context, Object e, {StackTrace? st}) {
  final msg = e is ApiError ? e.message : e.toString();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4)));
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
      return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
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
                  style: const TextStyle(color: SemColors.textMuted)),
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
          child: Text(emptyText, style: const TextStyle(color: SemColors.textMuted)),
        ),
      );
    }
    return child;
  }
}

/// 未登录提示卡：数据页在游客模式下的占位内容。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, this.title = '未登录'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined, size: 56, color: SemColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              '登录 anticraft 账号后查看校园数据\n校园凭据在网站「我的 → 校园服务」配置一次即可',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: SemColors.textMuted, height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
              child: const Text('去登录'),
            ),
            const SizedBox(height: 10),
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
          key: ValueKey('gate_${st.demo}_${st.token != null}'),
          child: child,
        );
      },
    );
  }
}

const cardRadius = 14.0;

/// 语义色（与 anticraft.top 网站 CSS 令牌一致）。
class SemColors {
  static const accent = Color(0xFF2563EB);
  static const accentSoft = Color(0x142563EB); // 8% 蓝
  static const accentStrong = Color(0x1F2563EB); // 12% 蓝
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0x1F16A34A);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0x1FDC2626);
  static const warning = Color(0xFFD97706);
  static const info = Color(0xFF0284C7);
  static const infoSoft = Color(0x1A0284C7);
  static const neutralSoft = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF4B5563);
  static const textMuted = Color(0xFF6B7280);
}

/// 网站同款状态胶囊徽章：全圆、同色 1px 描边、同色浅底。
class Capsule extends StatelessWidget {
  const Capsule(this.text, {super.key, this.color = SemColors.textMuted, this.soft});

  final String text;
  final Color color;
  final Color? soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: soft ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// 统一白卡片（1px 灰边、14px 圆角、无阴影，同网站 .cs-panel）。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.radius});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? cardRadius;
    final card = Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: const BorderSide(color: SemColors.border),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(r), onTap: onTap, child: card);
  }
}

/// 30px/600 大数字统计（网站 .cs-stat）。
class BigStat extends StatelessWidget {
  const BigStat({super.key, required this.label, required this.value, this.suffix, this.color});

  final String label;
  final String value;
  final String? suffix;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: SemColors.textMuted)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w600, height: 1.1,
                    color: color ?? SemColors.textPrimary)),
            if (suffix != null) ...[
              const SizedBox(width: 4),
              Text(suffix!,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: SemColors.textSecondary)),
            ],
          ],
        ),
      ],
    );
  }
}
