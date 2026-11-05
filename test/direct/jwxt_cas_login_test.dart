import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：正方账号密码被拒时改走统一身份认证（CAS）。
///
/// 背景：2026 级新生在正方侧没有可用的账号密码——浏览器里也只能点登录页上的
/// 「统一身份认证登录」按钮进去；App 直接拿统一认证密码登正方会一直显示
/// 「用户名或密码错误」。这里用本地模拟服务把两条链路都跑真 HTTP / 真加密：
/// 正方密码登录被拒 → 自动切 CAS → 同一密码登入 → 课表可导入。
void main() {
  final mock = MockCampusServer.instance;

  setUpAll(() async {
    HttpOverrides.global = null;
    await mock.start();
  });
  tearDownAll(() async => mock.stop());
  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await mock.stop();
    await mock.start();
    await CampusDirect.I.disconnect();
  });
  tearDown(() {
    mock.debugJwxtPasswordLoginRejected = false;
    mock.debugJwxtNoSsoEntry = false;
  });

  JwxtClient newClient() =>
      JwxtClient(mock.baseUrl, authBase: '${mock.baseUrl}/authserver');

  test('登录页里的统一身份认证入口能被解析（含相对链接）', () {
    final entries = JwxtClient.ssoEntries(
        '<a id="authLogin" href="/jwglxt/xtgl/login_ssologin.html">统一身份认证登录</a>'
        '<input type="hidden" name="csrftoken" value="x"/>'
        '<script>var u="javascript:void(0)"</script>');
    expect(entries, contains('/jwglxt/xtgl/login_ssologin.html'));
  });

  test('入口写在脚本里（没有 href）也能解析出 authserver 地址', () {
    final entries = JwxtClient.ssoEntries(
        '<a href="javascript:void(0)" onclick="go()">统一身份认证</a>'
        '<script>function go(){location.href="https://authserver.sit.edu.cn/authserver/login?service=x"}</script>');
    expect(entries.any((e) => e.contains('authserver/login?service=')), isTrue);
  });

  test('正方账号密码被拒 → 切统一认证 → 同一密码登录成功，课表可查', () async {
    mock.debugJwxtPasswordLoginRejected = true;
    final c = newClient();
    addTearDown(c.dispose);

    // 第一次：正方账号密码登录被拒（26 级真实表现）
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await expectLater(
      () => c.completeLogin(mock.debugJwxtCaptcha!),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('密码'))),
    );
    expect(c.loggedIn, isFalse);

    // 改用统一身份认证：同一个密码
    expect(await c.enableCasLogin(), isTrue);
    expect(c.usingCasLogin, isTrue);
    final png = await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: '返回的应是统一认证验证码图');
    await c.completeLogin(mock.debugAuthCaptcha!);
    expect(c.loggedIn, isTrue);
    expect(await c.checkSession(), isTrue);

    final kb = await c.kbcx(MockCampusServer.studentId, '2026', '3', 1);
    expect(kb['courses'] as List, isNotEmpty);
    expect(kb['nj'], '2026');
  });

  test('统一认证验证码输错 → 报验证码错；换一张后仍能登录', () async {
    mock.debugJwxtPasswordLoginRejected = true;
    final c = newClient();
    addTearDown(c.dispose);

    expect(await c.enableCasLogin(), isTrue);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await expectLater(
      () => c.completeLogin('0000'),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('验证码'))),
    );

    // 失败后重新打开入口（execution 令牌已换新），用新验证码继续
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugAuthCaptcha!);
    expect(c.loggedIn, isTrue);
  });

  test('登录页没有统一认证入口 → 切不过去，不冒充登录成功', () async {
    mock.debugJwxtPasswordLoginRejected = true;
    mock.debugJwxtNoSsoEntry = true;
    final c = newClient();
    addTearDown(c.dispose);

    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await expectLater(
      () => c.completeLogin(mock.debugJwxtCaptcha!),
      throwsA(isA<ApiError>()),
    );
    expect(await c.enableCasLogin(), isFalse);
    expect(c.usingCasLogin, isFalse);
  });

  group('CampusDirect：26 级课表导入自动改走统一认证', () {
    void useMockSchool() {
      AppState.I
        ..school = mock.profile()
        ..creds = (CampusCreds()
          ..studentId = MockCampusServer.studentId
          ..password = MockCampusServer.password
          ..payPassword = MockCampusServer.payPassword
          ..dorm = MockCampusServer.dorm
          ..realName = MockCampusServer.realName);
    }

    test('第一次弹教务验证码被拒，第二次弹统一认证验证码并成功', () async {
      useMockSchool();
      mock.debugJwxtPasswordLoginRejected = true;
      final hints = <String>[];
      final errors = <String?>[];
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        hints.add(hint);
        errors.add(error);
        return hint.contains('教务') ? mock.debugJwxtCaptcha! : mock.debugAuthCaptcha!;
      };

      final week = await CampusDirect.I.timetableWeek('2026', '3', 1);
      expect(week['courses'] as List, isNotEmpty);
      expect(hints.length, 2, reason: '先试正方账号密码，被拒后改统一认证各一次');
      expect(hints.first, contains('教务'));
      expect(hints.last, contains('统一身份认证'));
      expect(errors.last, isNull, reason: '改走统一认证时不要把「密码错误」甩给下一次输入');
    });
  });
}
