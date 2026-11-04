import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 工具页本地缓存：把上一次成功拉到的接口数据留在本机。
///
/// 进入工具页先展示这份缓存，随后后台刷新，新数据到达后覆盖。只缓存接口原样
/// 返回的 JSON，不缓存派生 UI 状态；key 带上查询参数（学期、天数），不同筛选
/// 条件互不覆盖。
class ToolPageCache {
  static const _prefix = 'tool_page_cache_v1_';

  /// 读某页缓存；没有 / 损坏 / 格式变化都返回 null（当作首次进入）。
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

  /// 写某页缓存（失败静默：缓存只是体验优化，不影响数据本身）。
  static Future<void> write(String key, Map<String, dynamic> value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_prefix$key', jsonEncode(value));
    } catch (_) {}
  }

  /// 退出登录 / 换账号时清空所有工具页缓存：别把上一个账号的数据留给下一个人。
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
