import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'market_entry.dart';

/// 市场目录的**签名公钥**（写死在 App 里 = 信任根）。
///
/// 对应私钥只维护者本机有（`AntiSIT-market` 仓库的 `keys/market.key`，不进仓库、不进 CI），
/// 所以拿到目录的人伪造不出目录，而目录挂哪个镜像都无所谓——镜像改内容必然验签失败。
/// 这段是 `market_tool keygen` 打出来的，换密钥时把新 keyId 加进来（旧的要留着：
/// 老 App 只认识它发版时内置的那把）。
const Map<String, String> kMarketPublicKeys = {
  'k1': '0oooGYYznJVB3bBPD42pXabM93AH5hQKqaZXxzpj/XI=',
};

/// 目录的镜像（依次尝试，谁先给出**验签通过**的目录就用谁）。
const List<String> kMarketMirrors = [
  // 国内可达性好，缓存也快
  'https://cdn.jsdelivr.net/gh/fromtheendtothebeginning/AntiSIT-market@main/',
  'https://raw.githubusercontent.com/fromtheendtothebeginning/AntiSIT-market/main/',
];

/// 取一个 URL 的字节；测试里换成桩（与 `SiteIcon.loader` 同一个套路）。
typedef MarketFetcher = Future<List<int>> Function(Uri url);

Future<List<int>> httpFetcher(Uri url) async {
  final res = await http
      .get(url, headers: const {'Accept': 'application/json,*/*'})
      .timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    throw StateError('HTTP ${res.statusCode}');
  }
  return res.bodyBytes;
}

/// 目录状态：UI 按它决定显示什么。
enum MarketStatus {
  idle,

  /// 正在拉。
  loading,

  /// 拿到了一份验签通过的目录（可能来自缓存，看 [MarketSource.fromCache]）。
  ready,

  /// 网络与缓存都没有可用目录。
  failed,
}

/// 插件市场目录：拉取 + **验签** + 缓存 + 提供下载。
///
/// 页面监听它重建。目录本身很小（几十 KB），缓存原样存本地，
/// 断网时仍然能看已装拓展有没有更新——但缓存同样要过验签，不然缓存就成了后门。
class MarketSource extends ChangeNotifier {
  MarketSource();

  /// 宿主启动时换成真实实例；测试里换成干净的。
  static MarketSource I = MarketSource();

  /// 公钥与取数函数都可替换（测试用）。
  static Map<String, String> publicKeys = kMarketPublicKeys;
  static MarketFetcher fetcher = httpFetcher;

  static const String _kCatalog = 'plugin.ext.market.catalog';
  static const String _kSig = 'plugin.ext.market.sig';
  static const String _kAt = 'plugin.ext.market.at';

  /// 上次成功的镜像（跨会话记住，下次先试它——别每次都从第一个开始试错）。
  /// 这是跟 dsh 的市场学的：按资源记住可用线路，只在失败后才换线。
  static const String _kMirror = 'plugin.ext.market.mirror';

  /// 目录体积上限（官方那份不到 2 KB；拦的是一反代就吐几十兆的情况）。
  static const int maxCatalogBytes = 8 * 1024 * 1024;

  MarketStatus status = MarketStatus.idle;
  List<MarketEntry> entries = const [];

  /// 人话的失败原因（网络 / 验签 / 格式），失败时给页面显示。
  String error = '';

  /// 这份目录来自本地缓存（网络没通）。
  bool fromCache = false;

  /// 拉到的时间（缓存里存的也算）。
  DateTime? fetchedAt;

  /// 取到目录的那个镜像（下载拓展包优先走它，省一次试错）。
  String activeBase = '';

  bool get ready => status == MarketStatus.ready;

  MarketEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 拉一份目录：镜像依次试 → 每个都**验签** → 存缓存；全挂了退回缓存（同样验签）。
  ///
  /// 已经拿到过就不重复拉（页面每次进来不该都打网络）；要强制刷新传 [force]。
  Future<void> load({bool force = false}) async {
    if (status == MarketStatus.loading) return;
    if (ready && !force) return;

    status = MarketStatus.loading;
    error = '';
    notifyListeners();

    final problems = <String>[];
    for (final base in await _mirrorOrder()) {
      try {
        final catalog = await fetcher(Uri.parse('${base}market.json'));
        if (catalog.length > maxCatalogBytes) {
          problems.add('$base：目录太大（${(catalog.length / 1024 / 1024).toStringAsFixed(1)} MB）');
          continue;
        }
        // 反代/加速服务出错时会回 HTTP 200 的 HTML 错误页：单独说清，
        // 不然报「签名校验不过」会把排查方向带偏
        if (!String.fromCharCodes(catalog.take(40)).trimLeft().startsWith('{')) {
          problems.add('$base：返回的不是目录（像网页或错误页，可能被反代挡了）');
          continue;
        }
        final sig = utf8.decode(await fetcher(Uri.parse('${base}market.json.sig'))).trim();
        final bad = await _verifyProblem(catalog, sig);
        if (bad != null) {
          problems.add('$base：$bad');
          continue;
        }
        _use(parseCatalog(catalog), base: base, cached: false, at: DateTime.now());
        await _saveCache(catalog, sig);
        return;
      } catch (e) {
        problems.add('$base：${_shortError(e)}');
      }
    }

    // 网络没通：用上次验签通过的缓存（缓存也要验，不然改个文件就能骗过 App）
    final sp = await SharedPreferences.getInstance();
    final cached = sp.getString(_kCatalog);
    final cachedSig = sp.getString(_kSig);
    if (cached != null && cachedSig != null) {
      final bytes = utf8.encode(cached);
      final bad = await _verifyProblem(bytes, cachedSig);
      if (bad == null) {
        final at = sp.getInt(_kAt) ?? 0;
        _use(parseCatalog(bytes),
            base: '', cached: true, at: at == 0 ? null : DateTime.fromMillisecondsSinceEpoch(at));
        error = '网络没通，用的是上次缓存的目录'
            '${problems.isEmpty ? '' : '（${problems.first}）'}';
        return;
      }
      problems.add('缓存：$bad');
    }

    status = MarketStatus.failed;
    error = problems.isEmpty ? '拉不到市场目录' : problems.join('\n');
    notifyListeners();
  }

  /// 验签不通过的原因（通过返回 null）。
  Future<String?> _verifyProblem(List<int> catalog, String signature) async {
    final String keyId;
    try {
      keyId = catalogKeyId(catalog);
    } catch (e) {
      return '目录读不了（${_shortError(e)}）';
    }
    final pub = publicKeys[keyId];
    if (pub == null || pub.trim().isEmpty) {
      return '目录用的密钥「$keyId」这个版本不认识（要升级 App）';
    }
    final ok = await verifyCatalogSignature(catalog, signature: signature, publicKey: pub);
    return ok ? null : '目录签名校验不过（内容被改过？）';
  }

  void _use(List<MarketEntry> list,
      {required String base, required bool cached, DateTime? at}) {
    entries = list;
    activeBase = base;
    fromCache = cached;
    if (base.isNotEmpty) unawaited(_rememberMirror(base));
    fetchedAt = at;
    status = MarketStatus.ready;
    notifyListeners();
  }

  Future<void> _saveCache(List<int> catalog, String sig) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kCatalog, utf8.decode(catalog));
    await sp.setString(_kSig, sig);
    await sp.setInt(_kAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// 镜像尝试顺序：上次成功的那个排第一，其余按内置顺序。
  Future<List<String>> _mirrorOrder() async {
    final sp = await SharedPreferences.getInstance();
    final remembered = sp.getString(_kMirror);
    if (remembered == null || !kMarketMirrors.contains(remembered)) {
      return kMarketMirrors;
    }
    return [remembered, ...kMarketMirrors.where((b) => b != remembered)];
  }

  Future<void> _rememberMirror(String base) async {
    if (!kMarketMirrors.contains(base)) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMirror, base);
  }

  /// 下载一个拓展包（`market.json` 里的相对路径）：先走当前镜像，再依次试别的。
  /// **不校验哈希**——校验交给装的人（[MarketInstaller]），它才有目录里那个值。
  Future<List<int>> download(String relativePath) async {
    if (relativePath.trim().isEmpty) throw StateError('这条拓展没有下载地址');
    final ordered = await _mirrorOrder();
    final bases = [
      if (activeBase.isNotEmpty) activeBase,
      for (final b in ordered)
        if (b != activeBase) b,
    ];
    final problems = <String>[];
    for (final base in bases) {
      try {
        // 目录里的路径带缓存戳：镜像换内容时 hash 变了，URL 跟着变（免得吃旧缓存）
        return await fetcher(Uri.parse('$base$relativePath'));
      } catch (e) {
        problems.add('$base：${_shortError(e)}');
      }
    }
    throw StateError('下载失败：${problems.join('；')}');
  }

  static String _shortError(Object e) {
    final s = '$e'.replaceFirst('Exception: ', '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

/// Ed25519 验签。**这段与市场仓库 `lib/market_signing.dart` 的 verify 必须一致**
/// （App 不能反向依赖那个仓库，所以这里是一份小拷贝；两边都靠单测与真目录兜住）。
Future<bool> verifyCatalogSignature(
  List<int> bytes, {
  required String signature,
  required String publicKey,
}) async {
  try {
    final sig = base64Decode(signature);
    if (sig.length != 64) return false;
    final pub = base64Decode(publicKey);
    if (pub.length != 32) return false;
    return await Ed25519().verify(
      bytes,
      signature: Signature(sig, publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
    );
  } catch (_) {
    return false;
  }
}
