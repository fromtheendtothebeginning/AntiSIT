/// 电费查询历史的本机持久化：读取、追加（保留最近一年）与时间格式化。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 电费历史在 SharedPreferences 里的存储键。
const String electricityHistoryKey = 'direct_electricity_history';

/// 解析历史记录里的时间串；无法解析返回 null。
DateTime? parseHistoryTime(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString().replaceFirst(' ', 'T'));

/// 时间 →「yyyy-MM-dd HH:mm:ss」。
String formatHistoryTime(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// 读取电费历史（坏数据按空列表处理）。
List<Map<String, dynamic>> readElectricityHistory(SharedPreferences sp) {
  try {
    final raw = sp.getString(electricityHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    final arr = jsonDecode(raw);
    if (arr is List) return arr.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  } catch (_) {}
  return [];
}

/// 追加一条电费历史并清掉一年前的记录。
Future<void> appendElectricityHistory({
  double? balance,
  double? remain,
  required String dorm,
  double recharge = 0,
}) async {
  final sp = await SharedPreferences.getInstance();
  final records = readElectricityHistory(sp);
  records.add({
    'balance': balance,
    'remain': remain,
    'dorm': dorm,
    'time': formatHistoryTime(DateTime.now()),
    'recharge': recharge,
  });
  final cutoff = DateTime.now().subtract(const Duration(days: 366));
  records.removeWhere((r) => (parseHistoryTime(r['time']) ?? DateTime.now()).isBefore(cutoff));
  await sp.setString(electricityHistoryKey, jsonEncode(records));
}
