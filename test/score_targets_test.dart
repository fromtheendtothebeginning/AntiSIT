import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二课达标线不再写死某一届：
/// * default 是兜底策略；
/// * cohorts 按入学年（nj）覆盖；
/// * 都没有时只显示实际分数（空策略）。
void main() {
  test('未知年级走 default 策略', () {
    final t = ScoreTargets.parse('''
{
  "default": {
    "total": 8,
    "groups": [{"keywords": ["德育"], "target": 3}],
    "subs": [{"keywords": ["讲座", "报告"], "target": 1.8}]
  }
}
''')!;
    final p = t.forCohort('2027');
    expect(p.total, 8);
    expect(p.groupFor('德育小计')?.target, 3);
    expect(p.groupFor('劳育小计'), isNull);
    expect(p.subFor('讲座报告'), 1.8);
  });

  test('年级覆盖优先于 default', () {
    final t = ScoreTargets.parse('''
{
  "default": {"total": 8},
  "cohorts": {"2027": {"total": 10, "label": "2027级"}}
}
''')!;
    expect(t.forCohort('2027').total, 10);
    expect(t.forCohort('2027').label, '2027级');
    expect(t.forCohort('2026').total, 8);
  });

  test('显式空策略 = 不比较（不是退回 default）', () {
    final t = ScoreTargets.parse('''
{"default": {"total": 8}, "cohorts": {"2028": {}}}
''')!;
    expect(t.forCohort('2028').isEmpty, isTrue);
  });

  test('没有 default、也没有该届 → 内置默认规则', () {
    final t = ScoreTargets.parse('{"cohorts": {}}')!;
    expect(t.forCohort('2027').total, 8);
  });

  test('内置兜底是现行默认规则（不绑定 2025）', () {
    final p = ScoreTargets.fallback().forCohort('2027');
    expect(p.total, 8);
    expect(p.groupFor('德育小计')?.target, 3.0);
    expect(p.label, isNull, reason: '默认规则不冒充某一届');
  });

  test('本机自定义优先于远端/默认，且只作用于对应年级', () {
    const t = ScoreTargets(
      defaultPolicy: ScoreTargetPolicy(total: 8),
      cohorts: {'2026': ScoreTargetPolicy(total: 10)},
      local: {
        '2027': ScoreTargetPolicy(total: 9),
        'default': ScoreTargetPolicy(total: 7),
      },
    );
    expect(t.forCohort('2027').total, 9, reason: '本机该届自定义');
    expect(t.forCohort('2026').total, 10, reason: '有年级时不吃本机 default');
    expect(t.forCohort('2025').total, 8, reason: '无该届时退回远端默认');
    expect(t.forCohort('').total, 7, reason: '未填年级才用本机 default');
    expect(t.localOverrideFor('2027')?.total, 9);
  });

  test('保存/清除本机自定义', () async {
    SharedPreferences.setMockInitialValues({});
    await ScoreTargets.saveLocalOverride('2027', const ScoreTargetPolicy(total: 9));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('score_targets_local_v1'), contains('2027'));
    await ScoreTargets.saveLocalOverride('2027', null);
    expect(sp.getString('score_targets_local_v1'), isNull);
  });

  test('非法 JSON 返回 null', () {
    expect(ScoreTargets.parse('not json'), isNull);
    expect(ScoreTargets.parse('[]'), isNull);
  });
}
