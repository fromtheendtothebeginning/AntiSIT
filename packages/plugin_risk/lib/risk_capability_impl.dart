import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_notice_page.dart';

/// 风险提醒能力的实现：拦截界面 + 关闭前的条款确认。
/// 文案与条款都留在本包里，被拦的插件（校园码 / 电费）只拿 campus_core 的
/// [RiskNoticeCapability] 接口，不 import 本包。
class RiskNoticeCapabilityImpl extends RiskNoticeCapability {
  const RiskNoticeCapabilityImpl();

  /// 跳插件管理：那页属于宿主包，插件不认识它，只能走宿主注入的构建器
  /// （见 campus_core 的 `hostPluginManagerBuilder`）。
  void _openPluginManager(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => hostPluginManagerBuilder()));
  }

  void _openNotice(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RiskNoticePage()));
  }

  @override
  Widget blockedNotice(BuildContext context, {required String feature}) => _notice(context,
      feature: feature, onOpenManager: () => _openPluginManager(context));

  @override
  Future<void> warnBlocked(BuildContext context, {required String feature}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('操作已暂停'),
        content: _notice(
          ctx,
          feature: feature,
          onOpenManager: () {
            Navigator.pop(ctx); // 先关弹窗，别把管理页叠在弹窗上
            if (context.mounted) _openPluginManager(context);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Future<bool> confirmDisable(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const RiskNoticePage(confirmMode: true)));
    return ok ?? false;
  }

  /// 拦截内容：说明 + 两个出口（去关闭 / 看条款）。原位引导与弹窗共用它，
  /// 只有「去关闭」的动作不同（弹窗里要先把自己关掉）。
  Widget _notice(BuildContext context,
      {required String feature, required VoidCallback onOpenManager}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.gpp_maybe_outlined, size: 30, color: SemColors.warning),
        const SizedBox(height: 8),
        const Text('「风险提醒」已开启',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('$feature已暂停，关闭「风险提醒」后即可使用。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.5)),
        const SizedBox(height: 10),
        FilledButton.tonal(
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onOpenManager,
          child: const Text('去插件管理关闭'),
        ),
        TextButton(
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: SemColors.textSecondary),
          onPressed: () => _openNotice(context),
          child: const Text('风险说明与条款', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}
