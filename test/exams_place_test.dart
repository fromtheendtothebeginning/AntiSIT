import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_exams/plugin_exams.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 考试卡的考场要完整显示：和日期挤同一行时会被省略成「一教A…」，
/// 学生最需要看的教室号就没了。用例往缓存里灌一条考试，页面直接画出来。
void main() {
  testWidgets('考场单独一行、完整显示，不省略', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    // 关掉自动刷新：用例不碰网络，只画缓存里那一条
    await AppState.I.setAutoRefreshTools(false);
    addTearDown(() => AppState.I.setAutoRefreshTools(true));

    const place = '一教A201';
    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    await ToolPageCache.write('exams:$xnm:$xqm', {
      'exams': [
        {
          'name': '离散数学',
          'ksmc': '2627（1）期末考试（奉贤）',
          'date': '2026-12-11',
          'start': '13:00',
          'end': '14:40',
          'place': place,
          'seat': '41',
          'ksfs': '笔试',
        },
      ],
    });

    tester.view.physicalSize = const Size(1080, 2344);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExamsPage()));
    await tester.pumpAndSettle();

    final placeFinder = find.text(place);
    expect(placeFinder, findsOneWidget, reason: '考场文字要原样出现，不能是省略号');
    final paragraph = tester.renderObject<RenderParagraph>(placeFinder);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '考场被截断了：说明又和日期挤回同一行',
    );
    expect(find.text('座位 41'), findsOneWidget);
  });
}
