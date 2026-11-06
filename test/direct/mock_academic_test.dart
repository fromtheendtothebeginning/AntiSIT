import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 学业情况（N105515）直连链路：真 HTTP 打本地模拟服务，验证
/// 「登录 → 首页（整体统计 + 节点树 + 隐藏域）→ 只对叶子节点 POST 课程明细」整条协议，
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
    mock.debugLastAcademicForm = null;
  });

  Future<JwxtClient> loggedIn() async {
    final c = JwxtClient(mock.baseUrl);
    addTearDown(c.dispose);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugJwxtCaptcha!);
    return c;
  }

  test('首页统计 + 节点树（含层级）+ 叶子节点课程明细都拿得到', () async {
    final c = await loggedIn();
    final r = await c.academicStatus();

    expect(r['sid'], '25110001');
    final stats = r['statistics'] as Map<String, dynamic>;
    expect(stats['gpa'], 3.52);
    expect((stats['planed'] as Map)['total'], 60);
    expect((stats['planed'] as Map)['passed'], 52);
    expect((stats['unplaned'] as Map)['failed'], 1);

    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats.map((e) => e['name']).toList(), ['主修', '专业核心课', '专业选修课']);
    expect(cats.map((e) => e['id']).toList(), ['9001', '9002', '9003']);
    expect(cats.map((e) => e['level']).toList(), [0, 1, 1]);
    expect(cats[1]['parent'], '9001');
    expect(cats[1]['required'], 33.0);
    expect(cats[1]['earned'], 28.0);

    // 父节点没有课程明细接口可拉（真实接口返回空数组），客户端应跳过请求。
    expect(cats[0]['courses'], isEmpty);

    final core = (cats[1]['courses'] as List).cast<Map<String, dynamic>>();
    expect(core.length, 2, reason: '9002 叶子节点应返回 2 门课程');
    expect(core[0]['name'], '高等数学(下)');
    expect(core[0]['credit'], '4.0');
    expect(core[0]['score'], '92');
    expect(core[0]['point'], '4.2');
    expect(core[0]['statusText'], '在修');
    expect(core[0]['term'], '大二上');
    expect(core[0]['coursesError'], isNull);

    final elective = (cats[2]['courses'] as List).cast<Map<String, dynamic>>();
    expect(elective.length, 1);
    expect(elective.first['name'], '人工智能导论');
    expect(elective.first['statusText'], '未过');
    expect(elective.first['score'], isEmpty, reason: '未出分的课程没有成绩');
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

  test('老版静态页面（节点直接渲染 HTML）仍能解析并拉明细', () async {
    final c = await loggedIn();
    mock.debugAcademicIndexHtml = MockCampusServer.debugAcademicStaticPage;
    final r = await c.academicStatus();
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats, hasLength(1));
    expect(cats.first['name'], '专业核心课');
    expect(cats.first['required'], 33.0);
    expect((cats.first['courses'] as List), hasLength(2));
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

  test('叶子节点明细返回非 JSON：标 coursesError 而不是当成「没有课」', () async {
    final c = await loggedIn();
    mock.debugAcademicCoursesBody = '<html><body>接口改版了</body></html>';
    final r = await c.academicStatus();
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats, isNotEmpty);
    // 父节点本来就没有明细请求，不该带错误；叶子节点要明确标失败。
    expect(cats[0]['courses'], isEmpty);
    expect(cats[0]['coursesError'], isNull);
    for (final cat in cats.skip(1)) {
      expect(cat['courses'], isEmpty);
      expect('${cat['coursesError']}', contains('HTTP 200'));
    }
  });

  test('某个节点确实没有课程（空数组）时不影响其它节点', () async {
    final c = await loggedIn();
    mock.debugAcademicCourses = const {'9002': []};
    final r = await c.academicStatus();
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats[1]['courses'], isEmpty);
    expect(cats[1]['coursesError'], isNull);
    expect(cats[2]['courses'], isNotEmpty);
  });
}
