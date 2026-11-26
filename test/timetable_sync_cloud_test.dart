import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课表云同步的 LWW 回归：云端数据解析不了时**不能**把本地清空写盘。
///
/// 历史上 `syncCloud()` 先 `semesters = {}` 再 `_adoptJson(data)`，而 `_adoptJson`
/// 内部 catch 吞掉一切异常——云端一份脏数据就会让本地课表变空并当场落盘，
/// 之后 `_pushCloud()` 还会把这份空表推上去，把云端一起污染。
void main() {
  late HttpServer server;
  late int port;
  late String body;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = false;
    AppState.I.mode = AppMode.server;
    AppState.I.token = 'test-token';
    TimetableStore.instance.semesters = {};
    TimetableStore.instance.updatedAt = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    AppState.I.serverUrl = 'http://127.0.0.1:$port';
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      if (req.method == 'GET' && req.uri.path == '/api/timetable') {
        req.response.write(body);
      } else {
        req.response.write(jsonEncode({'ok': true}));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  TtCourse course(String name) => TtCourse(
      id: name, name: name, day: 0, slotStart: 0, slotEnd: 1,
      weekType: 'all', weekStart: 1, weekEnd: 16);

  test('云端 semesters 结构不对（更新但脏）：本地课表原样保留，不落空表', () async {
    final tt = SemesterTt()..startDate = '2026-09-07';
    tt.courses = [course('高数')];
    TimetableStore.instance.semesters = {'2026-3': tt};
    TimetableStore.instance.updatedAt = 100;

    body = jsonEncode({
      'ok': true,
      'data': {
        'updatedAt': 9999, // 云端「更新」
        'semesters': {'2026-3': '坏数据'},
      },
    });

    final adopted = await TimetableStore.instance.syncCloud();

    expect(adopted, isFalse, reason: '解析不了就不算采纳');
    expect(TimetableStore.instance.semesters['2026-3']?.courses.single.name, '高数',
        reason: '云端脏数据不能把本地课表清空');

    // 关键：本地磁盘上也不能是空课表
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString('campus_timetable');
    if (saved != null) {
      expect(saved, isNot(contains('"semesters":{}')));
    }
  });

  test('云端较新且结构正常：正常采纳（修复不能把同步做成永不生效）', () async {
    final local = SemesterTt()..startDate = '2026-09-07';
    local.courses = [course('旧课')];
    TimetableStore.instance.semesters = {'2026-3': local};
    TimetableStore.instance.updatedAt = 100;

    final cloud = SemesterTt()..startDate = '2026-09-07';
    cloud.courses = [course('新课')];
    body = jsonEncode({
      'ok': true,
      'data': {
        'updatedAt': 9999,
        'active': '2026-3',
        'semesters': {'2026-3': cloud.toJson()},
      },
    });

    final adopted = await TimetableStore.instance.syncCloud();

    expect(adopted, isTrue);
    expect(TimetableStore.instance.semesters['2026-3']?.courses.single.name, '新课');
    expect(TimetableStore.instance.updatedAt, 9999);
  });
}
