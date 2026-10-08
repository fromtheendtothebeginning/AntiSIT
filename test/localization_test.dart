import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日期/时间选择器的中文文案：App 之前没挂 flutter_localizations，
/// showDatePicker / showTimePicker 一路显示英文（CANCEL / OK / SELECT DATE）。
/// 这里用与 App 同一份 delegates 起一个 MaterialApp，真实弹出选择器检查中文。
void main() {
  Widget host(Widget child) => MaterialApp(
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(body: Builder(builder: (ctx) => child)),
      );

  testWidgets('日期选择器显示中文', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showDatePicker(
      context: ctx,
      initialDate: DateTime(2026, 3, 2),
      firstDate: DateTime(2025),
      lastDate: DateTime(2027),
    );
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget, reason: '英文环境这里会是 CANCEL');
    expect(find.text('确定'), findsOneWidget, reason: '英文环境这里会是 OK');
    expect(find.text('CANCEL'), findsNothing);
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('时间选择器显示中文并带 24 小时/上下午文案', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 19, minute: 0));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });
}
