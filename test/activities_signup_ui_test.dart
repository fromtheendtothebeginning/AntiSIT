import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/plugin_activities.dart';

/// 活动详情页在线报名的全流程（演示模式）：报名中的活动给「在线报名」入口，
/// 点开是确认弹窗（无需填写任何内容，报名信息由学校预填），确认后提交，
/// 成功给出申请编号并把入口置为「已报名」防重复。
void main() {
  testWidgets('报名中 → 确认 → 申请编号 → 按钮变已报名', (tester) async {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);

    await tester.pumpWidget(const MaterialApp(
      home: ActivityDetailPage(id: 'a001', activity: {
        'id': 'a001',
        'name': 'AI 赋能学习效率提升讲座',
        'bm_start': '2026-10-23 10:00:00',
        'bm_end': '2026-10-30 22:00:00',
        'start': '2026-11-01 14:00:00',
        'end': '2026-11-01 16:00:00',
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('在线报名'), findsOneWidget);

    // 确认弹窗：没有输入框，只有取消 / 确认报名（标题与按钮同名）
    await tester.tap(find.text('在线报名'));
    await tester.pumpAndSettle();
    expect(find.text('确认报名'), findsWidgets);
    expect(find.byType(TextField), findsNothing, reason: '报名不需要用户填写任何内容');

    // 确认提交（演示接口有 400ms 延迟）
    await tester.tap(find.widgetWithText(FilledButton, '确认报名'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 成功：申请编号弹窗
    expect(find.text('报名已提交'), findsOneWidget);
    expect(find.textContaining('申请编号'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    // 入口变为已报名（含绿色徽章），不可再点
    expect(find.text('已报名'), findsWidgets);
    expect(find.text('在线报名'), findsNothing);
  });

  testWidgets('确认弹窗点取消：不发请求，入口不变', (tester) async {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);

    await tester.pumpWidget(const MaterialApp(
      home: ActivityDetailPage(id: 'a001', activity: {
        'id': 'a001',
        'name': 'AI 赋能学习效率提升讲座',
        'bm_start': '2026-10-23 10:00:00',
        'bm_end': '2026-10-30 22:00:00',
        'start': '2026-11-01 14:00:00',
        'end': '2026-11-01 16:00:00',
      }),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在线报名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('报名已提交'), findsNothing);
    expect(find.text('在线报名'), findsOneWidget);
  });

  testWidgets('学校说已报名（signed）→ 徽章 + 禁用按钮，不给报名入口', (tester) async {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);

    // a002 在演示数据里标记 signed: true
    await tester.pumpWidget(const MaterialApp(
      home: ActivityDetailPage(id: 'a002', activity: {
        'id': 'a002',
        'name': '秋季校园马拉松志愿者',
        'bm_start': '2026-10-05 12:00:00',
        'bm_end': '2026-10-12 18:00:00',
        'start': '2026-10-18 07:00:00',
        'end': '2026-10-18 13:00:00',
      }),
    ));
    // 详情接口（演示 400ms 延迟）拉回 signed；页面无加载动画时 pumpAndSettle 会提前退出，
    // 必须定长推进到定时器触发，否则测试结束时「Timer is still pending」
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('已报名'), findsWidgets); // 徽章 + 按钮都显示
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('已报名'), matching: find.bySubtype<FilledButton>()));
    expect(button.onPressed, isNull, reason: '已报名的活动不能再报');
  });

  testWidgets('报名窗口外的活动不给报名入口', (tester) async {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);

    await tester.pumpWidget(const MaterialApp(
      home: ActivityDetailPage(id: 'a003', activity: {
        'id': 'a003',
        'name': '实验室开放日参观',
        'bm_start': '2026-09-01 09:00:00',
        'bm_end': '2026-09-15 17:00:00',
        'start': '2026-09-20 13:30:00',
        'end': '2026-09-20 17:00:00',
      }),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    // 状态胶囊与按钮都写着「报名已结束」——按钮那个必须禁用
    //（FilledButton.icon 的实际类型是子类，byType 匹配不上，得用 bySubtype）
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('报名已结束'), matching: find.bySubtype<FilledButton>()));
    expect(button.onPressed, isNull, reason: '窗口外的报名按钮必须禁用');
  });
}
