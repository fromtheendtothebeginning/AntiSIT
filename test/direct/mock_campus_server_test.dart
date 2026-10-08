import 'dart:io';

import 'package:campus_service/api_error.dart';
import 'package:campus_service/app_state.dart';
import 'package:campus_service/direct/campus_direct.dart';
import 'package:campus_service/direct/epay.dart';
import 'package:campus_service/direct/jwxt.dart';
import 'package:campus_service/direct/mock_campus_server.dart';
import 'package:campus_service/direct/school.dart';
import 'package:campus_service/direct/xg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用本地模拟校园服务（行为与学校系统一致）驱动真实的直连客户端：
/// 登录表单 + 验证码 + Cookie 会话 + 各业务接口，全部走真 HTTP 与真实加密。
void main() {
  // 注意：这里不能初始化 TestWidgetsFlutterBinding——它会把 HttpClient 换成返回 400 的假实现，
  // 于是所有真 HTTP 请求都发不出去（本用例靠真 HTTP 打本地模拟服务）。
  final mock = MockCampusServer.instance;

  setUpAll(() async => mock.start());
  tearDownAll(() async => mock.stop());

  setUp(() async {
    HttpOverrides.global = null; // 保险：确保 HttpClient 不被测试框架拦截
    SharedPreferences.setMockInitialValues({});
    await mock.stop();
    await mock.start(); // 每个用例独立会话，避免上一条用例的 Cookie 影响登录流程
    await CampusDirect.I.disconnect();
  });

  /// 模拟用户手输验证码：教务 / 统一认证各取服务端最新下发的那一个。
  String readCaptcha(String hint) =>
      hint.contains('教务') ? mock.debugJwxtCaptcha! : mock.debugAuthCaptcha!;

  group('正方教务（RSA 加密密码 + 图形验证码）', () {
    test('验证码 → 登录 → 成绩 / 课表 / 考试', () async {
      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);

      final png = await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      expect(png.length, greaterThan(100));
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // 真 PNG
      await c.completeLogin(readCaptcha('教务'));
      expect(c.loggedIn, isTrue);
      expect(await c.checkSession(), isTrue);

      final all = await c.grades(MockCampusServer.studentId);
      expect(all['count'], 6);
      expect((all['terms'] as List).length, 2); // 两个学期
      final one = await c.grades(MockCampusServer.studentId, xnm: '2026', xqm: '3');
      expect(one['count'], 4);
      expect(one['gpa'], greaterThan(0));

      final kb = await c.kbcx(MockCampusServer.studentId, '2026', '3', 1);
      expect((kb['courses'] as List), isNotEmpty);
      expect((kb['dates'] as List).length, 7);
      expect(kb['nj'], '2026');

      final exams = await c.exams('2026', '3');
      expect(exams.length, 3);
      expect(exams.first['date'], '2027-01-10');
      expect(exams.first['start'], '08:00');
    });

    test('验证码错误 → 提示验证码；密码错误 → 直接失败不反复弹窗', () async {
      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);

      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('验证码'))),
      );

      // 重新取码后换错密码：学校原文是「用户名或密码错误」，不该被当成验证码问题重试
      await c.prepareLogin(MockCampusServer.studentId, 'wrong-password');
      await expectLater(
        () => c.completeLogin(readCaptcha('教务')),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('密码'))),
      );
    });

    // 学校页面里没有可读错误文案（新版登录页把提示交给 JS 渲染）：过去会退化成全页搜「验证码」
    // 二字，把 HTML 注释里的 `验证码-->` 当成失败原因贴给用户，还因为含「验证码」白重试三次。
    test('登录页没有错误文案 → 报状态码与页面片段，不拿页面碎片当原因', () async {
      mock.debugJwxtLoginFailBody =
          '<html><head><!--验证码--></head><body><label>验证码</label>'
          '<form id="loginForm" action="/jwglxt/xtgl/login_slogin.html"></form></body></html>';
      addTearDown(() => mock.debugJwxtLoginFailBody = null);
      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);

      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having(
          (e) => e.message,
          'message',
          allOf(contains('HTTP 200'), contains('loginForm'), isNot(contains('-->'))),
        )),
      );
    });

    test('未登录直接查业务接口 → 会话失效', () async {
      final c = JwxtClient(mock.baseUrl);
      addTearDown(c.dispose);
      await expectLater(
        () => c.kbcx(MockCampusServer.studentId, '2026', '3', 1),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('学工二课（CAS AES 加密密码 + 图形验证码）', () {
    test('CAS 登录 → 二课分数 / 活动 / 活动详情', () async {
      final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
      addTearDown(c.dispose);

      final png = await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      expect(png, isNotNull);
      await c.completeLogin(readCaptcha('统一身份认证'));
      expect(c.loggedIn, isTrue);

      final score = await c.score(MockCampusServer.studentId);
      expect((score['student'] as Map)['xm'], MockCampusServer.realName);
      expect(score['total'], '8.0');
      final groups = score['groups'] as List;
      expect(groups.map((g) => g['name']), containsAll(['德育', '劳育']));
      expect((groups.firstWhere((g) => g['name'] == '德育')['rows'] as List).length, 3);

      final payload = await c.activitiesPayload();
      expect(payload['student_id'], MockCampusServer.studentId);
      final acts = payload['activities'] as List;
      expect(acts.length, 3);
      final first = acts.firstWhere((a) => a['id'] == 'm001');
      expect(first['dlmc'], '思想成长');
      expect(first['quota'], '200 人'); // 说明里的人数被解析出来
      expect(first['signup']['qq'], contains('765432198'));
      expect(first['backdrop'] ?? first['backfill'], isFalse);

      final detail = await c.fetchActivityDetail('m002');
      expect('${detail['hdms']}', contains('社会实践'));
    });

    test('未登录查二课分数 → 会话失效', () async {
      final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
      addTearDown(c.dispose);
      await expectLater(
        () => c.score(MockCampusServer.studentId),
        throwsA(isA<ApiError>()),
      );
    });

    test('加密盐写在 id 之前也能解析（页面改版属性顺序会变）', () async {
      mock.debugFlipSaltAttribute = true;
      addTearDown(() => mock.debugFlipSaltAttribute = false);
      final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
      addTearDown(c.dispose);

      final png = await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      expect(png, isNotNull);
      await c.completeLogin(mock.debugAuthCaptcha!);
      expect(c.loggedIn, isTrue);
    });

    test('统一认证会话还在、学工会话过期：靠 SSO 自愈，不再要验证码', () async {
      final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
      addTearDown(c.dispose);

      // 先正常登录一次，建立统一认证会话（CASTGC）
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await c.completeLogin(mock.debugAuthCaptcha!);
      expect(await c.score(MockCampusServer.studentId), isNotEmpty);

      // 只丢业务会话：下次 authserver 不会再给登录页，而是带 ticket 302 回业务系统
      mock.debugForgetXgSession();
      c.loggedIn = false;
      final again = await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      expect(again, isNull, reason: '不该再要验证码：跟完 SSO 跳转其实已经登录成功');
      expect(c.loggedIn, isTrue);
      expect(await c.score(MockCampusServer.studentId), isNotEmpty);
    });

    test('登录失败要透出学校页面原文（能分辨验证码错 / 密码错）', () async {
      final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
      addTearDown(c.dispose);

      // 验证码错：真实页面把判定结果放可见的 #msg（隐藏骨架的同名文案不算数）
      await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
      await expectLater(
        () => c.completeLogin('0000'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('验证码'))),
      );

      // 密码错：可见元素里的原文（不能退化成笼统的「登录失败」，更不能拿隐藏骨架顶替）
      await c.prepareLogin(MockCampusServer.studentId, 'wrong-password');
      await expectLater(
        () => c.completeLogin(mock.debugAuthCaptcha!),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('用户名或密码错误'))),
      );
    });
  });

  group('校付宝（SM4 支付密码）', () {
    test('支付密码 → 校园码 / 卡余额 / 电费查询与充值', () async {
      final c = EpayClient(mock.baseUrl);
      addTearDown(c.dispose);
      const sid = MockCampusServer.studentId;
      const name = MockCampusServer.realName;
      const pwd = MockCampusServer.payPassword;

      final qr = await c.qrcode(sid, name, pwd);
      expect('${qr['code']}', startsWith('MOCK|$sid'));

      final ele = await c.queryElectricity(sid, name, pwd, MockCampusServer.dorm);
      expect(ele['balance'], 23.45);
      expect(ele['card_balance'], 56.70);
      expect(ele['dorm'], MockCampusServer.dorm);

      final r = await c.rechargeElectricity(sid, name, pwd, MockCampusServer.dorm, 50);
      expect(r['amount'], 50);
      expect(r['balance'], 6.70); // 校园卡扣款后的余额
      expect('${r['billno']}'.startsWith('MOCK'), isTrue);

      final after = await c.queryElectricity(sid, name, pwd, MockCampusServer.dorm);
      expect(after['balance'], 73.45); // 电费到账
    });

    test('支付密码错误 / 寝室不存在 → 学校原文提示', () async {
      final c = EpayClient(mock.baseUrl);
      addTearDown(c.dispose);
      await expectLater(
        () => c.qrcode(MockCampusServer.studentId, MockCampusServer.realName, '000000'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('支付密码'))),
      );
      await expectLater(
        () => c.queryElectricity(
            MockCampusServer.studentId, MockCampusServer.realName, MockCampusServer.payPassword, '99号楼1'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('寝室'))),
      );
    });
  });

  group('CampusDirect 登录单飞（弹窗不叠）', () {
    /// 把 App 状态切到「直连 + 本地模拟学校」。
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

    test('首页并发查询只弹一次验证码，登录后不再弹', () async {
      useMockSchool();
      var prompts = 0;
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        prompts++;
        expect(image, isNotEmpty);
        expect(error, isNull); // 第一次就成功，不该带着「上次失败」再弹
        return readCaptcha(hint);
      };

      // 主页常驻四个 Tab：启动时课表 / 二课 / 电费 / 学籍会同时查询
      final results = await Future.wait([
        CampusDirect.I.score(),
        CampusDirect.I.activities(),
        CampusDirect.I.score(),
      ]);
      expect(results.length, 3);
      expect(prompts, 1, reason: '并发查询必须共用同一次登录，只弹一个验证码弹窗');

      // 会话复用：再查不再弹
      await CampusDirect.I.score();
      expect(prompts, 1, reason: '已登录后查询不该重新弹验证码');
    });

    test('教务与学工同时登录：各弹一次，共两次', () async {
      useMockSchool();
      final hints = <String>[];
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        hints.add(hint);
        return readCaptcha(hint);
      };

      await Future.wait([
        CampusDirect.I.score(), // 学工
        CampusDirect.I.timetableWeek('2026', '3', 1), // 教务
      ]);
      expect(hints.length, 2);
      expect(hints.any((h) => h.contains('教务')), isTrue);
      expect(hints.any((h) => h.contains('统一身份认证')), isTrue);
    });

    test('教务会话超时（客户端不知情）：查询要自动重登并成功，不必手动清会话', () async {
      useMockSchool();
      var prompts = 0;
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        prompts++;
        return readCaptcha(hint);
      };

      final first = await CampusDirect.I.grades();
      expect((first['data'] as Map)['count'], 6);
      expect(prompts, 1);

      // 服务端把教务会话删掉：客户端 loggedIn 依然是 true，旧实现从此次次失败
      mock.debugForgetJwxtSession();
      final week = await CampusDirect.I.timetableWeek('2026', '3', 1);
      expect((week['courses'] as List), isNotEmpty,
          reason: '会话失效不能被误报成「该周没有课表数据」而静默不显示');
      expect(prompts, 2, reason: '自动重登会再要一次教务验证码');

      final again = await CampusDirect.I.grades();
      expect((again['data'] as Map)['count'], 6, reason: '会话失效要自动重登后重试');
      expect(prompts, 2, reason: '已经重登过，不该再弹验证码');
    });

    test('验证码输错：带着错误原因重新弹，密码错则不再弹', () async {
      useMockSchool();
      var prompts = 0;
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        prompts++;
        if (prompts == 1) {
          expect(error, isNull);
          return '0000'; // 故意输错
        }
        expect(error, contains('验证码'), reason: '第二次弹窗要说明上次为什么失败');
        return readCaptcha(hint);
      };
      final r = await CampusDirect.I.score();
      expect(prompts, 2);
      expect((r['data'] as Map)['student'], isA<Map>());

      // 密码错：弹出一次后直接抛，不拿同一个错密码连弹三次
      await CampusDirect.I.disconnect(); // 连 Cookie 一起清掉，才会真的重新登录
      AppState.I.creds.password = 'wrong-password';
      var wrongPwdPrompts = 0;
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        wrongPwdPrompts++;
        return readCaptcha(hint);
      };
      await expectLater(() => CampusDirect.I.score(), throwsA(isA<ApiError>()));
      expect(wrongPwdPrompts, 1);
    });

    test('清除直连会话后重新登录（持久化 Cookie 不残留）', () async {
      useMockSchool();
      var prompts = 0;
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        prompts++;
        return readCaptcha(hint);
      };
      await CampusDirect.I.score();
      expect(prompts, 1);

      await CampusDirect.I.disconnect();
      await CampusDirect.I.score();
      expect(prompts, 2, reason: '清除会话后就该重新登录，而不是悄悄复用持久化的旧 Cookie');
    });

    test('取消失败 → 抛出取消，不进入重试循环', () async {
      useMockSchool();
      var prompts = 0;
      CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async {
        prompts++;
        return null; // 取消
      };
      await expectLater(
        () => CampusDirect.I.score(),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('取消'))),
      );
      expect(prompts, 1);
    });
  });
}
