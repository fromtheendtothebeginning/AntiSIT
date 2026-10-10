import 'package:campus_core/campus_core.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：点课程表上方的「课程表 · 大X上/下」就能切换学期
/// （打开的就是右上角菜单里那一项用的同一个学期选择器）。
void main() {
  // 页面初始化会采用「按今天推断的学期」，所以课就放在那个学期里；
  // 拿它同年的另一个学期当「切过去的目标」（两个都取得到「大X上/下」的标签）。
  const nj = '2025';
  late String activeKey;
  late String otherKey;
  late String otherLabel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    TimetableStore.instance.nj = nj; // 入学年：决定「大一上~大四下」怎么换算

    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    activeKey = '$xnm-$xqm';
    otherKey = xqm == '12' ? '$xnm-3' : '$xnm-12';
    otherLabel = TimetableStore.instance.semesterLabel(otherKey)!;

    final monday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    TimetableStore.instance.semesters = {
      activeKey: SemesterTt(
        startDate: TimetableStore.iso(monday),
        weekCount: 20,
        courses: [
          TtCourse(
            id: 'c1',
            name: '数据库原理及应用',
            day: 0,
            slotStart: 0,
            slotEnd: 1,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 20,
            place: '二教H102',
          ),
        ],
      ),
      // 切过去的目标：空课表，切换后旧学期的课应该看不见了
      otherKey: SemesterTt(startDate: TimetableStore.iso(monday), weekCount: 20),
    };
    TimetableStore.instance.active = activeKey;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 高一点：课表格子（第 1 节 08:20）要真的被构建出来
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 当前 AppBar 上的标题文字（=「课程表 · 学期」）
  String title(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.byType(Text)).first)
      .data!;

  /// 选择器里列的文案是通用学年标签（标题才用「大二上/下」这种，见下）
  String genericLabel(String key) {
    final p = key.split('-');
    final xn = int.parse(p[0]);
    return '$xn-${xn + 1}学年 ${p[1] == '3' ? '第一' : '第二'}学期';
  }

  Future<void> tapTitle(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
  }

  testWidgets('标题本身就是入口：右边带箭头，点开「选择学期」', (tester) async {
    await pumpPage(tester);

    expect(title(tester), startsWith('课程表'), reason: '标题还是那个标题');
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget, reason: '暗示可点');

    await tapTitle(tester);
    expect(find.text('选择学期'), findsOneWidget);
    expect(find.text('新建学期'), findsOneWidget, reason: '选择器底部照旧能新建学期');
  });

  testWidgets('在选择器里挑另一个学期：切过去，标题跟着变、旧课表不再显示', (tester) async {
    await pumpPage(tester);
    final before = title(tester);
    expect(find.text('数据库原理及应用'), findsWidgets, reason: '先确认当前学期的课在');

    await tapTitle(tester);
    await tester.tap(find.text(genericLabel(otherKey)));
    await tester.pumpAndSettle();

    expect(title(tester), '课程表 · $otherLabel');
    expect(title(tester), isNot(before));
    expect(find.text('数据库原理及应用'), findsNothing, reason: '$otherLabel 是空学期');
  });
}
