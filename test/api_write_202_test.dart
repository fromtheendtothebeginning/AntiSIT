import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `once: true` 的写操作（电费充值 / 断隧道）碰到 202 不能当成功。
///
/// 服务器回 202 = 「校园网隧道还在建，请求没被处理」。202 落在 2xx 区间，
/// 旧实现会带着 `{"retry_after":5}` 原样返回，充值调用方看到「没抛异常」
/// 就提示充值成功——实际一分钱没充。
void main() {
  late HttpServer server;
  late int port;
  late String mode;
  late int hits;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = false;
    AppState.I.mode = AppMode.server;
    AppState.I.token = 'test-token';
    ApiClient.tunnelWarmup.value = 0;
    mode = 'always202';
    hits = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    AppState.I.serverUrl = 'http://127.0.0.1:$port';
    server.listen((req) async {
      hits++;
      req.response.headers.contentType = ContentType.json;
      if (mode == 'zeroRetry') {
        // retry_after = 0：旧实现无延时紧密重试（死循环打爆服务器）
        req.response.statusCode = 202;
        req.response.write(jsonEncode({'vpn_connecting': true, 'retry_after': 0}));
      } else if (mode == 'ok') {
        req.response.write(jsonEncode({'ok': true, 'data': {}}));
      } else {
        req.response.statusCode = 202;
        req.response.write(jsonEncode({'vpn_connecting': true, 'retry_after': 1}));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    ApiClient.tunnelWarmup.value = 0;
    await server.close(force: true);
  });

  test('充值（once=true）遇 202：抛错而不是当成功返回', () async {
    await expectLater(
      ApiClient.I.electricityRecharge(10),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 202)),
    );
    expect(hits, 1, reason: '写操作绝不重发');
  });

  test('充值遇 202：错误被标成「确定没执行」，可以放心提示重试', () async {
    try {
      await ApiClient.I.electricityRecharge(10);
      fail('应该抛错');
    } on ApiError catch (e) {
      expect(writeOutcomeUncertain(e), isFalse);
    }
  });

  test('retry_after = 0 不会被夹成 0 秒：重试间隔至少 1 秒', () async {
    mode = 'zeroRetry';
    final sw = Stopwatch()..start();
    // 读到第一次 202 后等约 1.5 秒改成成功，验证「有等待、有重试」
    final f = ApiClient.I.score();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final hitsAtStart = hits;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(hits, hitsAtStart, reason: '夹到 ≥1 秒后不会在 0.7 秒内重复打出去');
    mode = 'ok';
    final r = await f;
    sw.stop();
    expect(r['ok'], isTrue);
  });
}
