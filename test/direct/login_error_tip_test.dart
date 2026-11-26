import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：登录页里隐藏的错误骨架（display:none）不能当成学校的错误原因，否则会把「请输入密码」抛给账号密码正确的用户；跑真 HTTP。
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
      // 没有 id/class 的错误元素只能靠文本兜底命中，兜底同样要跳过 display:none。
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

    test('正方教务：body 带防闪屏 display:none 时，可见 #tips 仍要读出原因', () async {
      // body 常带 display:none 防闪屏，去噪时整块删掉会连服务端渲染在可见 #tips 里的原因一起消失。
      mock.debugJwxtLoginFailBody =
          '<!doctype html><html lang="zh-CN"><head><title>教学管理信息服务平台</title></head>'
          '<body style="background:#fafafa; display: none;">'
          '<p id="tips" class="bg_danger sl_danger">'
          '<span class="glyphicon glyphicon-minus-sign"></span>用户名或密码不正确，请重新输入！'
          '</p></body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);

      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having(
          (e) => e.message,
          'message',
          allOf(contains('用户名或密码不正确'), isNot(contains('没有错误文案'))),
        )),
      );
    });

    test('正方教务：body 隐藏时，隐藏的 #tips 骨架仍不许当成原因', () async {
      mock.debugJwxtLoginFailBody =
          '<html><body style="display: none;">'
          '<p id="tips" style="display:none;">请输入密码</p>'
          '</body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);

      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having(
          (e) => e.message,
          'message',
          allOf(isNot(contains('请输入密码')), contains('没有错误文案')),
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
