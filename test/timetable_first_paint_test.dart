import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 冷启动时课表页「先显示、后刷新」的回归（启动动画放完了不该还在转圈）。
///
/// 历史症状：_init() 里 await 完 syncCloud()（服务器模式下 GET /api/timetable 是
/// 一次真网络往返，最坏 60s 超时）才把 _booting 置 false，于是启动页读到的本机
/// 课表明明已经就位，用户却要对着转圈等服务器应答。
void main() {
  late HttpServer server;
  late String startISO;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = false;
    AppState.I.mode = AppMode.server;
    AppState.I.token = 'test-token';

    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    startISO = TimetableStore.iso(monday);
    final (xnm, xqm) = AppState.inferSemester(now);
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(startDate: startISO, weekCount: 20),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
    // 已经读过本机课表（等同启动页那一遍）：课表页不该再阻止于转圈
    TimetableStore.instance.loaded = true;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    AppState.I.serverUrl = 'http://127.0.0.1:${server.port}';
    // 服务器一直回 202（建隧道中）：ApiClient 会按 retry_after 一直等下去，
    // 用来模拟「云端请求迟迟不回来」；课表页不该把首屏挂在这条请求上。
    server.listen((req) async {
      req.response.statusCode = 202;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"retry_after": 60}');
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  testWidgets('云端请求还没回来，课表页就已经显示网格（不是转圈）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    // 一帧本地初始化 + 一帧落地；此时云端合并还在等服务器应答
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '本机课表已就位就不该让用户对着转圈等网络',
    );
    expect(find.byType(AppBar), findsOneWidget, reason: '课表页骨架应当已经画出来');

    // 收尾：后台那两段网络各自挂着 60s 超时定时器（课堂测试时钟是假的，必须把它们
    // 走完，否则测试框架会报「还有 Timer 没结束」）。
    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
  });
}
