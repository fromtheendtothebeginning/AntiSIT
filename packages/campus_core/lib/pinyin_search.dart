import 'package:lpinyin/lpinyin.dart';

/// 「输入拼音搜汉字」的索引：原文 / 全拼 / 首字母任一命中即算匹配。
class PinyinSearchText {
  PinyinSearchText(this.source)
      : full = _full(source),
        short = _short(source);

  final String source;
  final String full;
  final String short;

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String _full(String s) => _norm(PinyinHelper.getPinyinE(
        s,
        separator: '',
        defPinyin: '',
        format: PinyinFormat.WITHOUT_TONE,
      ));

  static String _short(String s) {
    try {
      return _norm(PinyinHelper.getShortPinyin(s));
    } catch (_) {
      return ''; // 生僻字转不出：退化为仅原文 / 全拼匹配
    }
  }

  /// [query] 为空（或全空白）恒匹配。
  bool matches(String query) {
    final q = _norm(query);
    if (q.isEmpty) return true;
    if (source.toLowerCase().contains(q)) return true;
    if (full.contains(q)) return true;
    return short.isNotEmpty && short.contains(q);
  }
}

/// 列表过滤：[text] 取每条参与匹配的文本；[query] 为空时原样返回。
List<T> filterByPinyin<T>(List<T> items, String Function(T) text, String query) {
  final q = query.trim();
  if (q.isEmpty) return items;
  return [for (final it in items) if (PinyinSearchText(text(it)).matches(q)) it];
}
