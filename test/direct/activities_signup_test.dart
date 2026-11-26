import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 活动报名（hdsq）回归：动态表单预填字段原样回传、复合字段 hdkssj|hdjssj 拆分、附件字段剔除、自述字段透传；跑本地模拟校园服务。
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

  Future<XgClient> login() async {
    final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
    addTearDown(c.dispose);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugAuthCaptcha!);
    return c;
  }

  group('学工活动报名（hdsq 工作流）', () {
    test('成功：预填原样回传 + 复合时间拆开 + 附件剔除 + 自述项保持学校空值', () async {
      final c = await login();
      // 报名前详情的 bm = 0（未报名），报名后变 1——服务端以此透传 signed
      expect((await c.fetchActivityDetail('m001'))['bm'], 0);
      final r = await c.signupActivity('m001');
      expect((r['instance_id'] as String), isNotEmpty);
      expect((await c.fetchActivityDetail('m001'))['bm'], 1);

      final form = mock.debugLastSignupForm!;
      expect(form['hdid'], 'm001');
      expect(form['xh'], MockCampusServer.studentId); // 学籍预填来自学校 defaultValue
      expect(form['xm'], MockCampusServer.realName);
      expect(form['hdkssj'], '2026-10-10 14:00:00'); // hdkssj|hdjssj 拆成两项
      expect(form['hdjssj'], '2026-10-10 16:00:00');
      expect(form['decisionSignature'], ''); // 前端固定附加的空签名域
      expect(form.containsKey('hdkssj|hdjssj'), isFalse);
      expect(form.containsKey('bmfj'), isFalse, reason: '附件字段不参与提交');
      expect(form['bmyy'], '', reason: 'App 不填自述项：学校的空预填值原样回传');
    });

    test('重复报名同一活动 → 学校原文拒绝', () async {
      final c = await login();
      await c.signupActivity('m001');
      await expectLater(
        () => c.signupActivity('m001'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('已报名'))),
      );
    });

    test('活动不存在 → 表单接口的业务错误原文抛出', () async {
      final c = await login();
      await expectLater(
        () => c.signupActivity('nope'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('活动不存在'))),
      );
    });
  });
}
