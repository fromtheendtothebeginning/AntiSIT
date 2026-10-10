import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证码弹窗里 AI 识别与手输框是**并发**的：
/// 弹窗立刻把图和输入框摆出来（不干等 AI），AI 在后台读图；
/// 认出来且用户还没动手才自动填入并提交，用户先输完的、换过图的、识别失败的都退回手输。
void main() {
  // 1×1 透明 PNG：弹窗里的 Image.memory 要真能解码，随便几个字节会抛「Invalid image data」
  final image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
  const pendingHint = 'AI 正在后台识别，认出来会自动提交；想自己输就直接输';

  /// 弹出弹窗并拿到一个句柄：能查「关没关、返回值是什么」。
  Future<_Host> open(
    WidgetTester tester, {
    Future<String?>? ai,
    Future<Uint8List> Function()? refresh,
  }) async {
    final host = _Host();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () async {
              host.result = await showDialog<String>(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => CaptchaDialog(
                  image: image,
                  hint: '教务系统验证码',
                  onRefresh: refresh ?? () async => image,
                  ai: ai,
                ),
              );
              host.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(); // 弹窗入场
    await tester.pump(const Duration(milliseconds: 400));
    return host;
  }

  String typed(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  testWidgets('AI 出结果前弹窗已经能输；AI 先出结果就自动提交', (tester) async {
    final ai = Completer<String?>();
    final host = await open(tester, ai: ai.future);

    expect(host.closed, isFalse);
    expect(find.text(pendingHint), findsOneWidget, reason: 'AI 在后台跑，界面上有提示');
    await tester.enterText(find.byType(EditableText), '');
    expect(find.byType(EditableText), findsOneWidget, reason: '不等 AI 也能自己输');

    ai.complete('ab12');
    await tester.pump(); // .then 回调：自动填入 + 提交
    await tester.pump(const Duration(milliseconds: 400));
    expect(host.closed, isTrue);
    expect(host.result, 'ab12');
  });

  testWidgets('用户先自己输：AI 结果不抢、不覆盖', (tester) async {
    final ai = Completer<String?>();
    final host = await open(tester, ai: ai.future);

    await tester.enterText(find.byType(EditableText), 'zz99');
    ai.complete('ab12');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(host.closed, isFalse, reason: '用户已经动手，AI 不该替他提交');
    expect(typed(tester), 'zz99', reason: 'AI 结果不能覆盖用户输入');
    expect(find.text(pendingHint), findsNothing, reason: 'AI 已经跑完，提示该收掉');

    await tester.tap(find.text('确定'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(host.result, 'zz99');
  });

  testWidgets('中途换了另一张图：AI 认的是旧图，结果作废', (tester) async {
    final ai = Completer<String?>();
    final host = await open(tester, ai: ai.future, refresh: () async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump();
    ai.complete('ab12');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(host.closed, isFalse, reason: '图换了，旧图的识别结果不能用');
    expect(typed(tester), isEmpty);
  });

  testWidgets('AI 没认出来（null）：弹窗留着等手输', (tester) async {
    final ai = Completer<String?>();
    final host = await open(tester, ai: ai.future);

    ai.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(host.closed, isFalse);
    expect(find.text(pendingHint), findsNothing);
    await tester.enterText(find.byType(EditableText), 'k7');
    await tester.tap(find.text('确定'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(host.result, 'k7');
  });

  testWidgets('没让 AI 试（ai == null）：直接就是手输框', (tester) async {
    final host = await open(tester);
    expect(find.text(pendingHint), findsNothing);
    await tester.enterText(find.byType(EditableText), 'q1');
    await tester.tap(find.text('确定'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(host.result, 'q1');
  });
}

class _Host {
  String? result;
  bool closed = false;
}
