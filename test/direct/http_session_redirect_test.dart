import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：重定向链上每一跳的 Set-Cookie 都必须进 Cookie 罐。
///
/// 真实学校系统就是这么用的：authserver 在 302 上建会话（JSESSIONID），下面的
/// /captcha.html 与登录 POST 都靠这个会话把验证码对上；只留最后一跳的 Cookie
/// 会让验证码绑到另一个会话上，登录必然失败（且看不出原因）。
void main() {
  late HttpServer server;
  late int port;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/a') {
        // 第一跳：建会话（真实 CAS 就是这样在 302 上 Set-Cookie）
        req.response
          ..statusCode = HttpStatus.found
          ..headers.add('Set-Cookie', 'SESS=from-hop-1; Path=/')
          ..headers.add('Location', '/b')
          ..close();
        return;
      }
      if (path == '/b') {
        // 第二跳：又一个 302，再建一个 Cookie，最后落到 /c
        req.response
          ..statusCode = HttpStatus.found
          ..headers.add('Set-Cookie', 'TICKET=from-hop-2; Path=/')
          ..headers.add('Location', '/c')
          ..close();
        return;
      }
      // 终点：把收到的 Cookie 原样回显
      req.response
        ..statusCode = 200
        ..write(req.headers.value('cookie') ?? '');
      await req.response.close();
    });
  });

  tearDownAll(() async => server.close(force: true));

  test('跟随重定向时收集每一跳的 Cookie，并在后续请求带上', () async {
    HttpOverrides.global = null;
    final s = HttpSession(trustHosts: ['127.0.0.1']);
    addTearDown(s.dispose);

    final r = await s.get('http://127.0.0.1:$port/a');
    expect(r.status, 200);
    final cookies = r.text;
    expect(cookies, contains('SESS=from-hop-1'), reason: '第一跳（中间 302）的 Cookie 不能丢');
    expect(cookies, contains('TICKET=from-hop-2'), reason: '第二跳的 Cookie 也要带上');

    // 直连终点：罐里的 Cookie 应当复用
    final again = await s.get('http://127.0.0.1:$port/c');
    expect(again.text, contains('SESS=from-hop-1'));
  });
}
