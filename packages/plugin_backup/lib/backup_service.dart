import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机数据备份 / 恢复：只备份可重建不了的用户数据（课表、学期与作息、设置、学校档案、插件偏好）。
/// 不含账号密码、登录 token、直连 Cookie、AI Key（在 SecureStore，不该随明文 JSON 泄露）。
/// 拓展及其数据也不备份：它们含下载的文件，只恢复偏好会留下指向不存在文件的坏条目。
class BackupService {
  BackupService._();

  static const format = 'antisit-backup';
  static const version = 1;

  /// 导入文件大小上限：正常备份只有几百 KB，超过这个量级基本是选错文件。
  static const maxBytes = 20 * 1024 * 1024;

  static const _excludedExact = <String>{
    // 敏感：理论上已迁到 SecureStore，旧版本可能还在 prefs 里。
    'token',
    'username',
    'password',
    'direct_creds',
    'ai_config',
    'ai_debug_api_key',
    // 缓存 / 临时状态。
    'ai_models_cache',
    'demo',
    'tt_background_path',
    'score_targets_v1_at',
    'changelog_seen_version',
    'update_skipped_version',
  };

  static const _excludedPrefixes = <String>[
    'direct_cookies_',
    'tool_page_cache_',
    'tool_cache_',
    'tt_cache_',
    'tt_background_',
    // 拓展数据含下载的文件与卡片覆盖值，单独备份会恢复出坏条目。
    'plugin.ext.',
  ];

  /// 是否属于可备份的本机偏好；导入时也会再过滤一次，防止旧 / 恶意文件夹带敏感键。
  static bool isEligibleKey(String key) {
    if (_excludedExact.contains(key)) return false;
    return !_excludedPrefixes.any(key.startsWith);
  }

  /// 生成备份 JSON（不写文件；写文件 / 分享由页面决定）。
  static Future<String> buildJson() async {
    final sp = await SharedPreferences.getInstance();
    final prefs = <String, Map<String, Object?>>{};
    for (final key in sp.getKeys()) {
      if (!isEligibleKey(key)) continue;
      prefs[key] = _encode(sp.get(key));
    }
    final info = await PackageInfo.fromPlatform();
    final appVersion = info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
    final data = <String, Object?>{
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': appVersion,
      'excluded': const [
        '账号密码 / 登录 token / 直连 Cookie / AI Key',
        '工具页缓存（成绩、活动、电费等，可重新拉取）',
        '拓展（插件市场安装的网页拓展）及其数据',
        '课表自定义背景图路径（图片文件本身不备份）',
        '更新检查已忽略版本等临时状态',
      ],
      'prefs': prefs,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 备份文件名：`antisit-backup-YYYY-MM-DD.json`。
  static String fileName([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'antisit-backup-${t.year}-${two(t.month)}-${two(t.day)}.json';
  }

  /// 解析并校验备份，不写任何数据；格式不对 / 版本不支持抛 [FormatException]。
  static BackupPreview parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件不是 JSON 对象');
    }
    if (decoded['format'] != format) {
      throw const FormatException('这不是 AntiSIT 的备份文件');
    }
    final v = decoded['version'];
    if (v is! int || v < 1 || v > version) {
      throw FormatException('备份版本不支持：$v');
    }
    final prefsRaw = decoded['prefs'];
    if (prefsRaw is! Map) throw const FormatException('备份缺少 prefs 数据');

    final values = <String, Object>{};
    prefsRaw.forEach((key, entry) {
      final k = '$key';
      // 敏感键 / 缓存键即使出现在文件里也不恢复。
      if (!isEligibleKey(k)) return;
      if (entry is! Map) throw FormatException('备份里的「$k」格式不对');
      values[k] = _decode(k, entry);
    });
    if (values.isEmpty) throw const FormatException('备份里没有可恢复的数据');

    return BackupPreview(
      exportedAt: '${decoded['exportedAt'] ?? ''}',
      appVersion: '${decoded['appVersion'] ?? ''}',
      values: values,
    );
  }

  /// 应用备份：清本机可备份项 → 写入备份 → 清缓存 → 重载全局状态；页面随后跳回主壳。
  /// 清理范围不含 SecureStore 里的账号密码 / token / Cookie / AI Key，当前登录态保留。
  static Future<void> apply(BackupPreview preview) async {
    final sp = await SharedPreferences.getInstance();
    // 真正的恢复而不是叠加：先移除本机可备份项（含旧版课表缓存）。
    for (final key in sp.getKeys().toList()) {
      if (isEligibleKey(key) || key.startsWith('tt_cache_')) {
        await sp.remove(key);
      }
    }
    for (final e in preview.values.entries) {
      final value = e.value;
      if (value is bool) {
        await sp.setBool(e.key, value);
      } else if (value is int) {
        await sp.setInt(e.key, value);
      } else if (value is double) {
        await sp.setDouble(e.key, value);
      } else if (value is String) {
        await sp.setString(e.key, value);
      } else if (value is List<String>) {
        await sp.setStringList(e.key, value);
      }
    }

    // 工具页缓存是「上一个账号 / 上一次筛选」的数据，恢复后必须丢掉。
    await ToolPageCache.clearAll();
    await ToolCache.clear();
    AppState.I.studentInfo = null;
    AppState.I.statusInfo = null;
    AppState.I.username = null;
    AppState.I.password = null;

    // 课表：先清内存再重读，备份里没有课表时不会残留旧数据。
    TimetableStore.instance.resetForImport();
    await AppState.I.load();
    await PluginRegistry.I.load();
    await TimetableStore.instance.load();
  }

  static Map<String, Object?> _encode(Object? value) {
    if (value is bool) return {'t': 'b', 'v': value};
    if (value is int) return {'t': 'i', 'v': value};
    if (value is double) return {'t': 'd', 'v': value};
    if (value is String) return {'t': 's', 'v': value};
    if (value is List) return {'t': 'l', 'v': [for (final e in value) '$e']};
    return {'t': 's', 'v': '$value'};
  }

  static Object _decode(String key, Map entry) {
    final t = '${entry['t'] ?? ''}';
    final v = entry['v'];
    if (t == 'b' && v is bool) return v;
    if (t == 'i' && v is int) return v;
    if (t == 'd' && v is num) return v.toDouble();
    if (t == 's' && v is String) return v;
    if (t == 'l' && v is List) return [for (final e in v) '$e'];
    throw FormatException('备份里的「$key」类型不对');
  }
}

/// 解析后的备份摘要（确认弹窗用）。
class BackupPreview {
  const BackupPreview({
    required this.exportedAt,
    required this.appVersion,
    required this.values,
  });

  final String exportedAt;
  final String appVersion;
  final Map<String, Object> values;

  String get displayTime {
    final t = DateTime.tryParse(exportedAt)?.toLocal();
    if (t == null) return exportedAt.isEmpty ? '未知' : exportedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// 备份里的课表学期数，用于摘要文案。
  int get semesterCount {
    final raw = values['campus_timetable'];
    if (raw is! String) return 0;
    try {
      final j = jsonDecode(raw);
      final sems = j is Map ? j['semesters'] : null;
      return sems is Map ? sems.length : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 一行摘要：导出时间、App 版本、数据项数。
  String get summary {
    final sem = semesterCount;
    return '导出时间：$displayTime · App ${appVersion.isEmpty ? '未知' : appVersion}\n'
        '共 ${values.length} 项数据${sem > 0 ? '，含 $sem 个学期课表' : ''}';
  }
}
