import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 组 3（issue #13）的回归测试：**指示器与内容永远指向同一周**。
///
/// 历史症状：课程表内容停在第 1 周、周数指示器却是当前周。根因是 `_jumpTo`
/// 先把 `_shownWeek` 改成目标周、再延后跳页；跳页一旦没落地（PageView 还没挂上），
/// 指示器就永久跑在内容前面。
void main() {
  late int todayWeek;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    TimetablePage.todayResetAfter = const Duration(minutes: 30);

    // 学期起点 = 4 周前的周一，保证「今天」落在第 5 周左右（≠ 第 1 周，才看得出有没有跳）
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .subtract(const Duration(days: 28));
    final startISO = TimetableStore.iso(monday);
    todayWeek = TimetableStore.locateToday(startISO, 40)!;

    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: startISO,
        weekCount: 40,
        courses: const [],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  tearDown(() => TimetablePage.todayResetAfter = const Duration(minutes: 30));

  Future<void> pumpPage(WidgetTester tester, {ValueNotifier<int>? tab, int myTab = 0}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(activeTab: tab, myTab: myTab),
      ),
    );
    // 首页要等 load / syncCloud 这批 await 走完
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  /// 底部周切换条上的「第 N 周」。
  int shownWeek(WidgetTester tester) {
    final t = tester.widgetList<Text>(find.byType(Text)).firstWhere(
      (w) => (w.data ?? '').startsWith('第 ') && (w.data ?? '').endsWith(' 周'),
    );
    return int.parse(RegExp(r'\d+').firstMatch(t.data!)!.group(0)!);
  }

  testWidgets('冷启动直接落在本周（不是第 1 周），且指示器与内容一致', (tester) async {
    expect(todayWeek, greaterThan(1), reason: '测试前提：今天不在第 1 周');

    await pumpPage(tester);

    expect(shownWeek(tester), todayWeek, reason: '指示器应显示本周');
    // 周视图 PageView 落在第 todayWeek-1 页：内容与指示器同源
    final pv = tester.widget<PageView>(find.byType(PageView).first);
    expect(pv.controller!.page?.round(), todayWeek - 1,
        reason: '内容应停在本周那一页');
  });

  testWidgets('PageView 还没挂上就请求跳页：不丢，也不让指示器先跑', (tester) async {
    // 不 pump 完就切：模拟「数据慢 / 壳期」——_booting 期间只有转圈，没有 PageView
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump(); // 只走一帧：此时仍是 _booting 壳

    await tester.pumpAndSettle();

    expect(shownWeek(tester), todayWeek);
    final pv = tester.widget<PageView>(find.byType(PageView).first);
    expect(pv.controller!.page?.round(), todayWeek - 1,
        reason: '跳页不能静默丢失（旧实现 60 帧后放弃 -> 内容停在第 1 周）');
  });

  testWidgets('翻到别的周 → 立刻切走再回来：保留用户正在看的周', (tester) async {
    final tab = ValueNotifier<int>(0);
    addTearDown(tab.dispose);
    await pumpPage(tester, tab: tab);

    // 手动翻到下一周
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final flipped = shownWeek(tester);
    expect(flipped, todayWeek + 1);

    // 立刻切走再切回（远小于 30 分钟阈值）
    tab.value = 1;
    await tester.pumpAndSettle();
    tab.value = 0;
    await tester.pumpAndSettle();

    expect(shownWeek(tester), flipped, reason: '短暂来回切页不该把用户翻的周弹走');
  });

  testWidgets('离开一段时间后切回课表：自动回到本周', (tester) async {
    final tab = ValueNotifier<int>(0);
    addTearDown(tab.dispose);
    await pumpPage(tester, tab: tab);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(shownWeek(tester), todayWeek + 1);

    // 把阈值设成 0：等价于「离开了很久」
    TimetablePage.todayResetAfter = Duration.zero;
    tab.value = 1;
    await tester.pumpAndSettle();
    tab.value = 0;
    await tester.pumpAndSettle();

    expect(shownWeek(tester), todayWeek, reason: '回到课表应复位到本周');
    final pv = tester.widget<PageView>(find.byType(PageView).first);
    expect(pv.controller!.page?.round(), todayWeek - 1,
        reason: '内容也要跟着回到本周（不能只有指示器回去）');
  });
}
