import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 学业情况（N105515）直连链路：真 HTTP 打本地模拟服务，验证
/// 「登录 → 首页（整体统计 + 节点树 + 隐藏域）→ 按 jdkcsx 选接口、只对叶子并发拉明细」，
/// 以及会话失效、学校业务错误、页面改版、明细非 JSON 几个分支。
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
    mock.debugAcademicIndexHtml = null;
    mock.debugAcademicCourses = null;
    mock.debugAcademicCoursesBody = null;
    mock.debugAcademicNonCourses = null;
    mock.debugLastAcademicForm = null;
    mock.debugAcademicRequestLog.clear();
  });

  Future<JwxtClient> loggedIn() async {
    final c = JwxtClient(mock.baseUrl);
    addTearDown(c.dispose);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugJwxtCaptcha!);
    return c;
  }

  Map<String, dynamic> byName(List<Map<String, dynamic>> cats, String name) =>
      cats.firstWhere((c) => c['name'] == name);

  test('首页统计 + 5 层节点树 + 叶子课程（含非课程接口）都拿得到', () async {
    final c = await loggedIn();
    final r = await c.academicStatus();

    expect(r['sid'], '25110001');
    final stats = r['statistics'] as Map<String, dynamic>;
    expect(stats['gpa'], 3.52);
    expect((stats['planed'] as Map)['total'], 60);
    expect((stats['planed'] as Map)['passed'], 52);
    expect((stats['unplaned'] as Map)['failed'], 1);

    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats, hasLength(12));

    // 5 层：主修 → 公共基础课 → 数理课程 → 高等数学 → 工科
    expect(byName(cats, '主修')['level'], 0);
    expect(byName(cats, '公共基础课')['parent'], '1000');
    expect(byName(cats, '数理课程')['level'], 2);
    expect(byName(cats, '高等数学')['level'], 3);
    expect(byName(cats, '工科')['level'], 4);

    // 通识课：有学分（4.0）且子类课程能通过「非课程信息」接口拿到
    final general = byName(cats, '通识课');
    expect(general['earned'], 4.0);
    expect(general['courses'], isEmpty, reason: '父节点本来就不发明细请求');
    final culture = byName(cats, '企业文化与职业素养');
    expect(culture['jdkcsx'], '4');
    final cultureCourses = (culture['courses'] as List).cast<Map<String, dynamic>>();
    expect(cultureCourses, hasLength(1), reason: '通识课叶子不能再显示 0 门');
    expect(cultureCourses.first['name'], '企业文化与职业素养（慕课）');
    expect(cultureCourses.first['score'], '85');
    expect(cultureCourses.first['point'], '3.5');

    // 深层叶子（level 4）课程正常
    final engineering = (byName(cats, '工科')['courses'] as List)
        .cast<Map<String, dynamic>>();
    expect(engineering, hasLength(3));
    expect(engineering.first['name'], '高等数学（工）2');
    expect(engineering.first['score'], '92');

    // 根节点直接挂课程
    final others = (byName(cats, '其他课程')['courses'] as List)
        .cast<Map<String, dynamic>>();
    expect(others, hasLength(2));
    expect(others.first['score'], '88');
  });

  test('按 jdkcsx 选接口：课程节点走教学计划、非课程节点走非课程信息', () async {
    final c = await loggedIn();
    await c.academicStatus();
    final log = mock.debugAcademicRequestLog;

    // 通识课叶子（jdkcsx='4'）→ 非课程信息接口
    expect(log, contains('noncourse:1112'));
    expect(log, contains('noncourse:1113'));
    // 工科 / 思政课程 / 其他课程（jdkcsx='1'）→ 教学计划接口
    expect(log, contains('plan:1212'));
    expect(log, contains('plan:1220'));
    expect(log, contains('plan:2000'));
    // 父节点不发明细请求
    for (final parent in ['1000', '1100', '1200', '1210', '1211']) {
      expect(log.any((e) => e.endsWith(':$parent')), isFalse, reason: '父节点 $parent 不该发请求');
    }
  });

  test('明细请求带上首页隐藏域（学号 / 成绩录入学年学期），不只传 xfyqjd_id', () async {
    final c = await loggedIn();
    await c.academicStatus();
    final form = mock.debugLastAcademicForm;
    expect(form, isNotNull);
    expect(form!['xh_id'], '25110001');
    expect(form['cjlrxn'], '2026');
    expect(form['cjlrxq'], '3');
    expect(form['bkcjlrxn'], '2026');
    expect(form['xscjcxkz'], '0');
    expect(form['cjcxkzzt'], '1');
    expect(form['fromXh_id'], '');
    expect(form['xfyqjd_id'], isNotEmpty);
  });

  test('老版静态页面（没有 jdkcsx 属性）：先教学计划、空结果兜底到非课程接口', () async {
    final c = await loggedIn();
    mock.debugAcademicIndexHtml = MockCampusServer.debugAcademicStaticPage;
    final r = await c.academicStatus();
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats, hasLength(1));
    final core = cats.first;
    expect(core['name'], '专业核心课');
    expect(core['jdkcsx'], isEmpty);
    expect(core['courses'], hasLength(2), reason: '教学计划接口有数据，不应被非课程接口覆盖');
  });

  test('会话被服务端清掉：查学业情况抛「失效」而不是静默空数据', () async {
    final c = await loggedIn();
    mock.debugForgetJwxtSession();
    await expectLater(
      c.academicStatus(),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('失效'))),
    );
  });

  test('学校返回 alert-danger：原文透出，不误报成空数据', () async {
    final c = await loggedIn();
    mock.debugAcademicIndexHtml =
        '<html><body><h5>学生学业情况查询</h5>'
        '<div class="alert alert-danger">未配置培养方案，请联系教务处</div>'
        '</body></html>';
    await expectLater(
      c.academicStatus(),
      throwsA(isA<ApiError>().having(
        (e) => e.message,
        'message',
        contains('未配置培养方案'),
      )),
    );
  });

  test('页面改版（缺 alertBox / 无节点）：不崩，统计为 null、类别可为空', () async {
    final c = await loggedIn();
    mock.debugAcademicIndexHtml = '<html><body><h5>学生学业情况查询</h5>'
        '<input id="xh_id" value="25110001"/></body></html>';
    final r = await c.academicStatus();
    final stats = r['statistics'] as Map<String, dynamic>;
    expect(stats['gpa'], isNull);
    expect(r['categories'], isEmpty);
  });

  test('教学计划接口返回非 JSON：课程节点标 coursesError，非课程接口照常出数据', () async {
    final c = await loggedIn();
    mock.debugAcademicCoursesBody = '<html><body>接口改版了</body></html>';
    final r = await c.academicStatus();
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();

    final engineering = byName(cats, '工科');
    expect(engineering['courses'], isEmpty);
    expect('${engineering['coursesError']}', contains('HTTP 200'));

    final culture = byName(cats, '企业文化与职业素养');
    expect(culture['courses'], isNotEmpty);
    expect(culture['coursesError'], isNull);
  });

  test('某个节点确实没有课程（空数组）时不影响其它节点', () async {
    final c = await loggedIn();
    mock.debugAcademicCourses = const {'1220': []};
    final r = await c.academicStatus();
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(byName(cats, '思政课程')['courses'], isEmpty);
    expect(byName(cats, '思政课程')['coursesError'], isNull);
    expect(byName(cats, '工科')['courses'], isNotEmpty);
  });
}
