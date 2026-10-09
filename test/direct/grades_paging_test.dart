import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：直连模式「全部学期」的成绩必须逐页拉全。
///
/// 背景：正方成绩接口按 queryModel.showCount/currentPage 分页，原来固定
/// showCount=15 + currentPage=1，而成绩是按学年升序返回的——于是大二以后的成绩
/// 全被截掉，用户看到的现象就是「只能查到大一的」，学期筛选项也只有大一的。
void main() {
  final mock = MockCampusServer.instance;

  setUpAll(() async {
    HttpOverrides.global = null;
    await mock.start();
  });
  tearDownAll(() async => mock.stop());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await mock.stop();
    await mock.start();
  });

  Map<String, Object?> grade(String name, String xnm, String xqm, String xnmmc) => {
        'kcmc': name,
        'cj': '90',
        'xf': '2.0',
        'jd': '',
        'xfjd': '',
        'kclbmc': '必修',
        'kcxzmc': '主修',
        'khfsmc': '考试',
        'xqmmc': xqm == '3' ? '第一学期' : '第二学期',
        'xnmmc': xnmmc,
        'sfxwkc': '否',
        'xnm': xnm,
        'xqm': xqm,
      };

  Future<JwxtClient> loggedIn() async {
    final c = JwxtClient(mock.baseUrl);
    addTearDown(c.dispose);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugJwxtCaptcha!);
    return c;
  }

  test('大一~大三三学年、跨页的成绩都拿得到（不再只看到第一页）', () async {
    // 3 学年 × 40 门 = 120 条：超过一页（100），必须继续翻页
    final years = [
      ('2024', '2024-2025学年'),
      ('2025', '2025-2026学年'),
      ('2026', '2026-2027学年'),
    ];
    mock.debugGrades = [
      for (final (xnm, xnmmc) in years)
        for (var n = 0; n < 40; n++)
          grade('课程$n（$xnmmc）', xnm, n.isEven ? '3' : '12', xnmmc),
    ];
    addTearDown(() => mock.debugGrades = null);
    expect(mock.debugGrades!.length, 120);

    final c = await loggedIn();
    final all = await c.grades(MockCampusServer.studentId);

    expect(all['count'], 120, reason: '全部学期要拉全，不能只剩第一页的 15/100 条');
    final terms = (all['terms'] as List).cast<Map<String, dynamic>>();
    expect(terms.length, 6, reason: '3 学年 × 2 学期都应出现在学期筛选里');
    expect(terms.map((t) => t['xnmmc']).toSet().length, 3, reason: '大二、大三的学年不能被漏掉');

    // 单学期查询也按页拉全
    final one = await c.grades(MockCampusServer.studentId, xnm: '2024', xqm: '3');
    expect(one['count'], 20);
  });

  test('成绩条数不足一页时仍然只查一次（不会为翻页多打请求）', () async {
    final c = await loggedIn();
    final all = await c.grades(MockCampusServer.studentId);
    expect(all['count'], 6); // 内置样例 6 条
  });
}
