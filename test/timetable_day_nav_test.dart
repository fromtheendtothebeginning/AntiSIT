import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/timetable_nav.dart';

/// 日视图底部导航的「上一天 / 下一天」要按全局日索引走。
///
/// 历史症状：上一天用 `idx ~/ 7, idx % 7 - 1`，周日索引 0 时 `0 - 1 == -1`，
/// 调用方 `clamp(0, …)` 把它压成 0 → 从第 2 周周一跳到**第 1 周周一**（跳过 6 天）。
void main() {
  Future<void> pumpNav(
    WidgetTester tester, {
    required int week,
    required int day,
    required void Function(int week, int day) onGoDay,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: buildDayNav(
          shownWeek: week,
          shownDay: day,
          weekCount: 20,
          onGoDay: onGoDay,
          onTitleTap: () {},
        ),
      ),
    ));
  }

  testWidgets('第 5 周周一：上一天 = 第 4 周周日（不是跳到第 1 周）', (tester) async {
    (int, int)? got;
    await pumpNav(tester, week: 5, day: 0, onGoDay: (w, d) => got = (w, d));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    // idx = (5-1)*7 + 0 = 28 → 上一天下标 27 → 第 4 周（27~/7=3 → week 4）、周日（27%7=6）
    expect(got, (4, 6));
  });

  testWidgets('第 1 周周一：上一天禁用（没有更早的一天）', (tester) async {
    (int, int)? got;
    await pumpNav(tester, week: 1, day: 0, onGoDay: (w, d) => got = (w, d));
    final btn = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.chevron_left), matching: find.byType(IconButton)));
    expect(btn.onPressed, isNull);
    expect(got, isNull);
  });

  testWidgets('第 5 周周日：下一天 = 第 6 周周一', (tester) async {
    (int, int)? got;
    await pumpNav(tester, week: 5, day: 6, onGoDay: (w, d) => got = (w, d));
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(got, (6, 0));
  });

  testWidgets('第 5 周周三：上下一天都在同一周内', (tester) async {
    (int, int)? up;
    (int, int)? down;
    await pumpNav(tester, week: 5, day: 2, onGoDay: (w, d) => up = (w, d));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(up, (5, 1));

    await pumpNav(tester, week: 5, day: 2, onGoDay: (w, d) => down = (w, d));
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(down, (5, 3));
  });
}
