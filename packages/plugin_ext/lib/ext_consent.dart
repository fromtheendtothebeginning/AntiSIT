/// 拓展的运行时授权：静态 `permissions` 之外，真正敏感的动作再问一次用户。
///
/// 授权按「拓展 id + 能力」持久化；拒绝也会记住（避免每次打开都弹）。
/// 能力文案由 App 生成，拓展不能自定义——否则可以写一句假话骗用户点允许。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

class ExtConsentService {
  ExtConsentService._();

  static final ExtConsentService I = ExtConsentService._();

  static const String _prefix = 'plugin.ext.consent.';

  /// 同一个能力同时被请求多次时只弹一个框，其余等同一个结果。
  final Map<String, Future<bool>> _pending = <String, Future<bool>>{};

  String _key(String extId, String capability) => '$_prefix$extId.$capability';

  /// 授权记录的结构版本：2 起「没问过用户」不再被存成 false。
  static const String _schemaKey = 'plugin.ext.consent.schema';
  static const int _schema = 2;

  /// 一次性迁移：把旧版留下的**假拒绝**清掉。
  ///
  /// 旧版 `ensure` 在「弹不出来」（页面已关 / 在后台 / 没有 context）时也把 false
  /// 写进偏好，和用户真的点了「拒绝」长得一模一样。结果这些能力在权限页显示
  /// 「已拒绝」，插件那边 `status().granted === false`，于是自己把弹窗通知关了——
  /// 用户既没见过那个框，也没法在一次点击里恢复。
  ///
  /// 迁移只清掉 false 这一种：真拒绝的用户下次用到时会**再问一次**（就一次，
  /// 点了拒绝就照常记住），比留着一个他从未见过的「已拒绝」划算。
  static Future<void> migrateLegacyDenials() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt(_schemaKey) ?? 1) >= _schema) return;
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      if (prefs.getBool(key) == false) await prefs.remove(key);
    }
    await prefs.setInt(_schemaKey, _schema);
  }

  Future<Map<String, bool>> grants(String extId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$_prefix$extId.';
    final out = <String, bool>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      out[key.substring(prefix.length)] = prefs.getBool(key) ?? false;
    }
    return out;
  }

  Future<void> revoke(String extId, String capability) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(extId, capability));
  }

  /// 权限管理界面：用户直接打开 / 关闭某项授权。
  Future<void> allow(String extId, String capability) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(extId, capability), true);
  }

  Future<void> deny(String extId, String capability) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(extId, capability), false);
  }

  Future<void> revokeAll(String extId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$_prefix$extId.';
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await prefs.remove(key);
    }
  }

  /// 已授权返回 true；已拒绝返回 false；没记录就弹框问一次并记住结果。
  ///
  /// **问不到用户时（页面已关 / App 在后台 / 弹不出来）不落盘**：只返回 false，
  /// 下次真正能问的时候再问。早先这里把「问不到」当成用户点了「拒绝」存了下来，
  /// 于是后台定时器第一次触发（或页面刚好被关掉）就把这项能力**永久拒绝**了——
  /// 用户再也没见过那个框，permissions.status 一直报 false，插件只好把弹窗通知
  /// 关掉。这正是「插件用不了系统弹窗」的来源。
  Future<bool> ensure(
    BuildContext context, {
    required String extId,
    required String extName,
    required String capability,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(extId, capability);
    final saved = prefs.getBool(key);
    if (saved != null) return saved;

    final pendingKey = '$extId|$capability';
    final existing = _pending[pendingKey];
    if (existing != null) return existing;

    final future = () async {
      final answer = await _ask(context, extName, capability);
      if (answer != null) await prefs.setBool(key, answer);
      return answer ?? false;
    }();
    _pending[pendingKey] = future;
    try {
      return await future;
    } finally {
      _pending.remove(pendingKey);
    }
  }

  /// 弹框问一次。**问不到用户时返回 null**（调用方据此不落盘）：
  /// * 两个 context 都失效了（页面已经关掉，比如后台定时器触发的那一刻）；
  /// * App 不在前台——框弹出来了用户也看不见，等他回来就成了一条卡住的挂起请求。
  Future<bool?> _ask(
      BuildContext context, String extName, String capability) async {
    final target = _dialogContext(context);
    if (target == null) return null;
    final lifecycle = _lifecycleState();
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return null;
    return showDialog<bool>(
      context: target,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title(capability)),
        content: Text(body(extName, capability)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('允许'),
          ),
        ],
      ),
    );
  }

  /// 弹框挂在哪个 context 上：全局 navigator 优先（拓展页自己的 context 可能正好
  /// 在转场 / 已经失效，但那并不代表用户拒绝），退一步才用传进来的那个。
  /// 拿不到就返回 null——**不许**把「没有 context」当成拒绝。
  static BuildContext? _dialogContext(BuildContext context) {
    try {
      final host = navKey.currentContext;
      if (host != null) return host;
    } catch (_) {
      // 测试 / 还没有 MaterialApp：继续看调用方的 context
    }
    try {
      return context.mounted ? context : null;
    } catch (_) {
      // 失效的 context（页面已关）：它的 mounted 自己就会抛
      return null;
    }
  }

  /// 当前是否在前台。取不到（没有 binding 的测试环境）按「能问」处理。
  static AppLifecycleState? _lifecycleState() {
    try {
      return WidgetsBinding.instance.lifecycleState;
    } catch (_) {
      return null;
    }
  }

  /// 弹窗标题（App 文案，拓展不能改）。
  static String title(String capability) {
    if (capability == 'clipboard.read') return '读取剪贴板';
    if (capability.startsWith('net.host:')) {
      return '访问 ${capability.substring('net.host:'.length)}';
    }
    if (capability.startsWith('login.open:')) {
      return '打开 ${capability.substring('login.open:'.length)} 的登录页';
    }
    if (capability == 'background.keepalive') return '后台保持运行';
    if (capability == 'notification.popup') return '发送弹窗通知';
    return '授权请求';
  }

  /// 弹窗正文（App 文案，拓展不能改）。
  static String body(String extName, String capability) {
    if (capability == 'clipboard.read') {
      return '「$extName」想读取剪贴板。剪贴板里可能有验证码、链接或登录凭据，'
          '请确认这是你主动触发的操作。';
    }
    if (capability.startsWith('net.host:')) {
      final host = capability.substring('net.host:'.length);
      return '「$extName」想访问 $host。请求可能携带你保存在拓展里的登录凭据；'
          '只在你信任这个拓展、并且确实要它访问这个站点时允许。';
    }
    if (capability.startsWith('login.open:')) {
      final host = capability.substring('login.open:'.length);
      return '「$extName」想打开 $host 的登录页。登录完成后它会拿到你在该站点及其'
          '子域名下的 Cookie；只在你信任这个拓展时允许。';
    }
    if (capability == 'background.keepalive') {
      return '「$extName」想在后台保持运行，并显示一条常驻通知。'
          '只有你退到后台且没有关掉拓展页时才会继续刷新；关掉拓展页或点通知回 App 即可停止。';
    }
    if (capability == 'notification.popup') {
      return '「$extName」想在屏幕上弹出横幅通知（高优先级，会盖在其他应用上方）。'
          '只在你信任这个拓展时允许；之后可以在拓展菜单「运行时授权」里撤销。';
    }
    return '「$extName」请求一项需要确认的权限。';
  }

  /// 授权管理页展示用。
  static String describe(String capability) {
    if (capability == 'clipboard.read') return '读取剪贴板';
    if (capability.startsWith('net.host:')) {
      return '访问 ${capability.substring('net.host:'.length)}';
    }
    if (capability.startsWith('login.open:')) {
      return '登录 ${capability.substring('login.open:'.length)}';
    }
    if (capability == 'background.keepalive') return '后台保持运行';
    if (capability == 'notification.popup') return '发送弹窗通知';
    return capability;
  }
}
