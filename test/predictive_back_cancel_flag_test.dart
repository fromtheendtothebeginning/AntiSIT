import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:campus_service/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 预测式返回的一个收尾缺陷：手势刚起就取消时，全局标记必须清掉。
///
/// 历史症状：controller 已在 1（isCompleted）时框架不会启动任何动画，
/// `_onAnimationTick` 永远等不到 tick，`predictiveBackGesturing` 就永久为 true，
/// 之后所有前进转场都错误地套用返回曲线（下层页位置/曲线全乱），直到该路由 dispose。
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

  testWidgets('进度为 0 就开始又取消：predictiveBackGesturing 立刻回到 false', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    expect(predictiveBackGesturing, isFalse);
    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    expect(predictiveBackGesturing, isTrue, reason: '手势开始就置位');

    // 没有有效位移就松手：框架直接取消，且不会启动动画
    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();

    expect(predictiveBackGesturing, isFalse,
        reason: '取消后必须立刻清标记，否则后续所有前进转场都套返回曲线');
  });

  testWidgets('取消后再走一次正常 push：手势态不残留', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(predictiveBackGesturing, isFalse);

    // 再推一页：正常前进（下层同步让位），说明没有残留的手势态
    final settledOld = tester.getTopLeft(find.text('第二页')).dx;
    Navigator.of(tester.element(find.text('第二页'))).push(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Center(child: Text('第三页'))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final early = tester.getTopLeft(find.text('第三页')).dx;
    expect(early, greaterThan(0), reason: '新页仍从右侧滑入');
    final earlyOld = tester.getTopLeft(find.text('第二页')).dx;
    expect(earlyOld, lessThan(settledOld), reason: '下层页同步让位，说明没套用返回曲线');
    await tester.pumpAndSettle();
  });
}

