import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 页面转场的验收：
/// * 普通前进：新页整块从右侧滑入（不淡入），旧页延后 22% 时长才左移 20% + 轻微压暗；
/// * 普通返回：当前页向右滑出，下层页从 −20% 让位处回到 0；
/// * 预测式返回（Android 14+ 边缘拖入）：**画面就是这套默认返回动画**，由手指驱动动画值；
///   中途取消能退回原位，松手提交才真的返回。
///
/// 手势是用 Flutter 自己的测试手法模拟的：往 `flutter/backgesture` 平台通道发
/// start / update / cancel / commit 消息（见 flutter/packages/flutter/test 里的同名用例）。
void main() {
  Future<void> backGesture(WidgetTester tester, String method,
      [Map<String, Object?> args = const {}]) async {
    final message = const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/backgesture', message, (_) {});
    await tester.pump();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(GlassPalette.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const Scaffold(body: Center(child: Text('第二页'))),
              )),
              child: const Text('push'),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> dragTo(WidgetTester tester, double progress) async {
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 5.0 + progress * width,
      'y': 300.0,
      'progress': progress,
      'swipeEdge': 0,
    });
  }

  Future<void> startGesture(WidgetTester tester) => backGesture(
        tester,
        'startBackGesture',
        <String, Object?>{'touchOffset': <double>[5.0, 300.0], 'progress': 0.0, 'swipeEdge': 0},
      );

  testWidgets('普通 push：新页从右侧滑入，旧页前 22% 时长原地不动', (tester) async {
    await pumpApp(tester);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final settledOld = tester.getTopLeft(find.text('push')).dx;

    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90)); // 520ms 的前 17%
    final early = tester.getTopLeft(find.text('第二页')).dx;
    expect(early, greaterThan(0), reason: '入场页应当从右侧滑入，动画中还没到 0');
    expect(tester.getTopLeft(find.text('push')).dx, settledOld,
        reason: '旧页在前 22% 时长里应当原地不动，不能一上来就被推开');
    expect(
      find.ancestor(of: find.text('第二页'), matching: find.byType(FadeTransition)),
      findsNothing,
      reason: '入场页不能淡入，否则上一页会从透明处透出来',
    );

    await tester.pump(const Duration(milliseconds: 170)); // 过半
    final midOld = tester.getTopLeft(find.text('push')).dx;
    expect(midOld, lessThan(settledOld), reason: '旧页应当整体左移');
    expect(midOld, greaterThan(settledOld - 0.21 * width), reason: '左移不超过 20% 屏宽');

    await tester.pumpAndSettle();
    final settledNew = tester.getTopLeft(find.text('第二页')).dx;
    expect(early, greaterThan(settledNew), reason: '入场页从右侧滑入，动画中在落位点右边');
    // 落位后旧页被 Navigator 置为 offstage（不绘制），查位置要带 skipOffstage: false
    expect(tester.getTopLeft(find.text('push', skipOffstage: false)).dx,
        closeTo(settledOld - 0.2 * width, 2), reason: '旧页最终停在左移 20% 处');
  });

  testWidgets('普通返回：当前页整块向右滑出，下层页从 −20% 回到原位', (tester) async {
    await pumpApp(tester);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    final newSettled = tester.getTopLeft(find.text('第二页')).dx;
    final oldCovered = tester.getTopLeft(find.text('push', skipOffstage: false)).dx;

    Navigator.of(tester.element(find.text('第二页'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120)); // 320ms 的前 37%

    final popping = tester.getTopLeft(find.text('第二页', skipOffstage: false)).dx;
    expect(popping, greaterThan(newSettled), reason: '返回时当前页应当向右滑出');
    final revealed = tester.getTopLeft(find.text('push')).dx;
    expect(revealed, greaterThan(oldCovered), reason: '下层页应当从 −20% 往右回到原位');
    expect(revealed, lessThanOrEqualTo(oldCovered + 0.2 * width + 1),
        reason: '下层页最多回到原位，不会越过去');

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('push')).dx,
        closeTo(oldCovered + 0.2 * width, 2), reason: '落位后下层页回到原位');
  });

  testWidgets('预测式返回：手势期间严格线性 + 放大（小幅度手指动作触发大幅度动画）', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final newSettled = tester.getTopLeft(find.text('第二页')).dx;

    await startGesture(tester);
    expect(find.text('第二页'), findsOneWidget, reason: '手势开始还不能返回');

    // 线性 + 放大 2 倍：手指划 25% 屏宽 → 页面走 50%；划 40% → 走 80%
    await dragTo(tester, 0.25);
    final at25 = tester.getTopLeft(find.text('第二页')).dx - newSettled;
    await dragTo(tester, 0.40);
    final at40 = tester.getTopLeft(find.text('第二页')).dx - newSettled;

    expect(at25, closeTo(0.50 * width, 0.02 * width),
        reason: '手势 25% 应推进 50%（放大 2 倍、线性）');
    expect(at40, closeTo(0.80 * width, 0.02 * width),
        reason: '手势 40% 应推进 80%（线性无曲线加速段）');
    expect(at40 - at25, closeTo(0.30 * width, 0.02 * width),
        reason: '两段位移差应当与手指位移差成固定比例（严格线性）');

    // 与默认返回同一套观感：不做整页透明度淡出、不做圆角裁剪
    expect(find.ancestor(of: find.text('第二页'), matching: find.byType(Opacity)),
        findsNothing, reason: '手势期间不该给整页套 Opacity');
    expect(find.ancestor(of: find.text('第二页'), matching: find.byType(ClipRRect)),
        findsNothing, reason: '手势期间不做整页圆角裁剪');

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget, reason: '取消手势应当留在原页');
    expect(tester.getTopLeft(find.text('第二页')).dx, closeTo(newSettled, 1),
        reason: '取消后回到原位');
  });

  testWidgets('预测式返回：拖动后松手提交才真的返回', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    await startGesture(tester);
    await dragTo(tester, 0.5);
    expect(find.text('第二页'), findsOneWidget, reason: '还没松手，不能自己返回');

    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing);
    expect(find.text('push'), findsOneWidget);
  });

  testWidgets('预测式返回：松手后从当前位置播完，不从头重播', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final settled = tester.getTopLeft(find.text('第二页')).dx;

    await startGesture(tester);
    await dragTo(tester, 0.3); // 放大 2 倍 → 页面已推进 60%
    final atRelease = tester.getTopLeft(find.text('第二页')).dx - settled;
    expect(atRelease, closeTo(0.6 * width, 0.02 * width), reason: '松手时应推进 60% 屏宽');

    await backGesture(tester, 'commitBackGesture');
    await tester.pump(const Duration(milliseconds: 16));
    final after = tester.getTopLeft(find.text('第二页', skipOffstage: false)).dx -
        settled;
    expect(after, greaterThanOrEqualTo(atRelease - 1),
        reason: '松手后应当从当前位置继续往右播完，不能倒回起点重播');

    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing, reason: '收尾后完成返回');
  });

  testWidgets('预测式返回：松手取消后从当前位置回弹，不跳回起点重播', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final settled = tester.getTopLeft(find.text('第二页')).dx;

    await startGesture(tester);
    await dragTo(tester, 0.3);
    final atRelease = tester.getTopLeft(find.text('第二页')).dx - settled;

    await backGesture(tester, 'cancelBackGesture');
    await tester.pump(const Duration(milliseconds: 16));
    final after = tester.getTopLeft(find.text('第二页')).dx - settled;
    expect(after, lessThanOrEqualTo(atRelease + 1),
        reason: '取消（回弹）时位移只能往回收，不会先跳到别的值');
    expect(after, greaterThan(atRelease - 0.3 * width),
        reason: '回弹也是连续的，不会一帧就回到 0');
    expect(width, greaterThan(0));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('第二页')).dx, closeTo(settled, 1),
        reason: '取消后回到原位');
  });

  testWidgets('关掉「预测式返回动画」：不接管手势，松手仍按普通返回', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.setPredictiveBack(false);
    addTearDown(() => AppState.I.predictiveBack = true);
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('第二页'));

    await startGesture(tester);
    await dragTo(tester, 0.6);
    expect(tester.getTopLeft(find.text('第二页')), settled,
        reason: '关掉预测式返回后，手势期间画面不该跟着动');

    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing, reason: '松手后仍要按普通返回退出');
  });
}
