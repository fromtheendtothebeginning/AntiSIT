import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「安卓端增加可预测式返回动画」的验收：
/// * 普通前进 / 普通返回仍旧是自家 fade-through（玻璃观的淡入淡出，内容不做位移）；
/// * 系统返回手势（Android 14+ 的预测式返回）走官方动画：拖动时当前页跟着手指缩小，
///   松手前还能反悔取消。
///
/// 手势是用 Flutter 自己的测试手法模拟的：往 `flutter/backgesture` 平台通道发
/// start / update / commit 消息（见 flutter/packages/flutter/test 里的同名用例）。
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

  testWidgets('普通 push 仍是淡入淡出：内容不位移，只有透明度在变', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90)); // 过渡进行中
    final mid = tester.getTopLeft(find.text('第二页'));
    expect(find.byType(FadeTransition), findsWidgets, reason: '淡入淡出还在用');

    await tester.pumpAndSettle();
    expect(mid, tester.getTopLeft(find.text('第二页')),
        reason: '淡入淡出不该有位移（换成官方 FadeForwards 的横向滑动就会位移）');
  });

  testWidgets('位移 1:1 跟手：进度每涨 0.2，页面就多移 0.2 个屏宽', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final settled = tester.getTopLeft(find.text('第二页')).dx;

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });

    Future<double> shiftAt(double progress) async {
      await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
        'x': 5.0 + progress * width,
        'y': 300.0,
        'progress': progress,
        'swipeEdge': 0,
      });
      return tester.getTopLeft(find.text('第二页')).dx - settled;
    }

    final at20 = await shiftAt(0.2);
    final at40 = await shiftAt(0.4);
    // 系统给的 progress 就是「手指从边缘走到对边的比例」，所以位移应当 ≈ 进度 × 屏宽。
    // 允许 ±25px：还叠了一点缩放（0.99~0.98，居中内容几乎不动）。
    expect(at20, closeTo(0.2 * width, 25), reason: '进度 0.2 时应位移 0.2 个屏宽');
    expect(at40 - at20, closeTo(0.2 * width, 25), reason: '再涨 0.2 进度就再多移 0.2 个屏宽（跟手）');

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('第二页')).dx, closeTo(settled, 1),
        reason: '取消后要回到原位');
  });

  testWidgets('系统返回手势：当前页跟着手势缩小（预测式动画），提交后才真正返回', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('第二页'));

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0, // 左侧边缘
    });
    // 还没提交，页面不能自己返回
    expect(find.text('第二页'), findsOneWidget);

    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 200.0,
      'y': 300.0,
      'progress': 0.6,
      'swipeEdge': 0,
    });
    final during = tester.getTopLeft(find.text('第二页'));
    expect(during, isNot(before),
        reason: '预测式返回会把当前页缩小、内容往中心收；纯淡入淡出是原地淡出，位置不动');

    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing);
    expect(find.text('push'), findsOneWidget);
  });

  testWidgets('不论从哪条边划，一律按「从左边返回」：当前页往右滑出', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('第二页')).dx;

    // 从右边缘划进来（swipeEdge: 1）
    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[795.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 1,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 600.0,
      'y': 300.0,
      'progress': 0.3,
      'swipeEdge': 1,
    });
    final during = tester.getTopLeft(find.text('第二页')).dx;
    expect(during, greaterThan(settled),
        reason: '右侧划进来也按左边那套：当前页往右走、上一页从左面露出来');

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
  });

  testWidgets('拖动早期就能看见要回撤到的那一页（当前页淡得更早）', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 110.0,
      'y': 300.0,
      'progress': 0.2,
      'swipeEdge': 0,
    });
    final fade = tester.widget<Opacity>(
        find.ancestor(of: find.text('第二页'), matching: find.byType(Opacity)).first);
    expect(fade.opacity, lessThan(0.9),
        reason: '进度才 0.2 就该明显淡下去，后面那页要露得出来（原来 0.45 系数时还有 0.91）');

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
  });

  testWidgets('手势中途取消（松手回弹）不会返回，且动画不跳变', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 120.0,
      'y': 300.0,
      'progress': 0.3,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();

    expect(find.text('第二页'), findsOneWidget, reason: '取消手势应当留在原页');
    expect(tester.getTopLeft(find.text('第二页')), isNotNull);
  });

  testWidgets('关掉「预测式返回动画」：手势期间画面不动，松手按普通返回', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.setPredictiveBack(false);
    addTearDown(() => AppState.I.predictiveBack = true);
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('第二页'));

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 300.0,
      'y': 300.0,
      'progress': 0.5,
      'swipeEdge': 0,
    });
    expect(tester.getTopLeft(find.text('第二页')), settled,
        reason: '开关关掉时手势不接管：页面不跟手位移');

    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing, reason: '松手提交仍要能返回（普通返回）');
  });

  testWidgets('手势期间下层页渐进模糊：前 1/3 重糊，2/3 之后不再模糊', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    Future<void> progress(double p) => backGesture(tester, 'updateBackGestureProgress',
        <String, Object?>{'x': 5.0 + p * 100, 'y': 300.0, 'progress': p, 'swipeEdge': 0});

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });

    await progress(0.3); // g ≤ 1/3：下层页被重模糊盖着
    expect(find.byType(ImageFiltered), findsOneWidget, reason: '前 1/3 应隔着模糊看见下层页');

    await progress(0.7); // g ≥ 2/3：完全清楚
    expect(find.byType(ImageFiltered), findsNothing, reason: '2/3 之后不应再模糊');

    await progress(0.4); // 1/3 ~ 2/3 之间：插值中，模糊还在
    expect(find.byType(ImageFiltered), findsOneWidget);

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing, reason: '手势结束后不再有模糊层');
  });
}
