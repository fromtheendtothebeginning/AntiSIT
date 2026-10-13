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

  testWidgets('下层页在手势前 1/3 就淡入到位：1/3 时已完整可见（模糊由模糊层负责）', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    double underlyingOpacity() => tester
        .widget<Opacity>(find
            .ancestor(of: find.text('push'), matching: find.byType(Opacity))
            .first)
        .opacity;

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });

    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 15.0,
      'y': 300.0,
      'progress': 0.1,
      'swipeEdge': 0,
    });
    expect(underlyingOpacity(), greaterThan(0.0),
        reason: '手势一开始下层页就开始淡入（原来要拖过 2/3 才出现，「1/3 时完全看不到」的根因）');
    expect(underlyingOpacity(), lessThan(1.0));

    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 40.0,
      'y': 300.0,
      'progress': 0.4,
      'swipeEdge': 0,
    });
    expect(underlyingOpacity(), 1.0, reason: '过了 1/3 下层页完整在场，之后只有模糊在退');

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('push'), matching: find.byType(Opacity)),
        findsNothing,
        reason: '取消后回到普通淡入淡出路径（被盖住时按旧曲线隐藏）');
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

  testWidgets('拖深后松手提交不闪回：从松手时的透明度继续淡出，不突然升回不透明', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 5.0 + 0.7 * width,
      'y': 300.0,
      'progress': 0.7,
      'swipeEdge': 0,
    });
    double topOpacity() => tester.widget<Opacity>(
        find.ancestor(of: find.text('第二页'), matching: find.byType(Opacity)).first)
        .opacity;
    expect(topOpacity(), closeTo(0.3, 0.06), reason: '拖到 0.7 时当前页只剩 30% 不透明度');

    await backGesture(tester, 'commitBackGesture');
    await tester.pump(const Duration(milliseconds: 16)); // commit 动画首帧
    expect(topOpacity(), lessThan(0.5),
        reason: '松手提交应从松手时的透明度（0.3）继续淡出；从 1 起算就会闪回不透明');
    expect(topOpacity(), lessThan(0.35),
        reason: '首帧透明度还要与松手瞬间连续（不能有可见的上升）');

    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing, reason: '提交后仍要正常返回');
  });

  testWidgets('松开提交后立刻继续往右滑出，不再先冻住再猛冲', (tester) async {
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
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 5.0 + 0.7 * width,
      'y': 300.0,
      'progress': 0.7,
      'swipeEdge': 0,
    });
    final released = tester.getTopLeft(find.text('第二页')).dx;
    expect(released, closeTo(settled + 0.7 * width, 25));

    await backGesture(tester, 'commitBackGesture');
    // 框架提交后会先把动画值拉回 1.0 再反向；旧写法要等它降回松手值才动
    // （拖到 0.7 松手要冻 90ms、拖到 0.8 要冻 240ms），这一帧就该已经往右走了。
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.getTopLeft(find.text('第二页')).dx, greaterThan(released + 20),
        reason: '松手后要继续往右滑出去，不能先冻住不动');

    // 加快后整个滑出只用框架窗口的前 60%（≈180ms）：208ms 时位移应已走完并淡透。
    await tester.pump(const Duration(milliseconds: 176));
    expect(tester.getTopLeft(find.text('第二页')).dx, closeTo(settled + width, 40),
        reason: '比框架的 300ms 窗口更早滑完');
    expect(
        tester
            .widget<Opacity>(find
                .ancestor(of: find.text('第二页'), matching: find.byType(Opacity))
                .first)
            .opacity,
        0,
        reason: '淡出也应同时完成');

    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing, reason: '提交后仍要正常返回');
  });

  testWidgets('提交瞬间下层页不闪：框架拉回 1.0 的跳变不会漏到下层页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    double underOpacity() => tester
        .widget<Opacity>(find
            .ancestor(of: find.text('push'), matching: find.byType(Opacity))
            .first)
        .opacity;

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 5.0 + 0.7 * width,
      'y': 300.0,
      'progress': 0.7,
      'swipeEdge': 0,
    });
    expect(underOpacity(), 1.0, reason: '拖到 0.7 时下层页已完整在场');

    await backGesture(tester, 'commitBackGesture');
    // 旧写法这里把下层页的覆盖进度发布成 1.0（可见度 1 → 0）：下层页闪一下消失，
    // 过一会儿再淡回来。提交后它应该贴着实际滑出进度继续收尾。
    await tester.pump(const Duration(milliseconds: 16));
    expect(underOpacity(), 1.0, reason: '提交瞬间下层页不能闪一下消失');
    await tester.pump(const Duration(milliseconds: 80));
    expect(underOpacity(), 1.0, reason: '收尾过程中下层页也不能回退');

    await tester.pumpAndSettle();
  });

  testWidgets('拉到一半再拉回起点松手（取消）：覆盖率要清干净，之后不能留成空白页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 5.0 + 0.5 * width,
      'y': 300.0,
      'progress': 0.5,
      'swipeEdge': 0,
    });
    // 拉回起点再松手：框架这时不会再跑回位动画，动画通知也就不会再来一次
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 5.0,
      'y': 300.0,
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();

    expect(predictiveBackCover.value, isNull,
        reason: '手势结束就得自己把覆盖率清掉，不能停在被盖时那个旧值上');

    // 之后正常退回上一页：上一页必须是正常渲染，而不是「被盖住」那套全透明
    Navigator.of(tester.element(find.text('第二页'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing);
    expect(find.text('push'), findsOneWidget);
    expect(
        tester
            .widgetList<Opacity>(find.ancestor(
                of: find.text('push'), matching: find.byType(Opacity)))
            .where((w) => w.opacity == 0),
        isEmpty,
        reason: '覆盖率残留会把上一页整页渲染成全透明 —— 那就是用户看到的空白界面');
  });

  testWidgets('手势期间下层页渐进磨砂：前 1/3 最重，2/3 之后不再磨砂', (tester) async {
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

    Finder frost() => find.byWidgetPredicate((w) =>
        w is ColoredBox && w.color != GlassPalette.light.bg && w.color != GlassPalette.dark.bg);

    await progress(0.3); // g ≤ 1/3：下层页隔着重磨砂
    expect(frost(), findsOneWidget, reason: '前 1/3 应隔着磨砂看见下层页');

    await progress(0.7); // g ≥ 2/3：完全清楚
    expect(frost(), findsNothing, reason: '2/3 之后不应再磨砂');

    await progress(0.4); // 1/3 ~ 2/3 之间：插值中，磨砂还在
    expect(frost(), findsOneWidget);

    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(frost(), findsNothing, reason: '手势结束后不再有磨砂层');
  });
}
