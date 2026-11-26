import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 当前年级：直连手填优先，其次传入年级，最后学籍缓存。
String resolveScoreCohort(String? passed) {
  if (AppState.I.direct) {
    final creds = AppState.I.creds.grade.trim();
    if (creds.isNotEmpty) return creds;
  }
  final passedCohort = (passed ?? '').trim();
  if (passedCohort.isNotEmpty) return passedCohort;
  final info = AppState.I.studentInfo;
  if (info != null) return '${info['nj'] ?? ''}'.trim();
  return '';
}

/// 解析一个达标线输入框：留空 = 不比较；非法或负数抛 [FormatException]。
double? parseScoreTarget(TextEditingController c) {
  final s = c.text.trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v < 0) {
    throw const FormatException('请输入不小于 0 的数字，留空表示不比较');
  }
  return v;
}

/// 达标线输入框的初值（空串表示不比较）。
String formatScoreTargetInput(num? v) => v == null
    ? ''
    : (v == v.roundToDouble() ? v.round().toString() : v.toString());
