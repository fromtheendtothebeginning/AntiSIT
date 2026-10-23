import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_grades/plugin_grades.dart';

/// 成绩卡标签的回归用例（issue #2）：学校对部分课程不回「课程类别 / 考核方式 / 学年学期」，
/// 老代码把这些 null 直接插值进标签文本，成绩卡上就出现一排写着字面量 "null" 的标签。
void main() {
  test('字段全缺：一个标签都不生成', () {
    expect(gradeTags({'kclbmc': null, 'khfsmc': null, 'xnmmc': null, 'xqmmc': null}), isEmpty);
  });

  test('只缺一部分：只少那一个标签，其余照常', () {
    expect(
      gradeTags({'kclbmc': '必修', 'khfsmc': null, 'xnmmc': '2026-2027学年', 'xqmmc': '3'}),
      ['必修', '2026-2027学年 第一学期'],
    );
  });

  test('空串 / 只有空格的字段同样不生成标签', () {
    expect(gradeTags({'kclbmc': ' ', 'khfsmc': '考试', 'xnmmc': '', 'xqmmc': ''}), ['考试']);
  });

  test('字段齐全：标签与以前一致，学期码 1/2 与旧版 3/12/16 都认', () {
    expect(
      gradeTags({'kclbmc': '必修', 'khfsmc': '考试', 'xnmmc': '2026-2027学年', 'xqmmc': '3'}),
      ['必修', '考试', '2026-2027学年 第一学期'],
    );
    expect(gradeTags({'xnmmc': '2025-2026学年', 'xqmmc': '12'}), ['2025-2026学年 第二学期']);
    expect(gradeTags({'xnmmc': '2026-2027学年', 'xqmmc': '16'}), ['2026-2027学年 短学期']);
  });

  test('缺学年但有学期码：只显示学期名', () {
    expect(gradeTags({'xnmmc': null, 'xqmmc': '3'}), ['第一学期']);
  });
}
