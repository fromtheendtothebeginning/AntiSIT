import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 市场目录（`market.json`）里的一条：只带「装得下来」需要的东西。
///
/// 目录由维护者签名（见 [MarketSource]），这份解析只负责把它读成对象——
/// 校验字段合法性的是签名前的工具（`AntiSIT-market` 仓库的 `market_tool check`），
/// 所以这里对单条坏数据是**跳过**（记一条日志），不让它把整页拖崩。
class MarketEntry {
  const MarketEntry({
    required this.id,
    required this.name,
    required this.desc,
    required this.author,
    required this.category,
    required this.icon,
    required this.type,
    required this.version,
    required this.url,
    required this.homepage,
    required this.zip,
    required this.sha256,
    required this.size,
    required this.permissions,
    required this.minAppVersion,
    this.base = '',
    this.sourceId = '',
  });

  final String id;
  final String name;
  final String desc;
  final String author;
  final String category;
  final String icon;

  /// `bundle`（自包含 zip）或 `web`（第三方网址）。
  final String type;
  final String version;

  /// web 型：要打开的网址。
  final String url;
  final String homepage;

  /// bundle 型：仓库内相对路径（拼到镜像地址后面就是下载地址）。
  final String zip;

  /// bundle 型：下载后必须一致，否则不解压。
  final String sha256;
  final int size;
  final List<String> permissions;

  /// 低于它的 App 装不了（`''` = 没要求）。
  final String minAppVersion;

  /// 这条来自哪个源：**官方目录是空串**，第三方源是它解析出来的 base 地址
  /// （下载时用 `base + zip`，所以 App 不需要为第三方源再准备镜像）。
  final String base;

  /// 源 id（`''` = 官方目录）。用来判断「同一个 id 是不是换了个源在装」。
  final String sourceId;

  /// 官方目录（内置签名公钥那条）来的条目。
  bool get official => sourceId.isEmpty;

  bool get isBundle => type == 'bundle';

  /// 详情里显示「需要升级 App」用的判断。[appVersion] 形如 `1.16.0`。
  bool needsNewerApp(String appVersion) =>
      minAppVersion.isNotEmpty && compareVersions(appVersion, minAppVersion) < 0;

  static MarketEntry? tryParse(Object? raw, {String base = '', String sourceId = ''}) {
    if (raw is! Map) return null;
    String str(String key) => '${raw[key] ?? ''}'.trim();
    final id = str('id');
    final type = str('type');
    if (id.isEmpty || (type != 'bundle' && type != 'web')) return null;
    final size = raw['size'];
    final perms = raw['permissions'];
    return MarketEntry(
      id: id,
      name: str('name').isEmpty ? id : str('name'),
      desc: str('desc'),
      author: str('author'),
      category: str('category').isEmpty ? '其他' : str('category'),
      icon: str('icon'),
      type: type,
      version: str('version'),
      url: str('url'),
      homepage: str('homepage'),
      zip: str('zip'),
      sha256: str('sha256'),
      size: size is int ? size : 0,
      permissions: perms is List ? [for (final p in perms) '$p'] : const [],
      minAppVersion: str('minAppVersion'),
      base: base,
      sourceId: sourceId,
    );
  }

  /// 一条市场条目能不能用（bundle 必须有下载地址与哈希）。
  bool get usable =>
      isBundle ? (zip.isNotEmpty && sha256.isNotEmpty) : (url.startsWith('https://'));
}

/// `x.y.z` 比大小（App 的 `update_check` 里那个在 app 层，插件包够不着，这里要一份小的）。
/// 位数不等时按 0 补；非数字段当 0（不抛异常——目录里的脏数据不该把页面搞崩）。
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final s in v.split('.'))
          int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0,
      ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi < yi ? -1 : 1;
  }
  return 0;
}

/// 目录里的一条是否有「更新」：版本更高，或同版本但内容哈希变了（作者重发同一版）。
bool marketHasUpdate({
  required String installedVersion,
  required String installedSha,
  required MarketEntry entry,
}) {
  if (!entry.isBundle) return false; // 网址型没有版本概念：站点自己变
  final cmp = compareVersions(entry.version, installedVersion);
  if (cmp > 0) return true;
  if (cmp < 0) return false;
  return entry.sha256.isNotEmpty && installedSha.isNotEmpty && entry.sha256 != installedSha;
}

/// 解析整个目录：返回条目列表；坏条目跳过，坏的整份目录抛错。
List<MarketEntry> parseCatalog(List<int> bytes, {String base = '', String sourceId = ''}) {
  final raw = jsonDecode(utf8.decode(bytes));
  if (raw is! Map) throw const FormatException('市场目录不是一个 JSON 对象');
  if (raw['schema'] != 1) throw FormatException('市场目录的版本不认识：${raw['schema']}');
  final list = raw['extensions'];
  if (list is! List) throw const FormatException('市场目录里没有 extensions');
  final out = <MarketEntry>[];
  for (final item in list) {
    final e = MarketEntry.tryParse(item, base: base, sourceId: sourceId);
    if (e != null && e.usable) out.add(e);
  }
  return out;
}

/// 目录里自报的公钥（第三方源自带；官方目录没有，用 App 内置的那把）。
String catalogPublicKeyOf(List<int> bytes) {
  final raw = jsonDecode(utf8.decode(bytes));
  if (raw is! Map) throw const FormatException('市场目录不是一个 JSON 对象');
  return '${raw['publicKey'] ?? ''}'.trim();
}

/// 公钥指纹：`sha256(公钥字节)` 前 12 位，按 4 位分组（`A1B2-C3D4-E5F6`）。
/// **与市场仓库 `market_tool` 的 `keyFingerprint` 必须一致**——作者公布的指纹
/// 就是它，用户添加源时核对的也是它。
String keyFingerprintOf(String publicKeyBase64) {
  try {
    final hex = sha256.convert(base64Decode(publicKeyBase64)).toString().toUpperCase();
    if (hex.length < 12) return '(公钥无效)';
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
  } catch (_) {
    return '(公钥无效)';
  }
}

/// 目录声明的密钥 id（验签时用来挑公钥）。
String catalogKeyId(List<int> bytes) {
  final raw = jsonDecode(utf8.decode(bytes));
  if (raw is! Map) throw const FormatException('市场目录不是一个 JSON 对象');
  return '${raw['keyId'] ?? ''}';
}
