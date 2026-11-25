import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_core/campus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评教列表页的「缓存优先」：有缓存就直接显示，刷新只体现在顶部刷新条上，不能整页转圈把缓存盖掉。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const cachedTarget = EvalTarget(
    jxbId: 'J1',
    kchId: 'K1',
    jghId: 'G1',
    sfcjlrjs: '1',
    tjzt: '-1',
    course: '离散数学',
    teacher: '马秀莹',
    className: '2602121',
  );

  testWidgets('有缓存时进页立刻显示列表，不在整页 loading 里', (tester) async {
    await EvaluationCache.write(
      const [cachedTarget],
      const EvalSummary(pending: 1, saved: 0, submitted: 0),
    );

    await tester.pumpWidget(const MaterialApp(home: EvaluatePage()));
    // 只 pump 一帧：此时还在读缓存 / 联网，但缓存一旦读到就应当立刻出现
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 缓存里的课程必须已经画出来（不是「正在读取评教列表…」）
    expect(find.text('离散数学'), findsOneWidget);
    expect(find.text('马秀莹'), findsOneWidget);
    expect(find.textContaining('正在读取'), findsNothing);
    // 顶部刷新条可以显示「显示本地缓存」
    expect(find.byType(ToolRefreshBar), findsOneWidget);
  });

  // 测试环境没有真实服务器：无缓存时页面要么在加载、要么错误态，绝不能凭空显示课程。
  testWidgets('没有缓存时不会显示任何课程', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EvaluatePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('离散数学'), findsNothing);
  });
}