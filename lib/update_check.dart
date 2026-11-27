import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 更新源仓库（Gitee 镜像的发行由 tool/release_gitee.sh 同步）。
const String updateRepo = 'fromtheendtothebeginning/AntiSIT';

/// Gitee 镜像仓库：国内直连更快，更新检查与下载都优先走它。
const String giteeUpdateRepo = 'ender123/AntiSIT';

/// 更新源，按优先级排列：Gitee（国内快、APK 也从这里下）、GitHub、自建镜像
/// （`anticraft.top/apk/latest.json` 放同结构的 Release JSON）。
final List<Uri> latestReleaseApis = [
  Uri.parse('https://gitee.com/api/v5/repos/$giteeUpdateRepo/releases/latest'),
  Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'),
  Uri.parse('https://anticraft.top/apk/latest.json'),
];

/// 渠道检查要的是 Release **列表**：稳定版与内测版各挑一份最高的出来。
/// 镜像只会放单份 latest.json，列表端点失败不影响前两个源。
final List<Uri> releaseListApis = [
  Uri.parse(
    'https://gitee.com/api/v5/repos/$giteeUpdateRepo/releases?per_page=50',
  ),
  Uri.parse('https://api.github.com/repos/$updateRepo/releases?per_page=50'),
  Uri.parse('https://anticraft.top/apk/releases.json'),
];

/// 允许下载安装包 / 校验文件的主机：Release JSON 来自可被替换的更新源，不限主机就能把 APK 指到任意地址。
const Set<String> _allowedUpdateHosts = {
  'gitee.com',
  'github.com',
  'anticraft.top',
};

const List<String> _allowedUpdateHostSuffixes = [
  '.gitee.com',
  '.giteeusercontent.com',
  '.github.com',
  '.githubusercontent.com',
  '.anticraft.top',
];

/// 更新下载地址是否可信：必须 https，且主机在发布域白名单内。
bool isAllowedUpdateUrl(Uri uri) {
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  return _allowedUpdateHosts.contains(host) ||
      _allowedUpdateHostSuffixes.any((s) => host.endsWith(s));
}

/// 更新渠道：稳定版只跟正式 tag，内测版跟带预发布段的开发 tag（`v1.48.0-dev.2`）。
enum UpdateChannel { stable, dev }

/// 持久化键（渠道值），改名字等于丢用户选择。
String channelKey(UpdateChannel c) =>
    c == UpdateChannel.stable ? 'stable' : 'dev';

/// 界面上的叫法：「内测版」对用户比「开发版」更好懂，代码里仍叫 dev。
String channelLabel(UpdateChannel c) =>
    c == UpdateChannel.stable ? '稳定版' : '内测版';

/// 版本号（或 tag）属于哪个渠道：带 `-dev.N` / `-rc2` 这类预发布段的是内测版。
UpdateChannel channelOfVersion(String version) =>
    normalizeVersion(version).split('+').first.contains('-')
    ? UpdateChannel.dev
    : UpdateChannel.stable;

/// 一个比本机新的版本，以及引导更新要用的东西。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.sha256Url,
  });

  /// 版本号（去掉 tag 的 v 前缀，如 1.13.6）。
  final String version;

  /// 变更清单（Release 说明里「本次更新」那一段，已收拾成纯文本）。
  final String notes;

  /// Release 页面：看细节、手动下载的入口。
  final String pageUrl;

  /// 安装包直链（Release 资产里的 .apk）；没挂资产时为 null。
  final String? apkUrl;

  /// 安装包的 sha256 校验文件（Release 资产里的 .apk.sha256），下载后先对哈希再交给安装器。
  final String? sha256Url;

  /// 这份 Release 属于哪个渠道（由版本号的预发布段决定）。
  UpdateChannel get channel => channelOfVersion(version);

  /// 能否应用内下载安装：APK 直链与 sha256 缺一不可且都在发布域白名单内。
  /// 发布页漏挂校验文件时退回浏览器下载，绝不在没有哈希的情况下自动安装。
  bool get canSelfInstall {
    final a = apkUrl == null ? null : Uri.tryParse(apkUrl!);
    final s = sha256Url == null ? null : Uri.tryParse(sha256Url!);
    return a != null &&
        s != null &&
        isAllowedUpdateUrl(a) &&
        isAllowedUpdateUrl(s);
  }
}

/// 'v1.13.5' / ' 1.13.5 ' → '1.13.5'
String normalizeVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  return s;
}

/// 版本号比较：a 新于 b 返回正数、旧返回负数、等价返回 0。
/// 只比数字段（`1.13` 与 `1.13.0` 等价），构建号不参与，尾部预发布标记算「比正式版旧」。
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
  // 预发布段不能按字典序比：`rc10` < `rc2`、`alpha` < `beta` 都会反。
  return _comparePreRelease(pa, pb);
}

/// 预发布段比较：先按 `.` / `-` 切段，每段再拆「字母前缀 + 数字后缀」按 (alpha, num) 比。
/// 这样 `rc2 < rc10`、`alpha < beta`、`rc1 < rc1.1`；纯数字段比纯字母段新。
int _comparePreRelease(String a, String b) {
  final pa = a.split(RegExp(r'[.-]')).where((s) => s.isNotEmpty).toList();
  final pb = b.split(RegExp(r'[.-]')).where((s) => s.isNotEmpty).toList();
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    if (i >= pa.length) return -1; // 前缀相同，段多的更新（rc1 < rc1.1）
    if (i >= pb.length) return 1;
    final c = _compareSegment(pa[i], pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// 单个预发布段比较：`rc10` 拆成 ('rc', 10)，`10` 拆成 ('', 10)，`beta` 拆成 ('beta', -1)。
int _compareSegment(String a, String b) {
  final (ka, na) = _splitSegment(a);
  final (kb, nb) = _splitSegment(b);
  if (ka != kb) return ka.compareTo(kb) > 0 ? 1 : -1;
  if (na == nb) return 0;
  return na > nb ? 1 : -1;
}

(String, int) _splitSegment(String s) {
  final m = RegExp(r'^([A-Za-z]*)(\d*)$').firstMatch(s);
  if (m == null) return (s.toLowerCase(), -1); // 认不出的段按整串文字比
  final num = m.group(2)!;
  return (m.group(1)!.toLowerCase(), num.isEmpty ? -1 : int.parse(num));
}

/// 'v1.13.5+92' → ([1, 13, 5], '')；'1.14.0-rc1' → ([1, 14, 0], 'rc1')。
(List<int>, String) _splitVersion(String raw) {
  var s = normalizeVersion(raw).split('+').first;
  final parts = s.split('-');
  final nums = [for (final p in parts.first.split('.')) int.tryParse(p) ?? 0];
  return (nums, parts.length > 1 ? parts.sublist(1).join('-') : '');
}

/// Release JSON（GitHub / Gitee / 自建镜像同构）→ [UpdateInfo]，没有 tag_name 返回 null。
UpdateInfo? parseRelease(Map<String, dynamic> json) {
  final tag = '${json['tag_name'] ?? ''}'.trim();
  if (tag.isEmpty) return null;
  String? apk, sha256;
  for (final a in (json['assets'] as List? ?? const [])) {
    final asset = a as Map;
    final name = '${asset['name'] ?? ''}';
    final url = '${asset['browser_download_url'] ?? ''}';
    if (url.isEmpty) continue;
    // 不在发布域白名单里的资产直接丢弃：宁可退回浏览器，也不把任意地址当成官方 APK。
    final parsed = Uri.tryParse(url);
    if (parsed == null || !isAllowedUpdateUrl(parsed)) continue;
    if (name.endsWith('.apk')) apk ??= url;
    if (name.endsWith('.apk.sha256')) sha256 ??= url;
  }
  final page = '${json['html_url'] ?? ''}';
  final pageUri = Uri.tryParse(page);
  return UpdateInfo(
    version: normalizeVersion(tag),
    notes: releaseSummary('${json['body'] ?? ''}'),
    // Gitee 接口不返回 html_url，发布页回落到 Gitee 仓库页；非 https 的页面地址一律弃用。
    pageUrl: pageUri != null && pageUri.scheme == 'https'
        ? page
        : 'https://gitee.com/$giteeUpdateRepo/releases',
    apkUrl: apk,
    sha256Url: sha256,
  );
}

/// Release 说明 → 弹窗里的变更清单：只取「### 本次更新」之后的内容，去掉 markdown 记号与空行。
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

/// 一批 Release → 两个渠道各自最高的那份（同版本先出现的源优先）。
({UpdateInfo? stable, UpdateInfo? dev}) selectByChannel(
  Iterable<Map<String, dynamic>> releases,
) {
  UpdateInfo? stable;
  UpdateInfo? dev;
  for (final json in releases) {
    final info = parseRelease(json);
    if (info == null) continue;
    switch (info.channel) {
      case UpdateChannel.stable:
        if (stable == null ||
            compareVersions(info.version, stable.version) > 0) {
          stable = info;
        }
      case UpdateChannel.dev:
        if (dev == null || compareVersions(info.version, dev.version) > 0) {
          dev = info;
        }
    }
  }
  return (stable: stable, dev: dev);
}

/// 更新检查：启动时静默查一次（见 HomePage），也能随时在「我的 → 检查更新」手动查。
/// 只发请求、不上报信息；「稍后」过的版本按渠道各记一条，不再自动弹窗。
class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker I = UpdateChecker._();

  /// 旧键（只有一条，渠道上线前留下的）：读到时按那个版本所属渠道归位。
  static const _kSkippedLegacy = 'update_skipped_version';
  static const _kChannel = 'update_channel';
  static const _kPrompt = 'update_prompt_enabled';
  String _skippedKey(UpdateChannel c) => 'update_skipped_${channelKey(c)}';
  static const _timeout = Duration(seconds: 8);

  /// 本机版本号（PackageInfo 读；测试环境没有平台实现，读不到就是空串）。
  String current = '';

  /// 用户选择的更新渠道（默认稳定版）。
  UpdateChannel channel = UpdateChannel.stable;

  /// 有新版本时自动弹窗提醒（用户可在检查更新二级页关掉）。
  bool promptEnabled = true;

  /// 各渠道的最新版本（不再各处重复请求）。
  UpdateInfo? stableLatest;
  UpdateInfo? devLatest;

  /// 比本机新的版本，按渠道分开记：已是最新 / 检查失败时为 null。
  UpdateInfo? stableAvailable;
  UpdateInfo? devAvailable;

  /// 上次检查的失败原因（手动检查时提示用，成功时清空）。
  String? error;

  /// 用户点过「稍后」的版本（每个渠道各一条）：该版本不自动弹窗，等下一个版本再说。
  final Map<UpdateChannel, String?> _skipped = {};

  /// 是否正在检查。
  bool checking = false;

  /// 上次检查时间（二级界面用来显示「刚刚检查」）。
  DateTime? lastCheck;

  /// 当前渠道可用的新版本。
  UpdateInfo? get available =>
      channel == UpdateChannel.dev ? devAvailable : stableAvailable;

  /// 某个渠道可用的新版本。
  UpdateInfo? availableFor(UpdateChannel c) =>
      c == UpdateChannel.dev ? devAvailable : stableAvailable;

  /// 某个渠道的最新版本（含不高于本机的）。
  UpdateInfo? latestFor(UpdateChannel c) =>
      c == UpdateChannel.dev ? devLatest : stableLatest;

  /// 当前渠道里用户点过「稍后」的版本。
  String? get skipped => _skipped[channel];

  /// 有可用更新、弹窗提醒开着、且用户还没忽略过它——启动时该不该弹引导。
  bool get shouldPrompt =>
      promptEnabled && available != null && available!.version != skipped;

  /// 测试注入点：不为 null 时用它取 Release JSON（单份或列表都行），不联网。
  @visibleForTesting
  Future<Object?> Function()? debugFetch;

  /// 读本机版本、渠道、弹窗开关与各渠道「已忽略的版本」（启动时、「我的」页各一次）。
  Future<void> load() async {
    if (current.isEmpty) current = await _installedVersion();
    try {
      final prefs = await SharedPreferences.getInstance();
      channel = prefs.getString(_kChannel) == channelKey(UpdateChannel.dev)
          ? UpdateChannel.dev
          : UpdateChannel.stable;
      promptEnabled = prefs.getBool(_kPrompt) ?? true;
      for (final c in UpdateChannel.values) {
        _skipped[c] = prefs.getString(_skippedKey(c));
      }
      final legacy = prefs.getString(_kSkippedLegacy);
      if (legacy != null && legacy.isNotEmpty) {
        final c = channelOfVersion(legacy);
        _skipped[c] ??= legacy;
      }
    } catch (_) {} // 读不到偏好不影响后续检查
    notifyListeners();
  }

  /// 查一次各渠道的最新版本并和本机比。失败只记 [error]，不清掉上次的结论。
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
      final releases = await _loadReleases();
      final picked = selectByChannel(releases);
      stableLatest = picked.stable;
      devLatest = picked.dev;
      stableAvailable = _newer(picked.stable);
      devAvailable = _newer(picked.dev);
      lastCheck = DateTime.now();
    } catch (e) {
      error = _reason(e);
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// 切换更新渠道（立即落盘；之后启动按新渠道判断有没有新版本）。
  Future<void> setChannel(UpdateChannel c) async {
    if (channel == c) return;
    channel = c;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _kChannel,
        channelKey(c),
      );
    } catch (_) {}
    notifyListeners();
  }

  /// 开 / 关「有新版本时弹窗提示」。
  Future<void> setPromptEnabled(bool v) async {
    if (promptEnabled == v) return;
    promptEnabled = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_kPrompt, v);
    } catch (_) {}
    notifyListeners();
  }

  /// 忽略本版本（弹窗上的「稍后」）：之后不再自动弹，手动检查仍能看到。
  Future<void> skip() async {
    final info = available;
    if (info == null) return;
    await skipVersion(info.version);
  }

  /// 忽略某个版本（按版本号归到它自己的渠道）。
  Future<void> skipVersion(String version) async {
    final c = channelOfVersion(version);
    _skipped[c] = version;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _skippedKey(c),
        version,
      );
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    current = '';
    channel = UpdateChannel.stable;
    promptEnabled = true;
    stableLatest = null;
    devLatest = null;
    stableAvailable = null;
    devAvailable = null;
    error = null;
    lastCheck = null;
    _skipped.clear();
    checking = false;
    debugFetch = null;
  }

  UpdateInfo? _newer(UpdateInfo? info) =>
      info != null && compareVersions(info.version, current) > 0 ? info : null;

  Future<String> _installedVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return ''; // 测试环境 / 平台不支持：当作读不到，检查直接跳过
    }
  }

  /// 取各更新源的 Release 列表并合并；全部失败才抛错（单源失败只丢那一家）。
  Future<List<Map<String, dynamic>>> _loadReleases() async {
    if (debugFetch != null) {
      final raw = await debugFetch!();
      return _asReleaseList(raw);
    }
    final errors = <Object>[];
    final lists = <List<Map<String, dynamic>>>[];
    await Future.wait([
      for (final api in releaseListApis)
        () async {
          try {
            lists.add(await _fetchList(api));
          } catch (e) {
            errors.add(e);
          }
        }(),
    ]);
    if (lists.isEmpty) {
      // 列表端点全挂：退回旧的 latest 单份接口，至少稳定版还能查。
      try {
        return [await fetchLatestFrom(latestReleaseApis, _fetchOne)];
      } catch (_) {
        throw errors.isEmpty
            ? const FormatException('更新源都没有返回版本信息')
            : errors.last;
      }
    }
    return [for (final l in lists) ...l];
  }

  Future<List<Map<String, dynamic>>> _fetchList(Uri api) async {
    final res = await http
        .get(
          api,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'AntiSIT',
          },
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    return _asReleaseList(j);
  }

  Future<Map<String, dynamic>> _fetchOne(Uri api) async {
    final res = await http
        .get(
          api,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'AntiSIT',
          },
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map<String, dynamic>) {
      throw const FormatException('接口返回的不是 JSON 对象');
    }
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

/// 接口返回体 → Release 列表：数组是列表，单个对象（latest.json）当作只有一份。
List<Map<String, dynamic>> _asReleaseList(Object? raw) {
  if (raw is List) {
    return [
      for (final e in raw)
        if (e is Map<String, dynamic>)
          e
        else if (e is Map)
          Map<String, dynamic>.from(e),
    ];
  }
  if (raw is Map<String, dynamic>) return [raw];
  if (raw is Map) return [Map<String, dynamic>.from(raw)];
  throw const FormatException('接口返回的不是 Release JSON');
}

/// 并发查询所有更新源，取版本最高的那份；同版本优先靠前的源（下载地址跟着它走）。
/// 全部失败时抛出**最后一个源**的错误：末尾镜像的错误更能说明整体不可用。
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
