import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_backup/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 备份格式与恢复流程：敏感键不进备份、类型能原样往返、导入会覆盖同名数据并清理旧缓存。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStore.I = MemorySecureStore();
    PluginRegistry.I = PluginRegistry();
    TimetableStore.instance.resetForImport();
    PackageInfo.setMockInitialValues(
      appName: 'AntiSIT',
      packageName: 'top.anticraft.campus_service',
      version: '1.33.0',
      buildNumber: '155',
      buildSignature: '',
    );
  });

  test('导出：包含课表/设置，排除凭据、缓存、拓展与背景路径', () async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://example.com',
      'campus_timetable': '{"semesters":{"2026-3":{}},"active":"2026-3"}',
      'campus_slot_times': '{"starts":[],"ends":[]}',
      'plugin_theme': 'theme.glass',
      'plugin.ext.items': '[{"id":"x"}]',
      'plugin.ext.data.x.k': 'v',
      'direct_cookies_jwxt': '{"jwxt.sit.edu.cn":{}}',
      'tool_page_cache_v1_grades': '{}',
      'tool_cache_score': '{}',
      'tt_background_path': '/tmp/bg.png',
      'update_skipped_version': '1.2.3',
      'ai_config': '{"keys":{"deepseek":"sk"}}',
      'token': 'legacy-token',
    });

    final raw = await BackupService.buildJson();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    expect(j['format'], 'antisit-backup');
    expect(j['version'], 1);
    expect(j['appVersion'], '1.33.0+155');
    final prefs = (j['prefs'] as Map).keys.cast<String>().toSet();
    expect(prefs, containsAll([
      'server_url',
      'campus_timetable',
      'campus_slot_times',
      'plugin_theme',
    ]));
    for (final key in [
      'direct_cookies_jwxt',
      'tool_page_cache_v1_grades',
      'tool_cache_score',
      'tt_background_path',
      'update_skipped_version',
      'ai_config',
      'token',
    ]) {
      expect(prefs, isNot(contains(key)), reason: '$key 不应进备份');
    }
    expect(prefs.any((k) => k.startsWith('plugin.ext.')), isFalse);
  });

  test('解析：字符串/布尔/整数/小数/字符串列表原样往返', () async {
    SharedPreferences.setMockInitialValues({
      'x_string': '文本',
      'x_bool': true,
      'x_int': 3,
      'x_double': 1.5,
      'x_list': <String>['a', 'b'],
    });

    final preview = BackupService.parse(await BackupService.buildJson());

    expect(preview.values['x_string'], '文本');
    expect(preview.values['x_bool'], true);
    expect(preview.values['x_int'], 3);
    expect(preview.values['x_double'], 1.5);
    expect(preview.values['x_list'], ['a', 'b']);
  });

  test('解析：格式/版本不对、没有数据都拒绝', () {
    expect(() => BackupService.parse('not json'), throwsFormatException);
    expect(
      () => BackupService.parse('{"format":"other","version":1,"prefs":{}}'),
      throwsFormatException,
    );
    expect(
      () => BackupService.parse('{"format":"antisit-backup","version":99,"prefs":{}}'),
      throwsFormatException,
    );
    expect(
      () => BackupService.parse('{"format":"antisit-backup","version":1,"prefs":{}}'),
      throwsFormatException,
    );
  });

  test('解析：旧/恶意文件里夹带敏感键也会被忽略', () {
    final raw = jsonEncode({
      'format': 'antisit-backup',
      'version': 1,
      'prefs': {
        'token': {'t': 's', 'v': 'x'},
        'direct_cookies_jwxt': {'t': 's', 'v': 'x'},
        'plugin.ext.items': {'t': 's', 'v': 'x'},
        'server_url': {'t': 's', 'v': 'https://example.com'},
      },
    });

    final preview = BackupService.parse(raw);

    expect(preview.values.keys, ['server_url']);
  });

  test('导入：覆盖同名数据、清理旧的可备份项并重载课表', () async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://old.example.com',
      'dim_completed': false,
      'direct_cookies_jwxt': 'keep-me',
    });
    final timetable = jsonEncode({
      'version': 1,
      'active': '2026-3',
      'semesters': {
        '2026-3': {
          'startDate': '2026-09-07',
          'courses': [],
          'events': [],
          'adjust': [],
        },
      },
      'updatedAt': 1,
    });
    final raw = jsonEncode({
      'format': 'antisit-backup',
      'version': 1,
      'appVersion': '1.33.0+155',
      'prefs': {
        'server_url': {'t': 's', 'v': 'https://new.example.com'},
        'campus_timetable': {'t': 's', 'v': timetable},
      },
    });

    await BackupService.apply(BackupService.parse(raw));

    expect(AppState.I.serverUrl, 'https://new.example.com');
    expect(TimetableStore.instance.semesters.keys, contains('2026-3'));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('server_url'), 'https://new.example.com');
    expect(sp.getBool('dim_completed'), isNull,
        reason: '可备份项未出现在备份里时按恢复处理，回到默认');
    expect(AppState.I.dimCompleted, isTrue);
    expect(sp.getString('direct_cookies_jwxt'), 'keep-me',
        reason: '敏感键不在备份/清理范围，保持本机现状');
  });

  test('文件名与摘要可读', () {
    expect(BackupService.fileName(DateTime(2026, 11, 13)), 'antisit-backup-2026-11-13.json');
    final preview = BackupPreview(
      exportedAt: '2026-11-13T08:00:00.000Z',
      appVersion: '1.33.0+155',
      values: const {
        'campus_timetable': '{"semesters":{"a":{},"b":{}}}',
      },
    );
    expect(preview.semesterCount, 2);
    expect(preview.summary, contains('2 个学期课表'));
  });
}
