import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 玻璃日期 / 时间选择器：自绘的底部面板，替换 Material 原生弹层。
void main() {

  testWidgets('日期选择器：点日期后返回所选那天', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await showGlassDatePicker(
                  ctx,
                  initialDate: DateTime(2026, 11, 28),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择日期'), findsOneWidget);
    expect(find.text('2026 年 11 月'), findsOneWidget);
    // 选 12 号再确定
    await tester.tap(find.text('12'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.day, 12);
    expect(picked!.month, 11);
  });

  testWidgets('日期选择器：取消返回 null', (tester) async {
    DateTime? picked = DateTime(2020);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await showGlassDatePicker(ctx);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('时间选择器：返回所选时与分', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await showGlassTimePicker(
                  ctx,
                  initialTime: const TimeOfDay(hour: 9, minute: 30),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择时间'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 9, minute: 30));
  });

  testWidgets('少量选项面板：点一项就返回下标', (tester) async {
    int? index;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                index = await showGlassChoiceSheet(
                  ctx,
                  title: '每周几',
                  selected: 0,
                  options: const ['周一', '周二', '周三'],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周三'));
    await tester.pumpAndSettle();
    expect(index, 2);
  });
}
