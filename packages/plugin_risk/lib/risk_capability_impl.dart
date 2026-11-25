import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_notice_page.dart';
import 'risk_terms.dart';

/// 风险提醒能力实现：拦截界面 + 停用前的条款确认。
/// 文案与条款留在本包，被拦插件只拿 campus_core 的 [RiskNoticeCapability] 接口。
class RiskNoticeCapabilityImpl extends RiskNoticeCapability {
  const RiskNoticeCapabilityImpl();

  /// 跳插件管理：该页属宿主包，只能走宿主注入的 hostPluginManagerBuilder。
  void _openPluginManager(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => hostPluginManagerBuilder()));
  }

  /// 打开条款全文页。
  void _openNotice(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RiskNoticePage()));
  }

  @override
  Widget blockedNotice(BuildContext context, {required String feature}) => _notice(context,
      feature: feature, onOpenManager: () => _openPluginManager(context));

  @override
  Future<void> warnBlocked(BuildContext context, {required String feature}) async {
    // 标题由弹窗承担，内容里不再重复一行。
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('风险提醒组件已启用'),
        content: _notice(
          ctx,
          feature: feature,
          showTitle: false,
          onOpenManager: () {
            Navigator.pop(ctx); // 先关弹窗，别把管理页叠在弹窗上。
            if (context.mounted) _openPluginManager(context);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('已知悉')),
        ],
      ),
    );
  }

  @override
  Future<bool> confirmDisable(BuildContext context) async {
    // 返回 null（返回键 / 手势 / 点了「不同意」）→ 未作出同意，本组件维持启用。
    final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const RiskNoticePage(confirmMode: true)));
    return ok ?? false;
  }

  /// 拦截内容：结论 + 后果 + 两个并列出口（前往停用 / 查条款），不做诱导。
  /// [feature] 为被拦行为名称；[showTitle] = false 时标题由弹窗承担。
  Widget _notice(BuildContext context,
      {required String feature,
      required VoidCallback onOpenManager,
      bool showTitle = true}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.gpp_maybe_outlined, size: 30, color: SemColors.warning),
        const SizedBox(height: 8),
        if (showTitle) ...[
          const Text('风险提醒组件已启用',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        Text('依第三条第（一）项，受拦截行为不予执行：',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.5)),
        const SizedBox(height: 4),
        Text(feature,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('停用本组件，即视为已阅读并同意本条款全文；后果由用户自行承担（见第五条、第六条）。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: SemColors.danger, height: 1.5)),
        const SizedBox(height: 10),
        FilledButton.tonal(
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onOpenManager,
          child: const Text('前往插件管理页停用'),
        ),
        TextButton(
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact, foregroundColor: SemColors.accent),
          onPressed: () => _openNotice(context),
          child: Text('《${RiskTerms.title}》',
              style: const TextStyle(fontSize: 11.5, decoration: TextDecoration.underline)),
        ),
      ],
    );
  }
}
