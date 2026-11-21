import 'package:plugin_evaluate/evaluate_api.dart';
import 'package:plugin_evaluate/evaluate_cache.dart';
import 'package:plugin_evaluate/evaluate_model.dart';

/// 批量操作的结果。
class BatchResult {
  const BatchResult({
    required this.done,
    required this.skipped,
    required this.failures,
    this.unconfirmed = const [],
    this.checked = false,
  });

  /// 成功（并且复查通过）的条数。
  final int done;

  /// 已提交、被跳过的条数。
  final int skipped;

  /// 明确失败的条目（每条一行，带课程与教师）。
  final List<String> failures;

  /// 教务回了成功、但复查没看到状态变化的条目。
  final List<String> unconfirmed;

  /// 结束后是否真的复查过列表（网络异常时为 false，结果只能算「已发出」）。
  final bool checked;

  bool get ok => failures.isEmpty && unconfirmed.isEmpty;
}

/// 批量**提交**：把已经保存过的评教原样交上去（不可撤销，调用方必须先做二次确认）。
///
/// 口径（与表单页一致）：
/// * 分数取**这条评教自己的**已保存分（本机记的那份，退而求其次用页面回填值），
///   不再统一设分——用户点「全部提交」就是把已经保存好的内容交上去；
/// * 未保存的条目拿不到「已保存的分」，**绝不临时补分**，直接挡下来；
/// * 学校服务端对非法请求也会先回「成功」再静默丢弃，所以发完要复查列表才算数。
Future<BatchResult> submitAllTargets({
  required EvaluateApi api,
  required List<EvalTarget> targets,
  void Function(String message)? onProgress,
}) async {
  var done = 0;
  var skipped = 0;
  final failures = <String>[];
  final unconfirmed = <String>[];
  final sent = <EvalTarget>[];

  for (final t in targets) {
    if (t.submitted) {
      skipped++;
      continue;
    }
    if (!t.saved) {
      failures.add('${t.teacher}（${t.course}）：还没保存过，没有可提交的内容');
      continue;
    }
    onProgress?.call('${t.teacher} · ${t.course}');
    try {
      final form = await api.fetchForm(t);
      final scores = await _savedScoresFor(form, t);
      if (scores.isEmpty) {
        failures.add('${t.teacher}（${t.course}）：本机没有这套已保存的打分记录，'
            '无法照原样提交——请点开这一条确认分数并保存一次再提交');
        continue;
      }
      await api.submitForm(form, scores);
      done++;
      sent.add(t);
    } catch (e) {
      failures.add('${t.teacher}（${t.course}）：$e');
    }
  }

  // 复查：返回值不可信，以列表里的 tjzt 为准
  final after = await _recheck(api);
  if (after == null) {
    return BatchResult(
      done: done,
      skipped: skipped,
      failures: failures,
      checked: false,
    );
  }
  var confirmed = 0;
  for (final t in sent) {
    final match = after.where((x) => x.jxbId == t.jxbId);
    if (match.isNotEmpty && match.first.submitted) {
      confirmed++;
    } else {
      final now = match.isEmpty ? '列表里已经没有这条' : '仍是「${match.first.statusLabel}」';
      unconfirmed.add('${t.teacher}（${t.course}）：$now');
    }
  }
  return BatchResult(
    done: confirmed,
    skipped: skipped,
    failures: failures,
    unconfirmed: unconfirmed,
    checked: true,
  );
}

/// 给「本轮全部老师」统一打分并**保存**（不提交）。
///
/// 保存是可覆盖的写操作，批量做是安全的；提交不可撤销，所以这一步**绝不含提交**。
/// 打的分同时写一份到本机（[EvaluationLocalScores]）：之后点「全部提交」时，
/// 提交用的就是这里保存下来的这套分。
Future<BatchResult> fillAllTargets({
  required EvaluateApi api,
  required List<EvalTarget> targets,
  required double score,
  void Function(String message)? onProgress,
}) async {
  var done = 0;
  var skipped = 0;
  final failures = <String>[];
  final unconfirmed = <String>[];
  final sent = <EvalTarget>[];

  for (final t in targets) {
    if (t.submitted) {
      skipped++;
      continue;
    }
    onProgress?.call('${t.teacher} · ${t.course}');
    try {
      final form = await api.fetchForm(t);
      final scores = presetScores(form, score);
      await api.saveForm(form, scores);
      // 本机留一份：之后「全部提交」要按这套分原样提交
      await EvaluationLocalScores.write(t, scores);
      done++;
      sent.add(t);
    } catch (e) {
      failures.add('${t.teacher}（${t.course}）：$e');
    }
  }

  final after = await _recheck(api);
  if (after == null) {
    return BatchResult(
      done: done,
      skipped: skipped,
      failures: failures,
      checked: false,
    );
  }
  var confirmed = 0;
  for (final t in sent) {
    final match = after.where((x) => x.jxbId == t.jxbId);
    if (match.isNotEmpty && (match.first.saved || match.first.submitted)) {
      confirmed++;
    } else {
      final now = match.isEmpty ? '列表里已经没有这条' : '仍是「${match.first.statusLabel}」';
      unconfirmed.add('${t.teacher}（${t.course}）：$now');
    }
  }
  return BatchResult(
    done: confirmed,
    skipped: skipped,
    failures: failures,
    unconfirmed: unconfirmed,
    checked: true,
  );
}

/// 这条评教「已保存的分」：本机记的那份优先，没有就用页面回填的那份。
///
/// 两样都没有时返回空表——说明这条教务上标着已保存，但本机拿不到具体分数，
/// 调用方必须挡下来，不能凭空给一套分（那就成了「重新打分」，不是「提交已保存的」）。
Future<Map<String, double>> _savedScoresFor(EvalForm form, EvalTarget target) async {
  final local = await EvaluationLocalScores.read(target);
  final page = form.savedScores;
  final out = <String, double>{};
  for (final item in form.items) {
    final v = local?[item.id] ?? page[item.id];
    if (v != null) out[item.id] = item.snap(v);
  }
  return out;
}

/// 复查用：重新拉一次列表；失败返回 null（不把网络问题当成「没交上去」）。
Future<List<EvalTarget>?> _recheck(EvaluateApi api) async {
  try {
    return await api.fetchTargets();
  } catch (_) {
    return null;
  }
}
