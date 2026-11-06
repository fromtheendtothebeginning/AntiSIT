import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 抢课直连链路：真 HTTP 打本地模拟服务，验证
/// 「登录 → 选课轮次 → 课程列表（分页/搜索）→ 教学班 → 选课（满员重试）→ 已选课程」。
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
    mock.debugResetCourseSelection();
  });

  Future<JwxtClient> loggedIn() async {
    final c = JwxtClient(mock.baseUrl);
    addTearDown(c.dispose);
    await c.prepareLogin(MockCampusServer.studentId, MockCampusServer.password);
    await c.completeLogin(mock.debugJwxtCaptcha!);
    return c;
  }

  test('选课轮次：queryCourse 的 xkkz_id / xkkz_xh 各自独立，展示页再补齐名称', () async {
    final c = await loggedIn();
    final scopes = await c.courseScopes();

    expect(scopes, hasLength(2));
    expect(scopes[0].name, '主修选课');
    expect(scopes[0].params['xkkz_id'], 'KZ1');
    expect(scopes[0].params['xkkz_xh'], 'XH1');
    expect(scopes[0].params['xkxnm'], '2026');
    expect(scopes[0].params['xkxqm'], '12');
    expect(scopes[1].name, '通识选课');
    expect(scopes[1].params['xkkz_id'], 'KZ2');
    expect(scopes[1].params['xkkz_xh'], 'XH2');
  });

  test('课程列表：余量/满员判定、关键词过滤与 kspage/jspage 记录号分页', () async {
    final c = await loggedIn();
    final scopes = await c.courseScopes();

    final all = await c.courseOffers(scopes[0]);
    expect(all.map((e) => e.id), ['K001', 'K002']);
    expect(all[0].name, '高等数学');
    expect(all[0].isFull, isTrue);
    expect(all[0].remaining, 0);
    expect(all[1].isFull, isFalse);
    expect(all[1].remaining, 28);

    final searched = await c.courseOffers(scopes[0], keyword: '英语');
    expect(searched.map((e) => e.name), ['大学英语']);

    final page = await c.courseOffers(scopes[0], start: 1, pageSize: 1);
    expect(page.map((e) => e.id), ['K002']);
  });

  test('教学班：展开课程拿到 jxb_id / do_jxb_id 与余量', () async {
    final c = await loggedIn();
    final scopes = await c.courseScopes();
    final offers = await c.courseOffers(scopes[0]);

    final sections = await c.courseSections(offers[0]);
    expect(sections, hasLength(2));
    expect(sections[0].id, 'JXB1');
    expect(sections[0].selectionId, 'TOKEN1');
    expect(sections[0].isFull, isTrue);
    expect(sections[1].selectionId, 'TOKEN2');
    expect(sections[1].isFull, isFalse);
    expect(sections[1].remaining, 1);
  });

  test('选课：满员先返回 noCapacity，重试成功；提交表单带控制参数与 do_jxb_id', () async {
    final c = await loggedIn();
    final scopes = await c.courseScopes();
    final offers = await c.courseOffers(scopes[0]);
    final sections = await c.courseSections(offers[0]);

    mock.debugSelectFailures = 1;
    final first = await c.selectCourse(offers[0], sections[1]);
    expect(first.status, CourseSelectStatus.noCapacity);
    expect(first.ok, isFalse);
    expect(mock.debugLastSelectForm?['jxb_ids'], 'TOKEN2');
    expect(mock.debugLastSelectForm?['kch_id'], 'K001');
    expect(mock.debugLastSelectForm?['xkkz_id'], 'KZ1');
    expect(mock.debugLastSelectForm?['xkxnm'], '2026');
    expect(mock.debugLastSelectForm?['xkxqm'], '12');

    final second = await c.selectCourse(offers[0], sections[1]);
    expect(second.status, CourseSelectStatus.success);
    expect(second.ok, isTrue);

    final selected = await c.selectedCourses(scopes[0]);
    expect(selected, hasLength(1));
    expect(selected.first.name, '高等数学');
    expect(selected.first.courseId, 'K001');
    expect(selected.first.sectionId, 'TOKEN2');

    // 重复提交同一教学班：教务回「已选该教学班」，不当作失败重试。
    final again = await c.selectCourse(offers[0], sections[1]);
    expect(again.status, CourseSelectStatus.alreadySelected);
  });

  test('未登录时选课接口直接拒绝', () async {
    final c = JwxtClient(mock.baseUrl);
    addTearDown(c.dispose);
    expect(c.courseScopes(), throwsA(isA<ApiError>()));
  });
}
