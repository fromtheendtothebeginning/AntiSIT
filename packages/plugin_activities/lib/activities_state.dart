import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 报名窗口状态：按本机时间对 bm_start / bm_end 判断。
enum ActivityState { signing, upcoming, ended }

/// 报名按钮的不可报名状态：学校已明确给出原因（名额满 / 资格不符）。
enum SignupBlock { full, ineligible }

/// 活动快照的报名窗口状态。
ActivityState activityStateOf(Map<String, dynamic> a) {
  DateTime? p(dynamic s) {
    final str = s?.toString() ?? '';
    return str.isEmpty ? null : DateTime.tryParse(str.replaceAll(' ', 'T'));
  }

  final now = DateTime.now();
  final bs = p(a['bm_start']);
  final be = p(a['bm_end']);
  if (bs != null && now.isBefore(bs)) return ActivityState.upcoming;
  if (be != null && now.isAfter(be)) return ActivityState.ended;
  return ActivityState.signing;
}

/// 状态的展示文案。
String activityStateText(ActivityState s) => switch (s) {
  ActivityState.signing => '报名中',
  ActivityState.upcoming => '即将报名',
  ActivityState.ended => '报名已结束',
};

/// 状态的展示颜色。
Color activityStateColor(ActivityState s) => switch (s) {
  ActivityState.signing => SemColors.success,
  ActivityState.upcoming => SemColors.accent,
  ActivityState.ended => SemColors.textMuted,
};

/// 卡片状态胶囊文案：报名中且名额已满时显示「已人满」。
String marketStateText(Map<String, dynamic> a) {
  final st = activityStateOf(a);
  return st == ActivityState.signing && isFullSignup(a)
      ? '已人满'
      : activityStateText(st);
}

/// 卡片状态胶囊颜色。
Color marketStateColor(Map<String, dynamic> a) {
  final st = activityStateOf(a);
  return st == ActivityState.signing && isFullSignup(a)
      ? SemColors.danger
      : activityStateColor(st);
}

/// 校区胶囊文字；「未标注」（学校没写校区）返回空串，调用方据此不画胶囊。
String campusTagOf(Map a) {
  final c = '${a['campus'] ?? ''}'.trim();
  return c.isEmpty || c == '未标注' || c == 'null' ? '' : c;
}

/// 「大类 · 小类」：缺哪项就不显示哪项，两个都没有返回空串（不画这一行）。
String categoryTextOf(Map a) => [
  '${a['dlmc'] ?? ''}'.trim(),
  '${a['lbmc'] ?? ''}'.trim(),
].where((s) => s.isNotEmpty && s != 'null').join(' · ');

/// 活动时间的短展示：取「MM-DD HH:MM」，短于 16 位时原样返回。
String shortTimeText(Object? s) {
  final str = '$s';
  return str.length >= 16 ? str.substring(5, 16) : str;
}

/// 学校报名失败文案 → 按钮状态。识别不出返回 null（保持原来的错误弹窗）。
SignupBlock? signupBlockOfError(String msg) {
  if (RegExp(r'名额|人数|已满|满员|人满').hasMatch(msg)) return SignupBlock.full;
  if (RegExp(r'条件|资格|不符|不满足').hasMatch(msg)) return SignupBlock.ineligible;
  return null;
}
