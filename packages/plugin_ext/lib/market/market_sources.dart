import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'market_entry.dart';
import 'market_source.dart';

/// 一个「第三方源」：别人在自己仓库里发布的一份签名目录。
///
/// 与官方目录的区别只有两点：
/// * 公钥是**源自报**的（写在目录里）——所以首次添加时要把它连同**指纹**拿给用户确认，
///   确认之后固定住（存在这里），以后每次刷新都用固定的那把验签；
/// * 内容没有经过官方审核，界面上必须标注（收录 ≠ 背书）。
class ExtSource {
  const ExtSource({
    required this.id,
    required this.input,
    required this.base,
    required this.label,
    required this.keyId,
    required this.publicKey,
  });

  /// 稳定 id（去掉协议与尾斜杠的 base），也是删源时的键。
  final String id;

  /// 用户当初输入的东西（回显用）：`owner/repo` 或一个 https 地址。
  final String input;

  /// 目录地址前缀（以 `/` 结尾）：`<base>market.json`。分支不行时会被换成实际可用的那个。
  final String base;

  /// 显示名（默认 `owner/repo`）。
  final String label;
  final String keyId;

  /// 首次添加时固定的公钥（之后源换了钥匙就停用它）。
  final String publicKey;

  /// [publicKey] 的指纹，给用户核对（作者公布的也是它）。
  String get fingerprint => keyFingerprintOf(publicKey);

  Map<String, Object?> toJson() => {
        'id': id,
        'input': input,
        'base': base,
        'label': label,
        'keyId': keyId,
        'publicKey': publicKey,
      };

  static ExtSource? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final base = '${raw['base'] ?? ''}'.trim();
    final pub = '${raw['publicKey'] ?? ''}'.trim();
    if (base.isEmpty || pub.isEmpty) return null;
    final label = '${raw['label'] ?? ''}'.trim();
    return ExtSource(
      id: '${raw['id'] ?? base}'.trim(),
      input: '${raw['input'] ?? ''}'.trim(),
      base: base,
      label: label.isEmpty ? base : label,
      keyId: '${raw['keyId'] ?? ''}'.trim(),
      publicKey: pub,
    );
  }
}

/// 第三方源的清单：添加 / 移除 / 刷新 / 按源下载。
///
/// 界面监听它重建。刷新时**用固定的公钥**验签：源自报的公钥与固定值不一致就停用它
/// （作者换了钥匙，或有人在中间替换，都要用户自己核对指纹后重新添加）。
class ExtSourceStore extends ChangeNotifier {
  ExtSourceStore();

  static ExtSourceStore I = ExtSourceStore();

  /// 取数函数与官方源共用同一个（测试里换桩）。
  static MarketFetcher fetcher = httpFetcher;

  static const String _kSources = 'plugin.ext.market.sources';

  /// 一次拉取的体积上限：目录只是条目列表（官方那份不到 2 KB），
  /// 第三方源给到 8 MB 已经很宽松，再大就是拿手机内存开玩笑。
  static const int maxCatalogBytes = 8 * 1024 * 1024;

  List<ExtSource> sources = const [];

  /// 每个源当前拉到的条目（按源 id 索引）。
  Map<String, List<MarketEntry>> entriesBySource = const {};

  /// 每个源的失败原因（成功的不在里面）。
  Map<String, String> errorsBySource = const {};

  bool loaded = false;
  bool refreshing = false;

  /// 所有源合起来的条目（界面把它们接在官方目录后面）。
  List<MarketEntry> get allEntries => [
        for (final s in sources) ...(entriesBySource[s.id] ?? const <MarketEntry>[]),
      ];

  ExtSource? byId(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kSources) ?? const <String>[];
    sources = [
      for (final line in raw)
        if (_tryDecode(line) case final ExtSource s) s,
    ];
    loaded = true;
    notifyListeners();
    await refresh();
  }

  static ExtSource? _tryDecode(String line) {
    try {
      return ExtSource.tryParse(jsonDecode(line));
    } catch (e) {
      debugPrint('[market] 源条目解析失败已跳过：$e');
      return null;
    }
  }

  /// 把用户输入解析成源地址并**试拉一次**（不保存）——给「添加源」对话框用：
  /// 先让用户看到源的名称、条目数与**指纹**，确认了才真正加进来。
  ///
  /// 抛 [StateError] 时消息可以直接给用户看。
  Future<({ExtSource draft, List<MarketEntry> entries})> preview(String input) async {
    final base = resolveBase(input);
    final (bytes: catalog, base: effective) = await _fetchCatalog(base);
    final sig = await _fetchSignature(effective);
    final publicKey = catalogPublicKeyOf(catalog);
    if (publicKey.isEmpty) {
      throw StateError('这个目录没有自带公钥——它可能不是「作者自己发的源」'
          '（官方目录不带公钥，因为公钥内置在 App 里）');
    }
    if (!await verifyCatalogSignature(catalog, signature: sig, publicKey: publicKey)) {
      throw StateError('目录签名校验不过：要么不是这个源签的，要么内容被改过');
    }
    final entries = parseCatalog(catalog, base: effective, sourceId: sourceIdFor(effective));
    if (entries.isEmpty) throw StateError('这个源的目录里一条拓展都没有');
    return (
      draft: ExtSource(
        id: sourceIdFor(effective),
        input: input.trim(),
        base: effective,
        label: labelFor(input, effective),
        keyId: catalogKeyId(catalog),
        publicKey: publicKey,
      ),
      entries: entries,
    );
  }

  /// 添加（用户已经核对过指纹的那个源）。
  Future<void> add(ExtSource source, List<MarketEntry> entries) async {
    sources = [...sources.where((s) => s.id != source.id), source];
    entriesBySource = {...entriesBySource, source.id: entries};
    errorsBySource = {...errorsBySource}..remove(source.id);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    sources = [for (final s in sources) if (s.id != id) s];
    entriesBySource = {...entriesBySource}..remove(id);
    errorsBySource = {...errorsBySource}..remove(id);
    await _persist();
    notifyListeners();
  }

  /// 逐个源重新拉（用固定的公钥）。
  Future<void> refresh() async {
    if (sources.isEmpty) {
      entriesBySource = const {};
      errorsBySource = const {};
      notifyListeners();
      return;
    }
    refreshing = true;
    notifyListeners();

    final entries = <String, List<MarketEntry>>{};
    final errors = <String, String>{};
    for (final s in sources) {
      try {
        final (bytes: catalog, base: effective) = await _fetchCatalog(s.base);
        final declared = catalogPublicKeyOf(catalog);
        if (declared.isNotEmpty && declared != s.publicKey) {
          errors[s.id] = '这个源换了签名密钥（原来 ${s.fingerprint}，现在 '
              '${keyFingerprintOf(declared)}）。要么作者换了钥匙，要么有人在中间替换——'
              '已停用它；和作者核对指纹之后再重新添加';
          continue;
        }
        final sig = await _fetchSignature(effective);
        if (!await verifyCatalogSignature(catalog, signature: sig, publicKey: s.publicKey)) {
          errors[s.id] = '签名校验不过（内容被改过，或作者换了密钥却没在目录里声明）';
          continue;
        }
        entries[s.id] = parseCatalog(catalog, base: effective, sourceId: s.id);
      } catch (e) {
        errors[s.id] = _short(e);
      }
    }

    entriesBySource = entries;
    errorsBySource = errors;
    refreshing = false;
    notifyListeners();
  }

  /// 按条目自己的源下载字节（官方条目走内置镜像）。
  Future<List<int>> download(MarketEntry entry) {
    if (entry.official) return MarketSource.I.download(entry.zip);
    return _fetchBytes(Uri.parse('${entry.base}${entry.zip}'),
        timeout: const Duration(seconds: 60));
  }

  // ==================== 输入解析 ====================

  /// 把用户输入变成目录地址前缀。
  /// * `owner/repo` → jsDelivr；分支不是 main 时，取数那步会自动退到 master；
  /// * 完整 `https://…` 地址 → 原样用（作者自建托管也行）。
  static String resolveBase(String input) {
    final s = input.trim();
    if (s.isEmpty) throw StateError('填一个源：`所有者/仓库`，或一个 https 地址');
    if (s.startsWith('http://') || s.startsWith('https://')) {
      final uri = Uri.tryParse(s);
      if (uri == null || uri.host.isEmpty) throw StateError('这个地址不合法：$s');
      return s.endsWith('/') ? s : '$s/';
    }
    if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(s)) {
      throw StateError('格式不对：要么 `所有者/仓库`，要么一个 https 地址（现在填的是「$s」）');
    }
    return 'https://cdn.jsdelivr.net/gh/$s@main/';
  }

  /// 源 id（去掉协议、尾斜杠）——也用来判断「同一 id 是不是换了个源在装」。
  static String sourceIdFor(String base) =>
      base.replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');

  static String labelFor(String input, String base) {
    var s = input.trim();
    if (s.startsWith('http')) {
      final uri = Uri.tryParse(s);
      s = uri == null ? base : '${uri.host}${uri.path}';
    }
    return s.isEmpty ? base : s;
  }

  static String? _masterFallback(String base) =>
      base.contains('@main/') ? base.replaceFirst('@main/', '@master/') : null;

  // ==================== 取数 ====================

  /// 取 `market.json`：先按地址试，`@main` 不行退 `@master`；
  /// 体积超限、**不是 JSON** 都单独报错。
  ///
  /// 后半句是跟 dsh 的市场学的：公共反代/加速服务出错时常回一个 HTTP 200 的 HTML
  /// 错误页，要是只说「签名校验不过」，排查方向会被带偏。
  Future<({List<int> bytes, String base})> _fetchCatalog(String base) async {
    final candidates = [base, if (_masterFallback(base) != null) _masterFallback(base)!];
    List<int>? bytes;
    String? usedBase;
    Object? lastError;
    for (final b in candidates) {
      try {
        bytes = await _fetchBytes(Uri.parse('${b}market.json'),
            timeout: const Duration(seconds: 20));
        usedBase = b;
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (bytes == null || usedBase == null) {
      throw StateError('取不到目录：${_short(lastError ?? '未知原因')}');
    }
    if (bytes.length > maxCatalogBytes) {
      throw StateError('目录太大（${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB）');
    }
    final head = String.fromCharCodes(bytes.take(40)).trimLeft();
    if (!head.startsWith('{')) {
      throw StateError('这个地址返回的不是目录（像网页或错误页）——'
          '可能是加速服务/反代挡了，换成仓库地址或另一个地址再试');
    }
    return (bytes: bytes, base: usedBase);
  }

  Future<String> _fetchSignature(String base) async {
    Object? lastError;
    for (final b in [base, if (_masterFallback(base) != null) _masterFallback(base)!]) {
      try {
        final bytes =
            await _fetchBytes(Uri.parse('${b}market.json.sig'), timeout: const Duration(seconds: 20));
        return utf8.decode(bytes).trim();
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('取不到 market.json.sig（作者是不是忘了跑 publish？）：${_short(lastError ?? '')}');
  }

  Future<List<int>> _fetchBytes(Uri url, {required Duration timeout}) async {
    try {
      return await fetcher(url).timeout(timeout);
    } on TimeoutException {
      throw StateError('请求超时：$url');
    }
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kSources, [
      for (final s in sources) jsonEncode(s.toJson()),
    ]);
  }

  static String _short(Object e) {
    final s = '$e'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
