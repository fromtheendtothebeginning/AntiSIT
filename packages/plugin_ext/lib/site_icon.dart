import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 网站图标（favicon）的取法。
///
/// Flutter 的图片解码器**不认 `.ico`**——直接 `Image.network('.../favicon.ico')`
/// 在多数站点上都会失败（这正是「没正确显示网站 ico」的原因），所以这里自己走一套：
///
/// 1. 抓一次页面 HTML，按优先级挑图标地址：`apple-touch-icon`（PNG，一般 180×180，
///    最清楚）→ `rel="icon"` 里的位图（png / jpg / webp）→ 显式声明的 `.ico`；
/// 2. 一个都没挑到（或页面抓不到）就退到站点根的 `/favicon.ico`；
/// 3. 逐个取回字节：`.ico` 里如果嵌的是 PNG（现在多数是）就把**那一帧抠出来**再用；
///    老式的 DIB 帧不硬解（没必要，退回首字徽章就行）。
///
/// 结果按站点缓存在内存里（一次会话内不重复请求）；任何一步失败都只是「没有图标」，
/// 不影响别的功能。
class SiteIcon {
  SiteIcon._();

  /// 取图标字节（PNG / JPEG 这类 Flutter 认的格式）。测试里可以换掉它。
  static Future<Uint8List?> Function(String pageUrl) loader = forPage;

  static final Map<String, Future<Uint8List?>> _cache = {};

  /// [pageUrl] 对应站点的图标；拿不到返回 null（调用方退回首字徽章）。
  static Future<Uint8List?> forPage(String pageUrl) {
    final page = Uri.tryParse(pageUrl);
    if (page == null || page.origin.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(page.origin, () => _fetch(page, page.origin));
  }

  /// 清缓存（测试 / 想重取时用）。
  static void clearCache() => _cache.clear();

  static Future<Uint8List?> _fetch(Uri page, String origin) async {
    final candidates =
        iconCandidates(html: await _getText(page), page: page, origin: origin);
    for (final c in candidates) {
      final bytes = await _getBytes(c);
      if (bytes == null || bytes.isEmpty) continue;
      final image = isIco(bytes) ? pngFrameOfIco(bytes) : bytes;
      if (image != null && image.isNotEmpty) return image;
    }
    return null;
  }

  // ==================== 纯函数（好测）====================

  /// 候选图标地址，按优先级排：apple-touch-icon → 其它位图 → 显式 .ico → 站点根兜底。
  /// SVG 跳过（Flutter 不认）；相对地址按页面地址解析。
  static List<Uri> iconCandidates(
      {String? html, required Uri page, required String origin}) {
    final apple = <Uri>[];
    final others = <Uri>[];
    final icos = <Uri>[];
    if (html != null) {
      for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(html)) {
        final tag = m.group(0)!;
        if (!RegExp(r'''rel\s*=\s*["']?[^"'>]*icon''', caseSensitive: false)
            .hasMatch(tag)) {
          continue;
        }
        final href = RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false)
            .firstMatch(tag)
            ?.group(1);
        final uri = href == null ? null : Uri.tryParse(page.resolve(href).toString());
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) continue;
        final path = uri.path.toLowerCase();
        if (path.endsWith('.svg')) continue; // 矢量图标：交给首字徽章
        if (path.endsWith('.ico')) {
          icos.add(uri);
        } else if (tag.toLowerCase().contains('apple-touch')) {
          apple.add(uri);
        } else {
          others.add(uri);
        }
      }
    }
    final fallback = Uri.tryParse('$origin/favicon.ico');
    final out = [...apple, ...others, ...icos];
    if (fallback != null && !out.contains(fallback)) out.add(fallback);
    return out;
  }

  /// 是不是 ICO 文件（`00 00 01 00`）。
  static bool isIco(Uint8List b) =>
      b.length > 6 && b[0] == 0 && b[1] == 0 && b[2] == 1 && b[3] == 0;

  static const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// 从 ICO 里抠出最大的一帧 PNG（没有 PNG 帧则 null）。
  static Uint8List? pngFrameOfIco(Uint8List b) {
    if (!isIco(b)) return null;
    final count = _u16(b, 4);
    Uint8List? best;
    var bestW = -1;
    for (var i = 0; i < count; i++) {
      final at = 6 + i * 16;
      if (at + 16 > b.length) break;
      final w = b[at] == 0 ? 256 : b[at]; // 0 在 ICO 里表示 256
      final size = _u32(b, at + 8);
      final offset = _u32(b, at + 12);
      if (offset + size > b.length || size < 8) continue;
      if (!_startsWithPng(b, offset)) continue;
      if (w > bestW) {
        bestW = w;
        best = Uint8List.sublistView(b, offset, offset + size);
      }
    }
    return best;
  }

  static int _u16(Uint8List b, int at) => b[at] | (b[at + 1] << 8);

  static int _u32(Uint8List b, int at) =>
      b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

  static bool _startsWithPng(Uint8List b, int at) {
    if (at + _pngMagic.length > b.length) return false;
    for (var i = 0; i < _pngMagic.length; i++) {
      if (b[at + i] != _pngMagic[i]) return false;
    }
    return true;
  }

  // ==================== 网络（失败一律返回 null）====================

  static const Duration _timeout = Duration(seconds: 6);
  static const int _maxHtmlBytes = 300 * 1024;

  static Future<Uint8List?> _getBytes(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final res = await (await client.getUrl(uri)).close().timeout(_timeout);
      if (res.statusCode != 200) return null;
      final out = BytesBuilder();
      await for (final chunk in res.timeout(_timeout)) {
        out.add(chunk);
        if (out.length > 2 * 1024 * 1024) break; // 图标不至于这么大
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _getText(Uri uri) async {
    final bytes = await _getLimited(uri, _maxHtmlBytes);
    if (bytes == null) return null;
    try {
      return _decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _decode(Uint8List bytes) {
    // 页面声明的编码优先，未声明按 UTF-8 试；中文站点这样基本都对
    final head = String.fromCharCodes(bytes.sublist(0, bytes.length.clamp(0, 2048)));
    final m = RegExp(r'''charset\s*=\s*["']?([\w-]+)''', caseSensitive: false).firstMatch(head);
    final name = (m?.group(1) ?? 'utf-8').toLowerCase();
    if (name.contains('gbk') || name.contains('gb2312') || name.contains('gb18030')) {
      // Dart 没内置 GBK 解码：按字节读也能把 href 这类 ASCII 属性读对
      return String.fromCharCodes(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<Uint8List?> _getLimited(Uri uri, int max) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final res = await (await client.getUrl(uri)).close().timeout(_timeout);
      if (res.statusCode != 200) return null;
      final out = BytesBuilder();
      await for (final chunk in res.timeout(_timeout)) {
        out.add(chunk);
        if (out.length >= max) break;
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
