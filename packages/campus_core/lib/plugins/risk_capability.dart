import 'package:flutter/material.dart';

import 'capability.dart';

/// 风险提醒能力（提供方：风险提醒插件 `PluginIds.risk`）。
///
/// 付款码 / 电费充值走的是非官方通道，可能触发校方风控或出现扣款与到账不一致；
/// 被拦的行为不予执行，只给引导。取用方在取不到能力时**放行**（没装就等于没这道闸）。
abstract class RiskNoticeCapability extends PluginCapability {
  const RiskNoticeCapability();

  /// 被拦行为的原位引导（校园码放进二维码区域）：一行结论 + 停用入口 + 条款全文。
  /// [feature] = 受拦截行为的名称（“校园码付款码” / “宿舍电费充值”），拼进正文。
  Widget blockedNotice(BuildContext context, {required String feature});

  /// 点按钮类操作的拦截弹窗（电费充值）：跳插件管理前会先关掉弹窗。
  Future<void> warnBlocked(BuildContext context, {required String feature});

  /// 停用风险提醒之前的条款确认：false = 用户未同意，维持启用。
  Future<bool> confirmDisable(BuildContext context);
}
