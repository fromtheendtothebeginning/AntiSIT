import 'package:plugin_evaluate/evaluate_api.dart';
import 'package:plugin_evaluate/evaluate_model.dart';

/// 批量打分的结果。
class BatchResult {
  const BatchResult({required this.done, required this.skipped, required this.failures});

  /// 成功保存的条数。
  final int done;

  /// 已提交、被跳过的条数。
  final int skipped;

  /// 失败原因（每条一行，带课程与教师）。
  final List<String> failures;

  bool get ok => failures.isEmpty;
}

/// 批量**提交**本轮全部「已保存 / 未评」的条目（不可撤销，调用方必须先做二次确认）。
///
/// 提交前先把分写好再提交：学校要求提交时请求里带着全部打分明细，
/// 所以每一条都是「取表单 → 按同一分数填 → 提交」。
Future<BatchResult> submitAllTargets({
  required EvaluateApi api,
  required List<EvalTarget> targets,
  required double score,
  void Function(String message)? onProgress,
}) async {
  var done = 0;
  var skipped = 0;
  final failures = <String>[];
  for (final t in targets) {
    if (t.submitted) {
      skipped++;
      continue;
    }
    onProgress?.call('${t.teacher} · ${t.course}');
    try {
      final form = await api.fetchForm(t);
      await api.submitForm(form, presetScores(form, score));
      done++;
    } catch (e) {
      failures.add('${t.teacher}（${t.course}）：$e');
    }
  }
  return BatchResult(done: done, skipped: skipped, failures: failures);
}

/// 给「本轮全部老师」统一打分并**保存**（不提交）。
///
/// 保存是可覆盖的写操作，批量做是安全的；提交不可撤销，所以这一步**绝不含提交**，
/// 提交留给用户逐条确认。已提交的条目会被跳过。
Future<BatchResult> fillAllTargets({
  required EvaluateApi api,
  required List<EvalTarget> targets,
  required double score,
  void Function(String message)? onProgress,
}) async {
  var done = 0;
  var skipped = 0;
  final failures = <String>[];
  for (final t in targets) {
    if (t.submitted) {
      skipped++;
      continue;
    }
    onProgress?.call('${t.teacher} · ${t.course}');
    try {
      final form = await api.fetchForm(t);
      await api.saveForm(form, presetScores(form, score));
      done++;
    } catch (e) {
      failures.add('${t.teacher}（${t.course}）：$e');
    }
  }
  return BatchResult(done: done, skipped: skipped, failures: failures);
}