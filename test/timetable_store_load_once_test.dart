import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课表「一个进程只读一次」的守卫（启动耗时优化）。
///
/// 启动页已经读过本机课表，课表页首次构建时又会调一次 load()：没有守卫时那份
/// JSON 会被完整解析第二遍（含坏数据回退、旧缓存迁移），纯属白等一个磁盘往返。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'campus_timetable': _encode('线性代数'),
    });
    TimetableStore.instance.semesters = {};
    TimetableStore.instance.updatedAt = 0;
    TimetableStore.instance.loaded = false;
    TimetableStore.slotStarts = TimetableStore.defaultSlotStarts;
    TimetableStore.slotEnds = TimetableStore.defaultSlotEnds;
  });

  test('读过一次后再调 load：直接返回，不重新解析磁盘', () async {
    final store = TimetableStore.instance;

    await store.load();
    expect(store.loaded, isTrue);
    expect(store.semesters['2026-3']?.courses.single.name, '线性代数');

    // 模拟「启动页读完后，课表页又触发了一次」：内存里的课表应当原样保留，
    // 不能因为重读磁盘而回退 / 覆盖。
    store.semester('2026', '3').courses = const [];
    await store.load();
    expect(store.semesters['2026-3']?.courses, isEmpty, reason: '已读过就不该再读盘');
  });

  test('备份恢复先 resetForImport：守卫失效，真正重读磁盘', () async {
    final store = TimetableStore.instance;
    await store.load();
    expect(store.semesters['2026-3']?.courses.single.name, '线性代数');

    // 恢复备份后磁盘内容已经换了一份（BackupService.restore 会先 resetForImport）
    final sp = await SharedPreferences.getInstance();
    await sp.setString('campus_timetable', _encode('大学物理'));
    store.resetForImport();

    await store.load();
    expect(store.loaded, isTrue);
    expect(
      store.semesters['2026-3']?.courses.single.name,
      '大学物理',
      reason: 'resetForImport 之后必须真的从本机读回新数据',
    );
  });
}

String _encode(String name) {
  final tt = SemesterTt()
    ..startDate = '2026-09-07'
    ..weekCount = 20
    ..courses = [
      TtCourse(
        id: 'c1',
        name: name,
        day: 1,
        slotStart: 2,
        slotEnd: 3,
        weekType: 'all',
        weekStart: 1,
        weekEnd: 16,
      ),
    ];
  return jsonEncode({
    'version': 1,
    'nj': '2024',
    'active': '2026-3',
    'updatedAt': 1000,
    'semesters': {'2026-3': tt.toJson()},
  });
}
