import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_batch.dart';

/// 「全部打分」确认弹窗：返回选中的统一分数，取消返回 null。
Future<double?> showFillAllDialog(
  BuildContext context, {
  required int count,
  required double score,
}) async {
  var value = score;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('全部打分'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '把分数写进 $count 位老师的每一道题，并保存（不提交）。',
              style: const TextStyle(fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: value.toInt().toString(),
                    onChanged: (v) => setLocal(() => value = v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    value.toInt().toString(),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: SemColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '保存好之后，「全部提交」交的就是这套分——不会另设分数。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: SemColors.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始'),
          ),
        ],
      ),
    ),
  );
  return ok == true ? value : null;
}

/// 「全部提交」二次确认弹窗：返回是否确认（提交不可撤销）。
Future<bool> showSubmitAllConfirm(
  BuildContext context, {
  required int count,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('提交全部评教？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '把已保存的 $count 条评教原样提交（分数是你保存时打的那套）。',
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 8),
          const Text(
            '提交之后不能修改，也不能撤销。评教是匿名的：教师看不到你的具体打分。',
            style: TextStyle(fontSize: 11.5, height: 1.6),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('再想想'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认提交'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// 批量操作结果弹窗：失败与「回了成功但复查没变」分开列。
Future<void> showBatchResultDialog(
  BuildContext context, {
  required BatchResult result,
  required bool submitted,
}) async {
  final problems = [
    ...result.failures,
    for (final u in result.unconfirmed) '$u（教务回了成功，但复查没看到变化）',
  ];
  final String headline;
  if (!result.checked) {
    headline = '已发出 ${result.done} 条，但复查时没连上教务：'
        '请下拉刷新列表确认状态，别当成没提交又点一次。';
  } else if (submitted) {
    headline = problems.isEmpty
        ? '全部提交完成，列表里可以看到状态变成「已提交」。'
        : '已提交 ${result.done} 条，还有 ${problems.length} 条没成功。';
  } else {
    headline = problems.isEmpty
        ? '全部保存成功，现在可以点「全部提交」了。'
        : '已保存 ${result.done} 条，还有 ${problems.length} 条没成功。';
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${submitted ? '已提交 ' : '已保存 '}${result.done} 条'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.skipped > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已提交的 ${result.skipped} 条已跳过。',
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ),
          if (problems.isEmpty)
            Text(
              headline,
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(fontSize: 12.5, height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      problems.join('\n\n'),
                      style: const TextStyle(fontSize: 12.5, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
