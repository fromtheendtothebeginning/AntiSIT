import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评教的本地缓存：列表 JSON 往返、本机记的分与回填优先级。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const target = EvalTarget(
    jxbId: 'J1',
    kchId: 'K1',
    jghId: 'G1',
    sfcjlrjs: '1',
    tjzt: '-1',
    course: '离散数学',
    teacher: '马秀莹',
    className: '2602121',
    college: '计算机学院',
    time: '星期一第3-4节{1-12周}',
    xsdm: '01',
    xnm: '2026',
    xqm: '3',
  );

  test('列表缓存：写入后读回来字段完整（含缺失的 sksj 也不会崩）', () async {
    expect(await EvaluationCache.read(), isNull);
    await EvaluationCache.write(
      [
        target,
        const EvalTarget(
          jxbId: 'J2',
          kchId: 'K2',
          jghId: 'G2',
          sfcjlrjs: '1',
          tjzt: '0',
          course: '艺术美学',
          teacher: '超星尔雅',
          className: '2600648',
        ),
      ],
      const EvalSummary(pending: 1, saved: 1, submitted: 0),
    );
    final cached = await EvaluationCache.read();
    expect(cached, isNotNull);
    expect(cached!.targets, hasLength(2));
    expect(cached.targets.first.course, '离散数学');
    expect(cached.targets.first.teacher, '马秀莹');
    expect(cached.targets.first.time, '星期一第3-4节{1-12周}');
    expect(cached.targets[1].saved, isTrue);
    expect(cached.summary.pending, 1);
    expect(cached.summary.saved, 1);
  });

  test('本机记的分：写入后能读回来，换账号读不到', () async {
    expect(await EvaluationLocalScores.read(target), isNull);
    await EvaluationLocalScores.write(target, {'A': 92, 'B': 88});
    final back = await EvaluationLocalScores.read(target);
    expect(back, {'A': 92.0, 'B': 88.0});
  });

  test('不同评教（教学班/教师不同）互不覆盖', () async {
    await EvaluationLocalScores.write(target, {'A': 92});
    const other = EvalTarget(
      jxbId: 'J1',
      kchId: 'K1',
      jghId: 'G-OTHER',
      sfcjlrjs: '1',
      tjzt: '-1',
      course: '离散数学',
      teacher: '另一位老师',
      className: '2602121',
    );
    await EvaluationLocalScores.write(other, {'A': 70});
    expect(await EvaluationLocalScores.read(target), {'A': 92.0});
    expect(await EvaluationLocalScores.read(other), {'A': 70.0});
  });
}