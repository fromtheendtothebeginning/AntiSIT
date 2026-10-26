import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新检查的来源：GitHub Release 与 Gitee 镜像同步发行（见 tool/release_gitee.sh）。
const String updateRepo = 'fromtheendtothebeginning/AntiSIT';

/// Gitee 镜像仓库：国内直连更快，更新检查与下载都优先走它。
const String giteeUpdateRepo = 'ender123/AntiSIT';

/// 更新源：Gitee 优先（国内访问快，APK 也从这里下）；读不到再 GitHub；
/// 两个都访问不了时退回自建镜像——`anticraft.top/apk/latest.json` 放一份**同结构**的
/// Release JSON。所有源会并发查询，取版本最高的那份；同版本优先靠前的源，
/// 这样 Gitee 镜像偶尔滞后也不会把 GitHub 上的新版藏起来。
final List<Uri> latestReleaseApis = [
  Uri.parse('https://gitee.com/api/v5/repos/$giteeUpdateRepo/releases/latest'),
  Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'),
  Uri.parse('https://anticraft.top/apk/latest.json'),
];

/// 一个比本机新的版本，以及引导更新要用的东西。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
  });

  /// 版本号（去掉 tag 的 v 前缀，如 1.13.6）。
  final String version;

  /// 变更清单（Release 说明里「本次更新」那一段，已收拾成纯文本）。
  final String notes;

  /// Release 页面：看细节、手动下载的入口。
  final String pageUrl;

  /// 安装包直链（Release 资产里的 .apk）；没挂资产时为 null。
  final String? apkUrl;
}

/// 'v1.13.5' / ' 1.13.5 ' → '1.13.5'
String normalizeVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  return s;
}

/// 版本号比较：a 新于 b 返回正数、旧返回负数、等价返回 0。
///
/// 只比数字段（`1.13` 与 `1.13.0` 等价），构建号（`+92`）不参与——同一个版本号
/// 重发一次不该提示更新；尾部的预发布标记（`1.14.0-rc1`）算「比正式版旧」。
int compareVersions(String a, String b) {
  final (na, pa) = _splitVersion(a);
  final (nb, pb) = _splitVersion(b);
  final len = na.length > nb.length ? na.length : nb.length;
  for (var i = 0; i < len; i++) {
    final x = i < na.length ? na[i] : 0;
    final y = i < nb.length ? nb[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  if (pa == pb) return 0;
  if (pa.isEmpty) return 1; // 正式版 > 预发布
  if (pb.isEmpty) return -1;
  return pa.compareTo(pb);
}

/// 'v1.13.5+92' → ([1, 13, 5], '')；'1.14.0-rc1' → ([1, 14, 0], 'rc1')。
(List<int>, String) _splitVersion(String raw) {
  var s = normalizeVersion(raw).split('+').first;
  final parts = s.split('-');
  final nums = [for (final p in parts.first.split('.')) int.tryParse(p) ?? 0];
  return (nums, parts.length > 1 ? parts.sublist(1).join('-') : '');
}

/// GitHub Release JSON → [UpdateInfo]；没有 tag_name（出错时的返回体）返回 null。
UpdateInfo? parseRelease(Map<String, dynamic> json) {
  final tag = '${json['tag_name'] ?? ''}'.trim();
  if (tag.isEmpty) return null;
  String? apk;
  for (final a in (json['assets'] as List? ?? const [])) {
    final asset = a as Map;
    if ('${asset['name'] ?? ''}'.endsWith('.apk')) {
      final url = '${asset['browser_download_url'] ?? ''}';
      if (url.isNotEmpty) apk = url;
      break;
    }
  }
  final page = '${json['html_url'] ?? ''}';
  return UpdateInfo(
    version: normalizeVersion(tag),
    notes: releaseSummary('${json['body'] ?? ''}'),
    pageUrl: page.isNotEmpty ? page : 'https://github.com/$updateRepo/releases',
    apkUrl: apk,
  );
}

/// Release 说明 → 弹窗里的变更清单：有「### 本次更新」就只取它之后的内容
/// （前面是安装说明模板，对升级的人来说是废话），去掉 markdown 记号与空行。
String releaseSummary(String body) {
  var text = body.replaceAll('\r\n', '\n');
  const marker = '### 本次更新';
  final i = text.indexOf(marker);
  if (i >= 0) text = text.substring(i + marker.length);
  final lines = <String>[];
  for (final raw in text.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    line = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    line = line.replaceFirst(RegExp(r'^[-*]\s+'), '· ');
    lines.add(line);
  }
  return lines.join('\n');
}

/// 更新检查：启动时静默查一次（见 HomePage），也能随时在「我的 → 检查更新」手动查。
///
/// 只发一个请求、不上报任何信息；结论放在 [available]，「稍后」过的版本记在
/// [skipped] 里不再自动弹窗（手动检查照旧能看到）。
class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker I = UpdateChecker._();

  static const _kSkipped = 'update_skipped_version';
  static const _timeout = Duration(seconds: 8);

  /// 本机版本号（PackageInfo 读；测试环境没有平台实现，读不到就是空串）。
  String current = '';

  /// 比本机新的最新版本；已是最新 / 检查失败时为 null。
  UpdateInfo? available;

  /// 上次检查的失败原因（手动检查时提示用，成功时清空）。
  String? error;

  /// 用户点过「稍后」的版本：该版本不自动弹窗，等下一个版本再说。
  String? skipped;

  bool checking = false;

  /// 有可用更新、且用户还没忽略过它——启动时该不该弹引导。
  bool get shouldPrompt => available != null && available!.version != skipped;

  /// 测试注入点：不为 null 时用它取 Release JSON，不联网。
  @visibleForTesting
  Future<Map<String, dynamic>> Function()? debugFetch;

  /// 读本机版本与「已忽略的版本」（启动时、「我的」页各一次）。
  Future<void> load() async {
    if (current.isEmpty) current = await _installedVersion();
    try {
      skipped = (await SharedPreferences.getInstance()).getString(_kSkipped);
    } catch (_) {} // 读不到偏好不影响后续检查
    notifyListeners();
  }

  /// 查一次最新版本并和本机比。失败只记 [error]，不清掉上次的结论。
  Future<void> check() async {
    if (checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      if (current.isEmpty) current = await _installedVersion();
      if (current.isEmpty) {
        error = '读不到本机版本';
        return;
      }
      final info = parseRelease(await (debugFetch?.call() ?? _fetchLatest()));
      available = info != null && compareVersions(info.version, current) > 0 ? info : null;
    } catch (e) {
      error = _reason(e);
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// 忽略本版本（弹窗上的「稍后」）：之后不再自动弹，手动检查仍能看到。
  Future<void> skip() async {
    final v = available?.version;
    if (v == null) return;
    skipped = v;
    try {
      await (await SharedPreferences.getInstance()).setString(_kSkipped, v);
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    current = '';
    available = null;
    error = null;
    skipped = null;
    checking = false;
    debugFetch = null;
  }

  Future<String> _installedVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return ''; // 测试环境 / 平台不支持：当作读不到，检查直接跳过
    }
  }

  Future<Map<String, dynamic>> _fetchLatest() =>
      fetchLatestFrom(latestReleaseApis, _fetchOne);

  Future<Map<String, dynamic>> _fetchOne(Uri api) async {
    final res = await http
        .get(api,
            headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'AntiSIT'})
        .timeout(_timeout);
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map<String, dynamic>) throw const FormatException('接口返回的不是 JSON 对象');
    return j;
  }

  /// 失败原因 → 给用户看的短句（接口限流与网络不通最常见）。
  String _reason(Object e) {
    if (e is TimeoutException) return '网络超时';
    final s = '$e';
    if (s.contains('403')) return '更新源接口限流（403），过一会儿再试';
    if (s.contains('404')) return '仓库里还没有发布过版本';
    return '网络不可用（Gitee、GitHub 与镜像都访问不了）';
  }
}

/// 并发查询所有更新源，取版本最高的那份；同版本优先靠前的源（Gitee 在前，
/// 下载地址就走 Gitee）。全部失败抛出**最后一个源**的错误——先试的源报错
/// 往往是限流/被墙，末尾镜像的错误更利于说明整体不可用。
Future<Map<String, dynamic>> fetchLatestFrom(
  Iterable<Uri> sources,
  Future<Map<String, dynamic>> Function(Uri) fetch,
) async {
  final list = sources.toList();
  if (list.isEmpty) throw StateError('没有可用的更新源');
  final found = <(int, String, Map<String, dynamic>)>[];
  final errors = List<Object?>.filled(list.length, null);

  Future<void> one(int i) async {
    try {
      final j = await fetch(list[i]);
      final info = parseRelease(j);
      if (info != null) found.add((i, info.version, j));
    } catch (e) {
      errors[i] = e;
    }
  }

  await Future.wait([for (var i = 0; i < list.length; i++) one(i)]);
  if (found.isEmpty) {
    for (var i = errors.length - 1; i >= 0; i--) {
      final e = errors[i];
      if (e != null) throw e;
    }
    throw const FormatException('更新源都没有返回版本信息');
  }
  found.sort((a, b) {
    final c = compareVersions(a.$2, b.$2);
    return c != 0 ? -c : a.$1.compareTo(b.$1);
  });
  return found.first.$3;
}
