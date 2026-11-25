import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 学生侧接口：我的报名用 POST /bizFlow/result/group/list.zf groupCode=xshd（本人记录，不是匿名公共池），加分明细同接口；跑模拟服务。
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
    await CampusDirect.I.disconnect();
  });

  Future<XgClient> login() async {
    final c = XgClient(authBase: mock.profile().authBase, xgBase: mock.baseUrl);
    addTearDown(c.dispose);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugAuthCaptcha!);
    return c;
  }

  group('我的报名（bizFlow 报名结果查询）', () {
    test('回本人报名记录，字段归一成列表要用的形状', () async {
      final c = await login();
      final list = await c.signedActivities();
      expect(list.length, 2);
      final first = list.first;
      expect(first['id'], 'm001'); // 活动 id（详情页用它）
      expect(first['name'], 'AI 赋能学习效率提升讲座');
      expect(first['dlmc'], '德育');
      expect(first['lbmc'], ''); // bizFlow 无类别中文名，留空
      expect(first['status_text'], '已报名'); // flowstatusmc=通过 → 已报名
      expect(first['signed'], isTrue);
      expect(first['start'], '2026-10-10 14:00:00');
      expect(list[1]['name'], '秋季校园马拉松志愿者');
    });

    test('报名状态码映射与未知码', () {
      expect(XgClient.hdStatusText('4'), '报名已满');
      expect(XgClient.hdStatusText(5), '已报名');
      expect(XgClient.hdStatusText('999'), '');
    });
  });

  group('加分明细（groupCode=xsrd 学分认定）', () {
    test('每条 = 活动 + 认定学分 + 审批状态', () async {
      final c = await login();
      final rows = await c.creditRecords();
      expect(rows.length, 2);
      expect(rows.first['name'], 'AI 赋能学习效率提升讲座');
      expect(rows.first['credit'], '0.20'); // rdxs 认定学分
      expect(rows.first['dldm'], '美育');
      expect(rows.first['lbdm'], '校园文化活动');
      expect(rows.first['status'], '通过');
      // xsrd 组没有活动起止时间，页面回退用 CREATE_TIME（认定/提交时间）
      expect(rows.first['start'], null);
      expect(rows.first['date'], '2026-10-11 09:00:00');
      expect(rows[1]['credit'], '0.50');
    });
  });

  test('CampusDirect 包装：登录一次、两个接口都可查', () async {
    AppState.I
      ..school = mock.profile()
      ..creds = (CampusCreds()
        ..studentId = MockCampusServer.studentId
        ..password = MockCampusServer.password);
    CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) async =>
        mock.debugAuthCaptcha!;

    final signed = await CampusDirect.I.signedActivities();
    expect((signed['activities'] as List).length, 2);
    final credits = await CampusDirect.I.creditRecords();
    expect((credits['records'] as List).length, 2);
  });
}
