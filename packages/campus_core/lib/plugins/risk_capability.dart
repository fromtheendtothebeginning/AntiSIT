import 'package:flutter/material.dart';

import 'capability.dart';

/// 风险提醒能力（提供方：风险提醒插件 `PluginIds.risk`，实现留在 `packages/plugin_risk`）。
///
/// 本 App 的两项行为走的是**非官方通道**（付款码来自第三方接口、电费充值走校园卡公网
/// 直连），可能触发校方风控、或出现扣款与到账不一致。「风险提醒」（默认启用）就是拦在
/// 这两件事前面的一道闸，其全部措辞与责任约定见《风险提醒组件条款》
/// （`packages/plugin_risk/lib/risk_terms.dart`，法律条文形式，先定义后使用）：
///
/// * 被拦的行为不予执行，只给出引导——一行结论 + 跳插件管理页停用 + 查阅条款全文；
/// * 停用属于用户自担风险，所以管理页停用它之前也要先经一遍条款确认（[confirmDisable]）。
///
/// 取用方式与其他能力一致：
/// `PluginRegistry.I.capability<RiskNoticeCapability>(PluginIds.risk)`
/// ——没装（包被删 / 被 EXCLUDE）或被用户停用时取到 null，取用方据此**放行**：
/// 没有风控组件就等于没装这道闸。
abstract class RiskNoticeCapability extends PluginCapability {
  const RiskNoticeCapability();

  /// 被拦行为的**原位引导**（校园码把它放进二维码区域）：
  /// 一行结论 + 「前往插件管理页停用」+ 「查阅条款全文」。
  /// [feature] = 受拦截行为的名称（第二条第（五）项 / 第（六）项的定义：
  /// “校园码付款码” / “宿舍电费充值”），拼进正文。
  Widget blockedNotice(BuildContext context, {required String feature});

  /// 点按钮类操作的拦截弹窗（电费充值）：[blockedNotice] 包成对话弹窗，
  /// 「前往插件管理页停用」会先关掉弹窗再跳插件管理。
  Future<void> warnBlocked(BuildContext context, {required String feature});

  /// 停用风险提醒之前的条款确认（插件管理页在停用它之前调用）：
  /// false = 用户未作出同意的意思表示，维持启用。
  Future<bool> confirmDisable(BuildContext context);
}
