import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 工具页本地缓存：留住上一次成功拉到的接口原始 JSON，key 含查询参数。
class ToolPageCache {
  static const _prefix = 'tool_page_cache_v1_';

  /// 读某页缓存；没有 / 损坏 / 格式变化都返回 null。
  static Future<Map<String, dynamic>?> read(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_prefix$key');
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// 写某页缓存（失败静默：缓存只是体验优化）。
  static Future<void> write(String key, Map<String, dynamic> value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_prefix$key', jsonEncode(value));
    } catch (_) {}
  }

  /// 清空所有工具页缓存（退出登录 / 换账号）。
  static Future<void> clearAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = sp.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await sp.remove(k);
      }
    } catch (_) {}
  }
}
