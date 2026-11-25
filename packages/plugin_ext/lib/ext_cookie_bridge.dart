/// 通用登录页读取 Cookie 的通道（Android `CookieManager`）。
///
/// 只给 `ctx.login.open` 用：拓展声明要哪些域，登录完成后原样拿回这些域的 Cookie。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExtCookieBridge {
  static const MethodChannel _channel = MethodChannel('antisit/cookies');

  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, String>> read(List<String> urls) async {
    if (!supported) {
      throw UnsupportedError('登录页目前只支持 Android');
    }
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'get',
      {'urls': urls},
    );
    final out = <String, String>{};
    if (raw != null) {
      raw.forEach((key, value) {
        if (key == null) return;
        out['$key'] = value == null ? '' : '$value';
      });
    }
    return out;
  }

  static Future<void> clear() async {
    if (!supported) return;
    await _channel.invokeMethod<bool>('clear');
  }

  /// 只删这些域的 Cookie（`login.clear` 用）。
  ///
  /// `ok=false` 表示清完仍读得到 Cookie；`scoped=false` 表示按域精确删没清干净、
  /// **兜底清了整个 CookieStore**（别的 WebView 登录态也没了，要如实告诉用户）。
  static Future<({bool ok, bool scoped})> remove(List<String> urls) async {
    if (!supported) {
      throw UnsupportedError('登录页目前只支持 Android');
    }
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'remove',
      {'urls': urls},
    );
    return (
      ok: raw?['ok'] == true,
      scoped: raw?['scoped'] != false,
    );
  }

  /// 把各域的 `a=1; b=2` 按 [order] 从宽到窄合并；同名后写覆盖先写。
  static String mergeHeaders(Map<String, String> byUrl, List<String> order) {
    final merged = <String, String>{};
    for (final url in order) {
      final raw = byUrl[url] ?? '';
      for (final part in raw.split(';')) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        final name = part.substring(0, index).trim();
        final value = part.substring(index + 1).trim();
        if (name.isEmpty) continue;
        merged[name] = value;
      }
    }
    return merged.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  /// 一个主机名可能要删的域，从最长到最短（至少保留两级）。
  ///
  /// 学习通的登录态多是**父域 Cookie**（`Domain=.chaoxing.com`），只删 host-only
  /// 删不掉，所以按父域逐个下发；原生侧 `CookieBridge.removeCookies` 用同一套候选。
  static List<String> domainCandidates(String host) {
    final parts = host
        .trim()
        .toLowerCase()
        .split('.')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return [parts.join('.')];
    return [
      for (var i = 0; i <= parts.length - 2; i++)
        parts.sublist(i).join('.'),
    ];
  }
}
