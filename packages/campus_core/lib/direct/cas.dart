import 'dart:typed_data';

import 'crypto.dart';
import 'http_session.dart';

/// 金智（Wisedu）统一身份认证 CAS 登录：打开入口 → 登录页 → 加密提交 → 带 ticket 跳回业务系统。
///
/// Cookie 必须与业务系统共用同一个 [HttpSession]，否则 ticket 回跳时种的业务会话会丢。
class CasLogin {
  CasLogin({required this.http, required this.authBase});

  final HttpSession http;

  /// 配置里的统一认证地址（含 /authserver），仅作兜底：实际地址以登录页 URL 为准。
  final String authBase;

  Map<String, String> _fields = {};
  String _salt = '';
  String _action = '';

  /// 是否已经打开过 CAS 登录页（[open] 成功之后为 true）。
  bool get ready => _action.isNotEmpty;

  static int _ms() => DateTime.now().millisecondsSinceEpoch;

  /// 打开 [serviceUrl]（业务系统登录页里的统一认证入口），跟随跳转直到 CAS 登录页；
  /// false 表示最终拿到的不是 CAS 登录页（入口无效 / 已直接放行回业务系统）。
  Future<bool> open(String serviceUrl) async {
    final page = await http.get(serviceUrl);
    return adopt(page);
  }

  /// 解析一页响应为 CAS 登录表单；不是登录页返回 false。
  bool adopt(HttpResult page) {
    final html = page.text;
    final fields = <String, String>{};
    for (final name in ['execution', '_eventId', 'lt', 'rmShown', 'dllt', 'geolocation']) {
      final v = _hiddenField(html, name);
      if (v != null) fields[name] = v;
    }
    final salt = _findSalt(html);
    if (fields['execution'] == null && salt.isEmpty) return false;
    fields.putIfAbsent('dllt', () => 'userNamePasswordLogin');
    fields.putIfAbsent('_eventId', () => 'submit');
    _fields = fields;
    _salt = salt;
    _action = page.url.split('?').first;
    return true;
  }

  /// 取一张新的验证码图（authserver 的 captcha.html）。
  Future<Uint8List> captcha() async {
    final base = _casBase();
    final r = await http.get('$base/captcha.html?ts=${_ms()}');
    return r.body;
  }

  /// 提交登录（[password] 为统一认证密码原文）；返回 CAS 的跳转响应，业务登录态由调用方自行探活。
  Future<HttpResult> submit(String studentId, String password, String captcha) {
    if (!ready) throw StateError('CAS 登录页尚未打开');
    final pwd = _salt.isEmpty ? password : wiseduEncryptPassword(password, _salt);
    return http.postForm(
      _action,
      {
        ..._fields,
        'username': studentId,
        'password': pwd,
        'captchaResponse': captcha,
      },
      headers: {'Referer': _action},
    );
  }

  /// CAS 登录页上的可见错误文案（验证码错 / 密码错），取不到返回空串。
  ///
  /// 隐藏骨架（`#passwordError` 等）与脚本 / 注释必须跳过，否则会把静态提示当成登录判定结果。
  static String errorTip(String html) {
    final clean = html
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(RegExp(r'<script\b.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style\b.*?</style>', dotAll: true, caseSensitive: false), ' ');
    final hidden = RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden', caseSensitive: false);
    for (final re in <RegExp>[
      RegExp(r'<[^>]*id="msg"[^>]*>(.*?)</(?:span|div)>', dotAll: true),
      RegExp(r'<[^>]*id="(?:username|password|cpatcha|captcha|login)Error"[^>]*>(.*?)</(?:span|div)>',
          dotAll: true),
      RegExp(r'<[^>]*class="[^"]*auth_error[^"]*"[^>]*>(.*?)</(?:span|div)>', dotAll: true),
    ]) {
      for (final m in re.allMatches(clean)) {
        if (hidden.hasMatch(m.group(0)!)) continue;
        final msg = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (msg.isNotEmpty) return msg;
      }
    }
    return '';
  }

  String _casBase() {
    if (ready) {
      final u = Uri.parse(_action);
      final path = u.path.replaceFirst(RegExp(r'/login/?$'), '');
      if (path.isNotEmpty) return '${u.origin}$path';
    }
    return authBase.replaceAll(RegExp(r'/+$'), '');
  }

  static String? _hiddenField(String html, String name) =>
      RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(html)?.group(1);

  static String _findSalt(String html) {
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
}
