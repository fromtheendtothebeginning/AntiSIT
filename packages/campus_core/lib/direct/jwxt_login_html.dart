/// 教务 / 统一认证登录页的 HTML 诊断：取学校原文错误提示与定位片段。
library;

import 'package:flutter/foundation.dart';

import 'http_session.dart';

/// 学校登录页上的可见错误文案（取不到返回空串）。
///
/// 注释、script 与隐藏骨架都必须跳过，否则「请输入密码」会被误报成账号密码错误。
String schoolLoginTip(String html) {
  final clean = stripLoginPageNoise(html);
  final obj = RegExp(r'验证码|密码|账号|用户名');
  final err = RegExp(r'错误|不正确|失效|过期|为空|不存在|无效|请输入');
  final hidden = RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden', caseSensitive: false);
  // 闭合标签按同名标签配对：`#tips` 里先有空 `<span>` 时，匹配任意闭合标签只会拿到空串。
  for (final re in <RegExp>[
    RegExp(r'<([a-zA-Z][\w]*)\b[^>]*id="(?:tips|msg|tipsMsg|errorMsg|loginError)"[^>]*>(.*?)</\1>',
        dotAll: true),
    RegExp(r'<([a-zA-Z][\w]*)\b[^>]*class="[^"]*(?:tips|error|msg)[^"]*"[^>]*>(.*?)</\1>',
        dotAll: true),
  ]) {
    for (final m in re.allMatches(clean)) {
      if (hidden.hasMatch(m.group(0)!)) continue;
      final t = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (t.isEmpty) continue;
      if (!obj.hasMatch(t) || !err.hasMatch(t)) continue;
      return t;
    }
  }
  for (final m in RegExp(r'>([^<>]{1,60})<').allMatches(clean)) {
    final t = m.group(1)!.trim();
    if (t.isEmpty) continue;
    if (!obj.hasMatch(t)) continue;
    if (!err.hasMatch(t)) continue;
    if (_enclosingTagHidden(clean, m.start, hidden)) continue;
    return t;
  }
  return '';
}

/// [textStart] 处文本的直接外层开始标签里是否带隐藏样式。
bool _enclosingTagHidden(String html, int textStart, RegExp hidden) {
  final open = html.lastIndexOf('<', textStart);
  if (open < 0) return false;
  final close = html.indexOf('>', open);
  if (close < 0 || close > textStart) return false;
  return hidden.hasMatch(html.substring(open, close + 1));
}

/// 登录失败提示：学校给了原文就用原文，取不到则如实说明并附页面片段。
String loginErrorMessage(HttpResult r) {
  final tip = schoolLoginTip(r.text);
  debugPrint('[教务登录] HTTP ${r.status} tip=[$tip] ${loginPageSnippet(r.text)}');
  if (tip.isNotEmpty) return tip;
  return '教务登录未通过（HTTP ${r.status}，学校登录页没有错误文案，可能是登录页改版）：'
      '${loginPageSnippet(r.text)}';
}

/// 登录页 HTML 去噪：注释、script、style 与隐藏元素整块删掉（html / body 例外）。
///
/// html / body 例外是因为正方新版用 `<body style="display:none">` 防闪屏，整块删会把正文删掉。
String stripLoginPageNoise(String html) => html
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
    .replaceAll(RegExp(r'<script\b.*?</script>', dotAll: true, caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<style\b.*?</style>', dotAll: true, caseSensitive: false), ' ')
    .replaceAll(
        RegExp(
            r'<(?!html\b|body\b)(\w+)\b[^>]*(?:display\s*:\s*none|visibility\s*:\s*hidden)[^>]*>[\s\S]*?</\1>',
            dotAll: true,
            caseSensitive: false),
        ' ');

/// 页面片段（压掉空白、限长）：窗口对准「错误 / 密码 / 验证码」等关键词。
String loginPageSnippet(String html) {
  final text = stripLoginPageNoise(html).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '（学校返回了空页面）';
  var at = -1;
  for (final kw in ['错误', '不正确', '无效', '验证码', '失败']) {
    at = text.indexOf(kw);
    if (at >= 0) break;
  }
  final start = (at < 0 ? 0 : at - 60).clamp(0, text.length);
  final end = (start + 160).clamp(0, text.length);
  return '${start > 0 ? '…' : ''}${text.substring(start, end).trim()}'
      '${end < text.length ? '…' : ''}';
}
