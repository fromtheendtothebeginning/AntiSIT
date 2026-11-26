import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课表本机数据损坏的回归：**不能让启动卡死，也不能把空课表写回去**。
///
/// 历史症状：`load()` 里的 `jsonDecode` 在 `_adoptJson` 的 try/catch 之外，
/// SharedPreferences 里 `campus_timetable` 一旦损坏，`load()` 直接抛异常，
/// `BootPage._boot()` 中断 → App 永远停在启动页（每次冷启动必现）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TimetableStore.instance.semesters = {};
    TimetableStore.instance.updatedAt = 0;
    TimetableStore.instance.loaded = false;
  });

  test('主键是坏 JSON：load 不抛异常，按空课表启动', () async {
    SharedPreferences.setMockInitialValues({'campus_timetable': '{不是 JSON'});
    TimetableStore.instance.semesters = {};

    await expectLater(TimetableStore.instance.load(), completes);
    expect(TimetableStore.instance.loaded, isTrue, reason: '载入流程必须走到底');
    expect(TimetableStore.instance.semesters, isEmpty);
  });

  test('主键结构不对（semesters 值不是对象）：不崩，且不把内存课表清空', () async {
    SharedPreferences.setMockInitialValues({
      'campus_timetable': '{"semesters":{"2026-3":"坏数据"},"updatedAt":100}',
    });
    final tt = SemesterTt()..startDate = '2026-09-07';
    tt.courses = [
      TtCourse(
          id: 'c1', name: '高数', day: 0, slotStart: 0, slotEnd: 1,
          weekType: 'all', weekStart: 1, weekEnd: 16),
    ];
    // 模拟「内存里已有可用课表」（例如导入流程刚写完内存），坏盘不能把它盖掉
    TimetableStore.instance.semesters = {'2026-3': tt};

    await TimetableStore.instance.load();

    expect(TimetableStore.instance.semesters['2026-3']?.courses.single.name, '高数',
        reason: '解析失败必须是「没读到」，不能顺手清成空表');
  });

  test('主键坏了但有上一次的快照：用快照恢复', () async {
    SharedPreferences.setMockInitialValues({
      'campus_timetable': '{半坏的主键',
      'campus_timetable_backup': _encodeGood(),
    });
    TimetableStore.instance.semesters = {};

    await TimetableStore.instance.load();

    expect(TimetableStore.instance.semesters['2026-3']?.courses.single.name, '线性代数');
    expect(TimetableStore.instance.updatedAt, 1000);
    // 恢复后主键要写回正常内容，避免每次冷启动都走回退
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('campus_timetable'), contains('线性代数'));
  });

  test('重新 persist 后，上一版内容成为快照（主键坏了还能救回来）', () async {
    final store = TimetableStore.instance;
    store.semester('2026', '3').courses = [
      TtCourse(
          id: 'c1', name: '大学物理', day: 2, slotStart: 0, slotEnd: 1,
          weekType: 'all', weekStart: 1, weekEnd: 16),
    ];
    await store.persist();
    // 再写一次，让上一版进入快照
    store.semester('2026', '3').courses.add(
          TtCourse(
              id: 'c2', name: '大学英语', day: 3, slotStart: 0, slotEnd: 1,
              weekType: 'all', weekStart: 1, weekEnd: 16),
        );
    await store.persist();

    final sp = await SharedPreferences.getInstance();
    final backup = sp.getString('campus_timetable_backup');
    expect(backup, isNotNull, reason: '覆盖前要留一份可解析的快照');
    expect(backup, contains('大学物理'));

    // 主键被写坏 → 退回快照
    await sp.setString('campus_timetable', '{坏');
    store.semesters = {};
    await store.load();
    expect(store.semesters['2026-3']?.courses.map((c) => c.name), contains('大学物理'));
  });
}

String _encodeGood() {
  final tt = SemesterTt()
    ..startDate = '2026-09-07'
    ..weekCount = 20
    ..courses = [
      TtCourse(
          id: 'c1', name: '线性代数', day: 1, slotStart: 2, slotEnd: 3,
          weekType: 'all', weekStart: 1, weekEnd: 16),
    ];
  return jsonEncode({
    'version': 1,
    'nj': '2024',
    'active': '2026-3',
    'updatedAt': 1000,
    'semesters': {'2026-3': tt.toJson()},
  });
}
