import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/config_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：「我的 → 配置」里能改工具页是否自动刷新、校园码换码间隔。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
  });

  Future<void> pumpConfig(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ConfigPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('自动刷新开关与校园码间隔可改，并立即落盘', (tester) async {
    await pumpConfig(tester);

    expect(find.text('工具页自动刷新'), findsOneWidget);
    expect(find.text('校园码刷新间隔'), findsOneWidget);
    expect(AppState.I.autoRefreshTools, isTrue);
    expect(AppState.I.ecardRefreshSeconds, 10);

    await tester.tap(find.text('工具页自动刷新'));
    await tester.pumpAndSettle();
    expect(AppState.I.autoRefreshTools, isFalse);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('tool_auto_refresh'), isFalse);

    await tester.tap(find.text('校园码刷新间隔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每 15 秒换一张'));
    await tester.pumpAndSettle();
    expect(AppState.I.ecardRefreshSeconds, 15);
    expect(sp.getInt('ecard_refresh_seconds'), 15);
    expect(find.textContaining('每 15 秒换一张码'), findsOneWidget);
  });

  test('校园码间隔限制在 5–30 秒', () async {
    await AppState.I.setEcardRefreshSeconds(1);
    expect(AppState.I.ecardRefreshSeconds, 5);
    await AppState.I.setEcardRefreshSeconds(99);
    expect(AppState.I.ecardRefreshSeconds, 30);
  });

  test('工具页缓存可读可写；损坏的缓存当作没有', () async {
    await ToolPageCache.write('demo', {
      'data': {'balance': 1.5}
    });
    final got = await ToolPageCache.read('demo');
    expect(got?['data'], {'balance': 1.5});
    expect(await ToolPageCache.read('missing'), isNull);

    final sp = await SharedPreferences.getInstance();
    await sp.setString('tool_page_cache_v1_bad', '{oops');
    expect(await ToolPageCache.read('bad'), isNull);
  });

  test('退出登录清空工具页缓存，不碰其它偏好', () async {
    await ToolPageCache.write('demo', {
      'data': {'balance': 1.5}
    });
    final sp = await SharedPreferences.getInstance();
    await sp.setString('unrelated_pref', 'keep');

    await AppState.I.clearSession();

    expect(await ToolPageCache.read('demo'), isNull);
    expect(sp.getString('unrelated_pref'), 'keep');
  });

  testWidgets('顶部刷新条：刷新中转圈禁点，空闲可手动刷新', (tester) async {
    var taps = 0;

    Widget bar({required bool refreshing}) => MaterialApp(
          home: Scaffold(
            body: ToolRefreshBar(
              refreshing: refreshing,
              fromCache: true,
              onRefresh: () => taps++,
            ),
          ),
        );

    await tester.pumpWidget(bar(refreshing: true));
    expect(find.text('正在刷新…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final busy =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh_rounded));
    expect(busy.onPressed, isNull);

    await tester.pumpWidget(bar(refreshing: false));
    expect(find.text('显示本地缓存'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(taps, 1);
  });
}
