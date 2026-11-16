import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 直连会话的 Cookie 载入必须是「所有并发请求一起等」。
///
/// 页面会在启动时同时拉课表 / 成绩 / 考试，几个请求可能同时走到 [HttpSession.load]：
/// 如果只是用一个 bool 标记「开始读了」，后到的请求会立即返回、在 Cookie 还没进罐时
/// 就发出去，学校系统认不出登录态——表现就是所有带 Cookie 的接口失效。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('并发请求共享同一次 Cookie 载入，后发请求也带 Cookie', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final cookies = <String?>[];
    server.listen((req) async {
      cookies.add(req.headers.value('cookie'));
      req.response.statusCode = 200;
      req.response.write('ok');
      await req.response.close();
    });

    final jar = jsonEncode({
      '127.0.0.1': {'JSESSIONID': 'secret-session'},
    });
    SecureStore.I = _SlowSecureStore(jar, const Duration(milliseconds: 80));

    final session = HttpSession(trustHosts: const ['127.0.0.1'], persistKey: 'test_concurrent');
    final results = await Future.wait([
      session.get('http://127.0.0.1:${server.port}/a'),
      session.get('http://127.0.0.1:${server.port}/b'),
    ]);

    expect(results.map((r) => r.status), everyElement(200));
    expect(cookies, hasLength(2));
    expect(cookies, everyElement('JSESSIONID=secret-session'),
        reason: '两个并发请求都必须等 Cookie 载入后再发');
  });
}

/// 让读 Cookie 慢一点，稳定复现「第二个请求先于载入完成就返回」的时序。
class _SlowSecureStore implements SecureStore {
  _SlowSecureStore(this.value, this.delay);

  final String value;
  final Duration delay;

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(delay);
    return value;
  }

  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
}
