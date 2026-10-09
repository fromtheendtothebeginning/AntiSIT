import 'dart:io';

import 'package:campus_core/campus_core.dart';
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

    test('正方教务：没挂 error 类名的隐藏骨架也不许被兜底抓成学校原文', () async {
      // 按 id/class 抓的那一轮漏掉它（没有 id/class），只能靠文本节点兜底命中——
      // 兜底同样要跳过 display:none 元素，否则「请输入密码」会被抛给账号密码正确的用户
      mock.debugJwxtLoginFailBody =
          '<html><body><div style="display:none;">请输入密码</div><div style="visibility: hidden">请输入用户名</div></body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);

      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having(
          (e) => e.message,
          'message',
          allOf(isNot(contains('请输入密码')), isNot(contains('请输入用户名')), contains('没有错误文案')),
        )),
      );
    });

    test('正方教务：<script> 里的静态提示文案不是学校的判定结果', () async {
      // 登录页常在脚本里写「用户名或密码错误」这类文案给 JS 改 DOM 用（服务端本次判定为空）
      mock.debugJwxtLoginFailBody =
          '<html><body><script>var msg = "用户名或密码错误"; \$("#tips").text(msg);</script></body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);

      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having(
          (e) => e.message,
          'message',
          allOf(isNot(contains('用户名或密码错误')), contains('没有错误文案')),
        )),
      );
    });
  });
}
