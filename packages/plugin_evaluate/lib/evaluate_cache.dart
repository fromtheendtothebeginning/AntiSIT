import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'evaluate_model.dart';

/// 评教的本地缓存：列表走 [ToolPageCache]（退出登录一起清），
/// 已打的分单独存本机（教务不回填具体分数，重开表单时要默认显示上次那套）。
class EvaluationCache {
  EvaluationCache._();

  static const String _key = 'evaluate:list';

  /// 读上次缓存的列表与汇总；没有 / 损坏返回 null（当作首次进入）。
  static Future<({List<EvalTarget> targets, EvalSummary summary})?> read() async {
    final cached = await ToolPageCache.read(_key);
    if (cached == null) return null;
    final rawTargets = cached['targets'];
    if (rawTargets is! List) return null;
    final targets = <EvalTarget>[
      for (final raw in rawTargets)
        if (EvalTarget.tryParse(raw) case final t?) t,
    ];
    return (targets: targets, summary: EvalSummary.fromJson(cached['summary']));
  }

  /// 写缓存（失败静默：缓存只是体验优化）。
  static Future<void> write(List<EvalTarget> targets, EvalSummary summary) =>
      ToolPageCache.write(_key, {
        'targets': [for (final t in targets) t.toJson()],
        'summary': summary.toJson(),
      });
}

/// 本机记住的「我上次给这门课打的分」：指标 ID → 分数。
/// 记录里带**学号指纹**：换账号后旧分数不生效，不会把别人的分带过来。
class EvaluationLocalScores {
  EvaluationLocalScores._();

  static const String _prefix = 'evaluate_scores_v1_';

  /// 一条评教的本地键：教学班 + 教师（同一教学班可能有多位老师）。
  static String keyFor(EvalTarget target) => target.id;

  /// 当前学号（评教与 App 直连凭据共用同一份学号）。
  static String get _studentId => AppState.I.creds.studentId.trim();

  static Future<Map<String, double>?> read(EvalTarget target) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefix + _safe(keyFor(target)));
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final owner = (j['sid'] ?? '').toString();
      // 换了账号就当没有：别把上一个人的分数带过来
      if (owner.isNotEmpty && owner != _studentId) return null;
      final scores = j['scores'];
      if (scores is! Map) return null;
      final out = <String, double>{};
      scores.forEach((k, v) {
        final d = v is num ? v.toDouble() : double.tryParse(v.toString());
        if (d != null) out[k.toString()] = d;
      });
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(EvalTarget target, Map<String, double> scores) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _prefix + _safe(keyFor(target)),
        jsonEncode({'sid': _studentId, 'scores': scores}),
      );
    } catch (_) {}
  }

  /// 退出登录 / 换账号：把本机记的分一起清掉。
  static Future<void> clearAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in sp.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await sp.remove(k);
      }
    } catch (_) {}
  }

  /// SharedPreferences 的 key 里不适合塞长 ID：转成短哈希避免特殊字符。
  static String _safe(String raw) {
    var h = 0;
    for (final c in raw.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}