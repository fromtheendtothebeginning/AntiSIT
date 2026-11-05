import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 学生侧两个新接口（2026-11 用 Edge 抓包确认）：
/// * 我的报名：POST /hdgl/list.zf `all=0`（all=1 是全部活动）
/// * 加分明细：POST /bizFlow/result/group/list.zf `groupCode=xshd`
/// 跑本地模拟校园服务，协议与真实学工系统同款。
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

  group('我的报名（all=0）', () {
    test('只回已报名活动，字段归一成列表要用的形状', () async {
      final c = await login();
      final list = await c.signedActivities();
      expect(list.length, 2);
      final first = list.first;
      expect(first['id'], 'm001');
      expect(first['name'], 'AI 赋能学习效率提升讲座');
      expect(first['dlmc'], '思想成长');
      expect(first['lbmc'], '讲座报告');
      expect(first['status_text'], '已报名'); // hdbmzt=5
      expect(first['signed'], isTrue); // bm=1
      expect(first['start'], '2026-10-10 14:00:00');
      expect(list[1]['status_text'], '无需报名'); // hdbmzt=6
    });

    test('报名状态码映射与未知码', () {
      expect(XgClient.hdStatusText('4'), '报名已满');
      expect(XgClient.hdStatusText(5), '已报名');
      expect(XgClient.hdStatusText('999'), '');
    });
  });

  group('加分明细（groupCode=xshd）', () {
    test('每条 = 活动 + 学分 + 审批状态', () async {
      final c = await login();
      final rows = await c.creditRecords();
      expect(rows.length, 2);
      expect(rows.first['name'], 'AI 赋能学习效率提升讲座');
      expect(rows.first['credit'], '0.20');
      expect(rows.first['dldm'], '德育');
      expect(rows.first['lbdm'], '讲座报告');
      expect(rows.first['status'], '通过');
      expect(rows.first['start'], '2026-10-10 14:00:00');
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
