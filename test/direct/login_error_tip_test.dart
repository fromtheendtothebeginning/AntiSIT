import 'dart:io';

import 'package:campus_service/api_error.dart';
import 'package:campus_service/direct/jwxt.dart';
import 'package:campus_service/direct/mock_campus_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：登录页里的**隐藏**错误骨架（`style="display:none"`）不能被当成学校的错误原因。
///
/// 背景：SIT 真实登录页同时带两套错误元素——
///   隐藏骨架 `#usernameError / #passwordError / #cpatchaError`（「请输入用户名 / 请输入密码 /
///   请输入验证码」，给 JS 改文案用，永远不出现在屏幕上）；服务端的判定结果一律渲染在可见元素里
///   （学工 CAS 实测是 `#msg`，正方教务是 `#tips`）。
/// 客户端按 id/class 抓第一个命中的元素时，若不过滤隐藏元素，就会把「请输入密码」当作学校原文
/// 抛给用户——账号密码正确的用户会以为凭据错了。本组用例跑真 HTTP，驱动真实客户端登录流程。
void main() {
  final mock = MockCampusServer.instance;

  setUpAll(() async {
    HttpOverrides.global = null;
    await mock.start();
  });
  tearDownAll(() async => mock.stop());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await mock.stop();
    await mock.start();
  });

  group('登录失败文案提取不抓隐藏骨架', () {
    test('正方教务：静态骨架 + 空的 #tips（服务端没给原因）→ 不误报账号密码错误', () async {
      mock.debugJwxtLoginFailBody =
          '<html><body>$MockCampusServer.casErrorSkeleton<div id="tips" style="display:none"></div></body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);

      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having(
          (e) => e.message,
          'message',
          allOf(
            isNot(contains('请输入密码')),
            isNot(contains('请输入用户名')),
            contains('没有错误文案'),
          ),
        )),
      );
    });

    test('正方教务：同一张页面里可见 #tips 有原因 → 以可见元素为准', () async {
      mock.debugJwxtLoginFailBody =
          '<html><body>$MockCampusServer.casErrorSkeleton<div id="tips">验证码错误</div></body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);

      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('验证码错误'))),
      );
    });
  });
}
