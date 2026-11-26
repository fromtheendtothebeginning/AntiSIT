import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'json_num.dart';

/// 二课分数快照（/score 的 data 节点）。
class ScoreSnapshot {
  const ScoreSnapshot._(this.raw);

  factory ScoreSnapshot.fromJson(Map<String, dynamic> j) => ScoreSnapshot._(j);

  final Map<String, dynamic> raw;

  /// 已得分 / 达标分（缺字段按 0）；学工接口这两个字段是字符串（如 "8.0"）。
  num get credit => asNum(raw['credit']) ?? 0;
  num get total => asNum(raw['total']) ?? 0;

  /// 学籍信息节点（院系 / 专业 / 班级），「我的 → 学籍信息」用。
  Map<String, dynamic>? get student => raw['student'] is Map<String, dynamic>
      ? raw['student'] as Map<String, dynamic>
      : null;
}

/// 宿舍电费快照（/electricity/query 的 data 节点）。
class ElectricitySnapshot {
  const ElectricitySnapshot._(this.raw);

  factory ElectricitySnapshot.fromJson(Map<String, dynamic> j) =>
      ElectricitySnapshot._(j);

  final Map<String, dynamic> raw;

  /// 当前余额（元）。
  num get balance => asNum(raw['balance']) ?? 0;
}

/// 工具页与子页共享的缓存数值（宫格卡面速览），同时写闪存供冷启动使用。
class ToolCache {
  static const _scoreKey = 'tool_cache_score';
  static const _electricityKey = 'tool_cache_electricity';

  static ScoreSnapshot? _score;
  static ElectricitySnapshot? _electricity;

  static ScoreSnapshot? get score => _score;
  static ElectricitySnapshot? get electricity => _electricity;

  static set score(ScoreSnapshot? v) {
    _score = v;
    unawaited(_persist(_scoreKey, v?.raw));
  }

  static set electricity(ElectricitySnapshot? v) {
    _electricity = v;
    unawaited(_persist(_electricityKey, v?.raw));
  }

  /// data 节点缺失 / 类型不对时给 null，把判空集中在这一处。
  static ScoreSnapshot? scoreOf(Object? data) =>
      data is Map<String, dynamic> ? ScoreSnapshot.fromJson(data) : null;

  static ElectricitySnapshot? electricityOf(Object? data) =>
      data is Map<String, dynamic> ? ElectricitySnapshot.fromJson(data) : null;

  /// 启动时读回上次的快照（失败当作没有，不影响后续刷新）。
  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final score = _decode(sp.getString(_scoreKey));
      if (score != null) _score = ScoreSnapshot.fromJson(score);
      final ele = _decode(sp.getString(_electricityKey));
      if (ele != null) _electricity = ElectricitySnapshot.fromJson(ele);
    } catch (_) {}
  }

  /// 退出登录 / 换账号时清空，别把上一个账号的数据留给下一个人。
  static Future<void> clear() async {
    _score = null;
    _electricity = null;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_scoreKey);
      await sp.remove(_electricityKey);
    } catch (_) {}
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persist(String key, Map<String, dynamic>? raw) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (raw == null) {
        await sp.remove(key);
      } else {
        await sp.setString(key, jsonEncode(raw));
      }
    } catch (_) {}
  }
}
