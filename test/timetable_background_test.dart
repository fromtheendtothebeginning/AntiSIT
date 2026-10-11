import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「自定义课表背景」的验收：
/// * 状态持久化（路径 + 淡显程度），清除后路径键从存档里移除；
/// * 换图 / 清除时删掉旧的本机副本；
/// * 设置页有入口，弹层里能恢复默认（滑块只在有图时可用）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TtBackground.I.debugFill();
  });

  test('load 读回路径与淡显，未设置时为默认值', () async {
    SharedPreferences.setMockInitialValues(
        {'flutter.tt_background_path': '/tmp/a.jpg', 'flutter.tt_background_opacity': 0.3});
    await TtBackground.I.load();
    expect(TtBackground.I.path, '/tmp/a.jpg');
    expect(TtBackground.I.opacity, closeTo(0.3, 1e-9));
  });

  test('未设置时 load 落回默认淡显', () async {
    await TtBackground.I.load();
    expect(TtBackground.I.path, isNull);
    expect(TtBackground.I.opacity, TtBackground.defaultOpacity);
  });

  test('set 清除背景时从存档移除路径键', () async {
    SharedPreferences.setMockInitialValues({'flutter.tt_background_path': '/tmp/a.jpg'});
    await TtBackground.I.load();
    await TtBackground.I.set(null);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('tt_background_path'), isNull,
        reason: '清除后不该残留路径（注意 mock 键没有 flutter. 前缀差异，见下方对照）');
  });

  test('setOpacity 夹紧到允许区间并落盘', () async {
    await TtBackground.I.load();
    await TtBackground.I.setOpacity(0.9);
    expect(TtBackground.I.opacity, TtBackground.maxOpacity);
    await TtBackground.I.setOpacity(0.01);
    expect(TtBackground.I.opacity, TtBackground.minOpacity);
  });

  test('copyIntoAppDir：拷贝到应用目录，失败返回 null', () async {
    // 路径不存在 → 拷贝失败 → null（不抛异常、不挡课表）
    final saved = await TtBackground.I.copyIntoAppDir('/nonexistent/dir/pic.png');
    expect(saved, isNull);
  });

  test('set 换图会删掉旧副本', () async {
    final dir = await Directory.systemTemp.createTemp('ttbg');
    final old = File('${dir.path}/old.png')..writeAsBytesSync([1, 2, 3]);
    final neu = File('${dir.path}/new.png')..writeAsBytesSync([4, 5, 6]);
    await TtBackground.I.set(old.path);
    await TtBackground.I.set(neu.path);
    expect(await old.exists(), isFalse, reason: '旧副本应被清理');
    expect(await neu.exists(), isTrue);
    await TtBackground.I.set(null);
    expect(await neu.exists(), isFalse, reason: '清除背景也应删副本');
    await dir.delete(recursive: true);
  });

  testWidgets('课程表设置页有「课表背景」入口，弹层可恢复默认', (tester) async {
    await TtBackground.I.load();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TimetableSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('课表背景'), findsOneWidget);
    expect(find.text('默认（跟随主题底色）'), findsOneWidget);

    await tester.tap(find.text('课表背景'));
    await tester.pumpAndSettle();
    expect(find.text('选择图片'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull,
        reason: '没有背景图时淡显滑块不可用');
    expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '恢复默认')).enabled, isFalse);

    // 有背景图后：滑块可用、可恢复默认
    await TtBackground.I.set('/tmp/bg.jpg');
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '恢复默认')).enabled, isTrue);
  });
}
