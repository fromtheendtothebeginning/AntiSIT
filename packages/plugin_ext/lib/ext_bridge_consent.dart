import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'ext_background.dart';
import 'ext_consent.dart';
import 'ext_cookie_bridge.dart';
import 'ext_login_page.dart';
import 'extension_item.dart';

/// 运行时授权：静态权限之外，剪贴板 / 特定域名这类动作再让用户确认一次。
Future<bool> askExtConsent({
  required BuildContext context,
  required String extId,
  required ExtensionItem? item,
  required String capability,
}) =>
    ExtConsentService.I.ensure(
      context,
      extId: extId,
      extName: item?.name ?? extId,
      capability: capability,
    );

/// 同 [askExtConsent]，用户拒绝时抛错回网页（调用方不应继续）。
Future<void> ensureExtConsent({
  required BuildContext context,
  required String extId,
  required ExtensionItem? item,
  required String capability,
}) async {
  final allowed = await askExtConsent(
    context: context,
    extId: extId,
    item: item,
    capability: capability,
  );
  if (!allowed) {
    throw ArgumentError('用户没有允许这项操作（$capability）');
  }
}

/// `permissions.*` 通道：显式申请 / 查询运行时授权，只认白名单能力键。
class ExtPermissionChannel {
  ExtPermissionChannel({
    required this.context,
    required this.extId,
    required this.item,
  });

  final BuildContext context;
  final String extId;
  final ExtensionItem? item;

  static const Set<String> _simpleCapabilities = {
    'notification.popup',
    'clipboard.read',
    'background.keepalive',
  };

  /// 把 `{name, host?}` 解析成内部能力键；只认白名单，避免拓展写任意键。
  static String _capabilityFromArgs(Object? args) {
    if (args is String) return _validateCapability(args.trim());
    if (args is! Map) throw ArgumentError('permissions 要带 {name}');
    final name = '${args['name'] ?? ''}'.trim();
    if (name == 'net.host' || name == 'login.open') {
      final host = '${args['host'] ?? ''}'.trim().toLowerCase();
      if (host.isEmpty || !RegExp(r'^[a-z0-9.-]+$').hasMatch(host)) {
        throw ArgumentError('$name 要带合法 host');
      }
      return '$name:$host';
    }
    return _validateCapability(name);
  }

  static String _validateCapability(String name) {
    if (_simpleCapabilities.contains(name)) return name;
    throw ArgumentError('不认识的能力：$name');
  }

  Future<Object?> request(Object? args) async {
    final capability = _capabilityFromArgs(args);
    final granted = await askExtConsent(
      context: context,
      extId: extId,
      item: item,
      capability: capability,
    );
    return {'name': capability, 'granted': granted};
  }

  Future<Object?> status(Object? args) async {
    final capability = _capabilityFromArgs(args);
    final grants = await ExtConsentService.I.grants(extId);
    return {'name': capability, 'granted': grants[capability]};
  }
}

/// 服务器模式下的校园隧道代理（`http://host:port`）；直连 / 演示 / 没连上都返回空串。
Future<String> campusProxyUrl() async {
  try {
    final state = AppState.I;
    if (state.demo || state.direct) return '';
    return await ApiClient.I.serverWebProxy();
  } catch (_) {
    return '';
  }
}

/// 打开一个可见的登录页，完成后只返回拓展声明的域名的 Cookie。
Future<Object?> loginOpen({
  required BuildContext context,
  required String extId,
  required ExtensionItem? item,
  required Object? args,
}) async {
  if (args is! Map) throw ArgumentError('login.open 要带 {url}');
  if (!ExtCookieBridge.supported) {
    throw ArgumentError('登录页目前只支持 Android');
  }
  final start = ExtLoginPage.parseHttpsUrl('${args['url'] ?? ''}');
  final cookieUrls = <String>[];
  final raw = args['cookieUrls'];
  if (raw is List) {
    for (final entry in raw) {
      final uri = ExtLoginPage.parseHttpsUrl('$entry');
      if (!ExtLoginPage.sameSite(start.host, uri.host)) {
        throw ArgumentError('cookieUrls 必须与登录地址同站：${uri.host}');
      }
      cookieUrls.add(uri.toString());
    }
  }
  if (cookieUrls.isEmpty) cookieUrls.add(start.toString());

  await ensureExtConsent(
    context: context,
    extId: extId,
    item: item,
    capability: 'login.open:${start.host}',
  );
  if (!context.mounted) throw StateError('页面已关闭');
  final result = await Navigator.of(context).push<Map<String, Object?>>(
    MaterialPageRoute(
      builder: (_) => ExtLoginPage(
        title: '${args['title'] ?? '登录'}',
        startUrl: start.toString(),
        cookieUrls: cookieUrls,
        successUrlPrefix: args['successUrlPrefix']?.toString(),
        successCookie: args['successCookie']?.toString(),
        userAgent: args['userAgent']?.toString(),
      ),
    ),
  );
  if (result == null) throw ArgumentError('没有完成登录');
  return result;
}

/// 退出登录：把这些域的 Cookie 从系统 CookieStore 删掉，返回 `{ok, scoped}`。
///
/// 按域精确删没清干净时会兜底清整个 CookieStore（`scoped=false`）：宁可多清，
/// 也不要「退出成功、一点登录又回到原账号」。
Future<Object?> loginClear({
  required BuildContext context,
  required String extId,
  required ExtensionItem? item,
  required Object? args,
}) async {
  if (args is! Map) throw ArgumentError('login.clear 要带 {cookieUrls}');
  if (!ExtCookieBridge.supported) {
    throw ArgumentError('登录页目前只支持 Android');
  }
  final urls = <String>[];
  final raw = args['cookieUrls'];
  if (raw is List) {
    for (final entry in raw) {
      final uri = ExtLoginPage.parseHttpsUrl('$entry');
      urls.add(uri.toString());
    }
  }
  if (urls.isEmpty) throw ArgumentError('login.clear 要带至少一个 cookieUrls');
  await ensureExtConsent(
    context: context,
    extId: extId,
    item: item,
    capability: 'login.open:${Uri.parse(urls.first).host}',
  );
  final outcome = await ExtCookieBridge.remove(urls);
  return {'ok': outcome.ok, 'scoped': outcome.scoped};
}

/// 后台保活：开启前先要用户同意；关闭时直接停前台服务。
Future<Object?> backgroundKeepAlive({
  required BuildContext context,
  required String extId,
  required ExtensionItem? item,
  required Object? args,
}) async {
  final map = args is Map ? args : const {};
  final enabled = map['enabled'] != false;
  if (!enabled) {
    await ExtBackgroundKeepAlive.stop();
    return false;
  }
  await ensureExtConsent(
    context: context,
    extId: extId,
    item: item,
    capability: 'background.keepalive',
  );
  final ok = await ExtBackgroundKeepAlive.start(
    title: '${map['title'] ?? item?.name ?? '拓展'}',
    text: '${map['text'] ?? '正在后台刷新'}',
  );
  return ok;
}
