import 'dart:convert';

import 'package:campus_core/campus_core.dart';

/// 拓展安装码：`{"antisit":"ext","url":"https://…/x.zip","sha256":"64 位十六进制"}`，
/// 可选 `name` / `id` 只用于展示；只认 https，sha256 对不上就不下载安装。
ScanOutcome? extensionOutcomeOf(String code) {
  final text = code.trim();
  if (!text.startsWith('{')) {
    final uri = Uri.tryParse(text);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return ScanLinkOutcome(url: text, raw: text);
    }
    return null;
  }
  try {
    final raw = jsonDecode(text);
    if (raw is! Map) return null;
    final kind = '${raw['antisit'] ?? ''}'.trim();
    if (kind == 'source') return sourceOutcomeOf(raw, text);
    if (kind != 'ext') return null;
    final url = '${raw['url'] ?? ''}'.trim();
    final sha = '${raw['sha256'] ?? ''}'.trim().toLowerCase();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    final name = '${raw['name'] ?? ''}'.trim();
    final id = '${raw['id'] ?? ''}'.trim();
    return ScanBundleOutcome(
      url: url,
      sha256: sha,
      name: name.isEmpty ? null : name,
      id: id.isEmpty ? null : id,
      raw: text,
    );
  } catch (_) {
    return null;
  }
}

/// 第三方源安装码：`{"antisit":"source","repo":"owner/repo","fingerprint":"XXXX-XXXX-XXXX"}`。
ScanSourceOutcome? sourceOutcomeOf(Map raw, String text) {
  final repo = '${raw['repo'] ?? ''}'.trim();
  if (!validSourceRepo(repo)) return null;
  final rawFp = '${raw['fingerprint'] ?? ''}'
      .replaceAll('-', '')
      .trim()
      .toUpperCase();
  String? fingerprint;
  if (rawFp.isNotEmpty) {
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(rawFp)) return null;
    fingerprint = '${rawFp.substring(0, 4)}-${rawFp.substring(4, 8)}-'
        '${rawFp.substring(8, 12)}';
  }
  final branch = '${raw['branch'] ?? ''}'.trim();
  final name = '${raw['name'] ?? ''}'.trim();
  return ScanSourceOutcome(
    repo: repo,
    fingerprint: fingerprint,
    branch: branch.isEmpty ? null : branch,
    name: name.isEmpty ? null : name,
    raw: text,
  );
}

/// 源地址合法：https URL 或 owner/repo。
bool validSourceRepo(String repo) {
  if (repo.isEmpty) return false;
  if (repo.contains('://')) {
    final uri = Uri.tryParse(repo);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
  return RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repo);
}

/// 像安装码但字段可能不合法（用于给出「格式不对」而不是闷头当普通文本）。
bool looksLikeExtensionCodeOf(String code) {
  final text = code.trim();
  return text.startsWith('{') && text.contains('"antisit"');
}

/// 二课活动详情码 → hdId（门户 `/login?redirect=/hdgl/hdxq/:hdId` 包装也认）。
String? dektDetailIdOf(String code) {
  final u = Uri.tryParse(code.trim());
  if (u == null || u.host != 'xg.sit.edu.cn') return null;
  var path = u.path;
  if (path == '/login') {
    // 生成端可能整段百分号编码，queryParameters 解一层后按需再解一层
    final r = u.queryParameters['redirect'];
    if (r == null) return null;
    path = r.startsWith('/hdgl/') ? r : Uri.decodeComponent(r);
  }
  final m = RegExp(r'^/hdgl/hdxq/([\w-]+)$').firstMatch(path);
  return m?.group(1);
}

/// 门户包装形态：`https://xg.sit.edu.cn/login?redirect=/hdgl/…` → 内部完整地址。
/// 生成端可能把 redirect 整段百分号编码；不是包装形态返回 null。
String? unwrapLoginRedirect(String code) {
  final u = Uri.tryParse(code.trim());
  if (u == null || u.host != 'xg.sit.edu.cn' || u.path != '/login') return null;
  final r = u.queryParameters['redirect'];
  if (r == null || !r.startsWith('/hdgl/')) return null;
  return 'https://xg.sit.edu.cn$r';
}
