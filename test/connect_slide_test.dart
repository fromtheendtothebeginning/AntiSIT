import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：连接设置里滑块下方的界面也随滑块切换，且整页可以左右滑动切模式（与主界面同一套）。
/// 两套设置并排放在一个 Stack 里跟着连续位置滑动，所以这里按**横向位置**判断谁在屏幕里。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.mode = AppMode.server;
  });

  Future<double> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(GlassPalette.light),
      home: const ConnectPage(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    return tester.view.physicalSize.width / tester.view.devicePixelRatio;
  }

  // 直连区的标记用警告条 Finder（两张卡都默认收起，内容不在树里；警告条始终在场）
  double leftOf(WidgetTester tester, Finder f) => tester.getTopLeft(f).dx;

  Finder directMarker() => find.textContaining('直连模式不走服务器');

  testWidgets('初始：服务器那套在屏幕内，另一套在右侧屏幕外', (tester) async {
    final w = await pumpPage(tester);
    final rest = leftOf(tester, find.text('服务器地址'));
    expect(rest, lessThan(80), reason: '当前是服务器模式，它这套就在屏幕里');
    expect(leftOf(tester, directMarker()), greaterThan(w), reason: '直连那套先在屏幕外右侧等着');
  });

  testWidgets('页面区域往左拖：下方两套跟着滑动，松手停在直连那套', (tester) async {
    final w = await pumpPage(tester);
    final rest = leftOf(tester, find.text('服务器地址')); // 卡片内边距，作为「在屏幕里」的基准

    final g = await tester.startGesture(Offset(w * 0.85, 200));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(Offset(-w * 0.15, 0)); // 分步拖过半屏（一步到位的话识别器吃不到足量位移）
      await tester.pump();
    }
    // 拖到一半多：直连那套已经滑进屏幕（不是等松手才瞬切）
    expect(leftOf(tester, directMarker()), lessThan(w * 0.6), reason: '跟着滑块一起滑进来');
    expect(leftOf(tester, find.text('服务器地址')), lessThan(rest - w * 0.1), reason: '原来那套往左滑了出去');

    await g.up();
    await tester.pumpAndSettle();
    expect(leftOf(tester, directMarker()), closeTo(rest - 3, 2), reason: '松手后停在直连模式那套');
    expect(leftOf(tester, find.text('服务器地址')), lessThan(-w * 0.9), reason: '服务器那套整块滑出屏幕');
  });

  testWidgets('关掉「界面实时跟着滑块切换」：拖动中两套设置不动，松手才切', (tester) async {
    AppState.I.followSlider = false;
    addTearDown(() => AppState.I.followSlider = true);
    final w = await pumpPage(tester);
    final rest = leftOf(tester, find.text('服务器地址'));

    final g = await tester.startGesture(Offset(w * 0.85, 200));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(Offset(-w * 0.15, 0));
      await tester.pump();
    }
    expect(leftOf(tester, find.text('服务器地址')), closeTo(rest, 1), reason: '拖动中不跟着滑');
    expect(leftOf(tester, directMarker()), greaterThan(w), reason: '另一套还在屏幕外');

    await g.up();
    await tester.pumpAndSettle();
    expect(leftOf(tester, directMarker()), closeTo(rest - 3, 2), reason: '松手后直接切到这套');
  });

  testWidgets('往右拖回来：回到服务器那套', (tester) async {
    final w = await pumpPage(tester);
    final rest = leftOf(tester, find.text('服务器地址'));

    // 先切到直连
    var g = await tester.startGesture(Offset(w * 0.85, 200));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(Offset(-w * 0.15, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(leftOf(tester, directMarker()), closeTo(rest - 3, 2), reason: '警告条不在卡内，左缘比卡内文字小 3（12+12 vs 12+16）');

    // 再往右拖回来
    g = await tester.startGesture(Offset(w * 0.15, 200));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(Offset(w * 0.15, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(leftOf(tester, find.text('服务器地址')), closeTo(rest, 2));
  });
}
