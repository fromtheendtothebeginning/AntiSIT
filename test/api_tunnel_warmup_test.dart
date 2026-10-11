import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务器模式第一次查询要建校园网隧道：服务端回 202 让客户端等几秒重试，最长能等两分钟。
/// 这期间界面必须说明白在等什么（原来只有一个光转的圈，看着就像卡死）。
void main() {
  late HttpServer server;
  late int port;
  /// 'warm' = 先回一次 202 再 200；'fail' = 先 202 再 500
  late String mode;

  setUp(() async {
    // 真 HTTP 打本地假服务：必须清掉测试框架换上的 HttpClient 假实现（它一律回 400）。
    // 放在 setUp 里而不是 main() 顶部——本文件还有 testWidgets，绑定注册时就会装上假实现。
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = false;
    AppState.I.mode = AppMode.server;
    AppState.I.token = 'test-token';
    ApiClient.tunnelWarmup.value = 0;
    mode = 'warm';

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    AppState.I.serverUrl = 'http://127.0.0.1:$port';

    var hits = 0;
    server.listen((req) async {
      hits++;
      req.response.headers.contentType = ContentType.json;
      if (hits == 1) {
        // 建隧道中：服务端让客户端等 1 秒再来
        req.response.statusCode = 202;
        req.response.write(jsonEncode({'vpn_connecting': true, 'retry_after': 1}));
      } else if (mode == 'fail') {
        req.response.statusCode = 500;
        req.response.write(jsonEncode({'detail': '炸了'}));
      } else {
        req.response.write(jsonEncode({'ok': true, 'data': {}}));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    ApiClient.tunnelWarmup.value = 0;
    await server.close(force: true);
  });

  test('建隧道期间计数为 1（界面据此显示提示），结束后归 0', () async {
    final f = ApiClient.I.score();
    // 等那次 202 回来（HTTP 往返本身是异步的）
    for (var i = 0; i < 100 && ApiClient.tunnelWarmup.value == 0; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(ApiClient.tunnelWarmup.value, 1, reason: '正在等隧道');
    await f;
    expect(ApiClient.tunnelWarmup.value, 0, reason: '查完就得收掉');
  });

  test('202 之后请求失败，计数也得归 0（提示不能留在界面上）', () async {
    mode = 'fail';
    await expectLater(ApiClient.I.score(), throwsA(isA<ApiError>()));
    expect(ApiClient.tunnelWarmup.value, 0);
  });

  testWidgets('loading 时把「正在建立校园网隧道」说出来', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageStateView(loading: true, onRetry: () {}, child: const SizedBox()),
      ),
    ));
    expect(find.textContaining('正在建立校园网隧道'), findsNothing, reason: '没在建隧道就别说');

    ApiClient.tunnelWarmup.value = 1;
    await tester.pump();
    expect(find.textContaining('正在建立校园网隧道'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: '圈还在，只是多了说明');

    ApiClient.tunnelWarmup.value = 0;
    await tester.pump();
    expect(find.textContaining('正在建立校园网隧道'), findsNothing);
  });
}
