/// 学工（zftal-xgxt）响应与登录页的解析：错误文案、加密盐、二课分数视图。
library;

import 'package:flutter/foundation.dart';

import 'http_session.dart';

/// 取 `<input ... name="x" value="y">` 的 value。
String? xgHiddenField(String html, String name) =>
    RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(html)?.group(1);

/// 加密盐：`<input ... pwdDefaultEncryptSalt value="...">` 或 JS 变量（不假设 id/value 顺序，单双引号都认）。
String xgFindSalt(String html) {
  final tag = RegExp(r'<input[^>]*pwdDefaultEncryptSalt[^>]*>', caseSensitive: false)
      .firstMatch(html)
      ?.group(0);
  if (tag != null) {
    final v = RegExp('''value\\s*=\\s*["']([^"']+)["']''').firstMatch(tag)?.group(1);
    if (v != null && v.isNotEmpty) return v;
  }
  return RegExp('''pwdDefaultEncryptSalt\\s*[:=]\\s*["']([^"']+)["']''').firstMatch(html)?.group(1) ??
      '';
}

/// 取不到加密盐时的诊断：把「请求到哪个页面、页面里有哪些要素」一并给出，便于分辨登录页改版。
String xgSaltError(HttpResult page, String html, String loginUrl) {
  const marks = {
    'pwdDefaultEncryptSalt': '盐字段名',
    'auth_login_btn': '登录按钮',
    'captchaImg': '验证码图',
    'execution': 'CAS 令牌',
    'username': '用户名框',
    'publicKey': '公钥',
  };
  final found = [for (final e in marks.entries) if (html.contains(e.key)) e.value];
  final at = html.toLowerCase().indexOf('salt');
  final snippet = at < 0
      ? '（整页没有 salt 字样）'
      : '…${html.substring((at - 80).clamp(0, html.length), (at + 80).clamp(0, html.length)).replaceAll(RegExp(r'\s+'), ' ')}…';
  return '统一认证登录页异常（请求 $loginUrl → HTTP ${page.status} · ${page.url} · ${html.length} 字）：'
      '${found.isEmpty ? '页面上没有登录表单要素' : '命中 ${found.join('/')}'}，'
      '但取不到加密盐 pwdDefaultEncryptSalt。$snippet';
}

/// 登录页上的可见错误文案；取不到返回 [fallback]。
///
/// 注释、script 与隐藏骨架（`#usernameError` 等静态提示）必须跳过，否则会把「请输入密码」误报成错误原因。
String xgLoginErrorTip(String html, String fallback) {
  final clean = html
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
      .replaceAll(RegExp(r'<script\b.*?</script>', dotAll: true, caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style\b.*?</style>', dotAll: true, caseSensitive: false), ' ');
  final hidden = RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden', caseSensitive: false);
  final rules = <RegExp>[
    RegExp(r'<[^>]*id="msg"[^>]*>(.*?)</(?:span|div)>', dotAll: true),
    RegExp(r'<[^>]*id="(?:username|password|cpatcha|captcha|login)Error"[^>]*>(.*?)</(?:span|div)>',
        dotAll: true),
    RegExp(r'<[^>]*class="[^"]*auth_error[^"]*"[^>]*>(.*?)</(?:span|div)>', dotAll: true),
  ];
  for (final re in rules) {
    for (final m in re.allMatches(clean)) {
      if (hidden.hasMatch(m.group(0)!)) continue;
      final msg = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (msg.isNotEmpty) return msg;
    }
  }
  debugPrint('[统一认证登录] 学校页面没有可读错误文案（${html.length} 字）');
  return fallback;
}

/// 二课分数接口响应 → 页面视图（学生信息 / 总分 / 学分 / 按德育分组的小计与明细）。
Map<String, dynamic> xgScoreView(Map j) {
  final queryModel = (j['queryModel'] as Map?) ?? const {};
  final items = (queryModel['items'] as List?) ?? const [];
  final header = (j['tableHeader'] as List?) ?? const [];
  if (items.isEmpty) {
    return {'student': {}, 'total': null, 'credit': null, 'groups': []};
  }
  final it = (items.first as Map?) ?? const {};
  final groups = <String, Map<String, dynamic>>{};
  for (final raw in header) {
    final h = raw is Map ? raw : const {};
    final fc = (h['fieldCode'] ?? '').toString();
    final name = (h['fieldName'] ?? fc).toString();
    final grp = (h['fieldTh'] ?? '其他').toString();
    if (['xh', 'xm', 'nj', 'bmmc', 'zymc', 'bjmc', 'zxs', 'sjxf', 'sjxs'].contains(fc)) {
      continue;
    }
    final g = groups.putIfAbsent(grp, () => {'subtotal': null, 'rows': []});
    if (fc.startsWith('dlxs')) {
      g['subtotal'] = it[fc];
    } else if (fc.startsWith('rdxs')) {
      (g['rows'] as List).add({'name': name, 'value': it[fc]});
    }
  }
  return {
    'student': {
      'xh': it['xh'],
      'xm': it['xm'],
      'nj': it['nj'],
      'bmmc': it['bmmc'],
      'zymc': it['zymc'],
      'bjmc': it['bjmc'],
    },
    'total': it['zxs'],
    'credit': it['sjxf'],
    'groups': [
      for (final e in groups.entries)
        {'name': e.key, 'subtotal': e.value['subtotal'], 'rows': e.value['rows']},
    ],
  };
}
