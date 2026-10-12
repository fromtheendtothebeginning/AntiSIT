import 'package:flutter/material.dart';

import 'capability.dart';

/// 风险提醒能力（提供方：风险提醒插件 `PluginIds.risk`，实现留在 `packages/plugin_risk`）。
///
/// 本 App 的两项高风险功能走的是**非官方通道**（付款码来自第三方接口、电费充值走
/// 校园卡公网直连），可能触发学校风控、或出现扣款与到账不一致。「风险提醒」
/// （默认开启）就是拦在这两件事前面的一道闸：
///
/// * 被拦的功能不直接放行，而是给出引导——说明 + 跳插件管理关掉它 + 看条款；
/// * 关闭属于用户自担风险，所以管理页停用它之前也要先过一遍条款确认（[confirmDisable]）。
///
/// 取用方式与其他能力一致：
/// `PluginRegistry.I.capability<RiskNoticeCapability>(PluginIds.risk)`
/// ——没装（包被删 / 被 EXCLUDE）或被用户停用时取到 null，取用方据此**放行**：
/// 没有风控组件就等于没装这道闸。
abstract class RiskNoticeCapability extends PluginCapability {
  const RiskNoticeCapability();

  /// 被拦功能的**原位引导**（校园码把它放进二维码区域）：
  /// 一句说明 + 「去关闭」+ 「看条款」。
  /// [feature] = 被拦的功能名（“校园码付款码” / “宿舍电费充值”），拼进说明文案。
  Widget blockedNotice(BuildContext context, {required String feature});

  /// 点按钮类操作的拦截弹窗（电费充值）：[blockedNotice] 包成对话弹窗，
  /// 「去关闭」会先关掉弹窗再跳插件管理。
  Future<void> warnBlocked(BuildContext context, {required String feature});

  /// 关闭风险提醒之前的条款确认（插件管理页在停用它之前调用）：
  /// false = 用户没同意，不要关。
  Future<bool> confirmDisable(BuildContext context);
}
