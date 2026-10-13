import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_notice_page.dart';
import 'risk_terms.dart';

/// 风险提醒能力的实现：拦截界面 + 停用前的条款确认。
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
    // 弹窗自带 Material 进出场动画（与全站其他弹窗一致）；标题由弹窗承担，
    // 内容里不再重复一行。
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('风险提醒组件已启用'),
        content: _notice(
          ctx,
          feature: feature,
          showTitle: false,
          onOpenManager: () {
            Navigator.pop(ctx); // 先关弹窗，别把管理页叠在弹窗上
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
    // 与别的二级页走同一条普通路由：进出动画、返回手势（含预测式返回）都跟全站一致。
    // 返回 null（返回键 / 手势 / 点了「不同意」）→ 未作出同意，本组件维持启用。
    final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const RiskNoticePage(confirmMode: true)));
    return ok ?? false;
  }

  /// 拦截内容：一行结论（受拦截行为不予执行）+ 一行后果 + 两个出口（前往停用 / 查条款）。
  /// 按告知同意的排法：先把后果说清，再给并列的出口，不做诱导。
  /// [feature] 是被拦行为的名称（第二条第（五）项 / 第（六）项的定义）。
  /// [showTitle] = 弹窗里由弹窗标题承担，内容里不再重复。
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
