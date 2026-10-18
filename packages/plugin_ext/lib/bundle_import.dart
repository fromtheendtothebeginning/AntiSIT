import 'dart:io';

import 'package:archive/archive.dart';

/// 导入的压缩包解出来之后的样子。
class ExtBundle {
  const ExtBundle({required this.dir, required this.entry});

  /// 解压目录（绝对路径）。
  final String dir;

  /// 入口 html 的绝对路径。
  final String entry;
}

/// 把 zip 解开到 [dir]，返回入口 html。
///
/// 约定（也写给拓展作者看，见 docs/extensions.md）：
/// * 所有文件都在同一个顶层目录里时自动去掉这层（`zip -r x.zip myapp/` 也能直接用）；
/// * 入口优先取根目录的 `index.html`，没有就取根目录排序后第一个 `*.html`；
/// * **安全**：绝对路径 / `..` / 盘符这类条目整条丢掉，绝不写到目标目录外面（zip-slip）。
///
/// 找不到 html 抛 [FormatException]，消息直接拿去给用户看。
ExtBundle extractBundle({required List<int> bytes, required String dir}) {
  final entries = <String, ArchiveFile>{};
  for (final f in ZipDecoder().decodeBytes(bytes).files) {
    if (!f.isFile) continue;
    final name = normalizeEntryPath(f.name);
    if (name != null) entries[name] = f;
  }

  final out = Directory(dir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final entry = entryFileOf(entries.keys);
  if (entry == null) {
    out.deleteSync(recursive: true);
    throw const FormatException('压缩包里没找到 html（根目录放一个 index.html 最省事）');
  }
  for (final e in entries.entries) {
    final target = File('$dir/${e.key}');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(e.value.content as List<int>);
  }
  return ExtBundle(dir: dir, entry: '$dir/$entry');
}

/// 条目路径归一化：绝对路径 / 盘符 / 含 `..` / 空名一律返回 null（不写盘）。
String? normalizeEntryPath(String raw) {
  var s = raw.replaceAll('\\', '/').trim();
  while (s.startsWith('./')) {
    s = s.substring(2);
  }
  if (s.isEmpty || s.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(s)) return null;
  final parts = <String>[];
  for (final seg in s.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') return null; // zip-slip：宁可整条丢掉
    parts.add(seg);
  }
  return parts.isEmpty ? null : parts.join('/');
}

/// 入口文件：先去掉「所有文件都在同一个顶层目录」的那层，再按
/// `index.html` → 排序后第一个 `*.html` 找；没有 html 返回 null。
String? entryFileOf(Iterable<String> names) {
  final all = names.toList();
  if (all.isEmpty) return null;
  final tops = {for (final n in all) n.split('/').first};
  final strip =
      tops.length == 1 && all.every((n) => n.contains('/')) ? '${tops.first}/' : '';
  final rel = [
    for (final n in all)
      if (n.startsWith(strip)) n.substring(strip.length),
  ];
  final htmls = [
    for (final n in rel)
      if (n.toLowerCase().endsWith('.html')) n,
  ]..sort();
  if (htmls.contains('index.html')) return '${strip}index.html';
  return htmls.isEmpty ? null : '$strip${htmls.first}';
}

/// 读压缩包目录里的一个相对文件（入口页内联时用）：
/// 越界（`..` / 绝对路径）或不存在的返回 null。
String? readBundleFile(String dir, String relative) {
  final name = normalizeEntryPath(relative);
  if (name == null) return null;
  final f = File('$dir/$name');
  if (!f.existsSync()) return null;
  try {
    return f.readAsStringSync();
  } catch (_) {
    return null; // 不是文本 / 读不动：交给调用方原样留着
  }
}

/// 打开压缩包导入的拓展：读入口 html，并把同目录的 css / js 内联进去，
/// 交给内核当 `html` 打开——不依赖 WebView 的 file:// 权限，也就不会撞上
/// 新版 Android 的文件访问限制（代价：html 里引用图片 / 字体这类资源不会被内联，
/// 相对路径的资源在部分平台可能加载不出来，所以三件套请自包含）。
String bundlePageHtml(String entry) {
  final dir = File(entry).parent.path;
  var html = File(entry).readAsStringSync();
  return inlineLocalAssets(html, (rel) => readBundleFile(dir, rel));
}

/// 把 html 里同目录的 `<link href="x.css">` 与 `<script src="x.js"></script>`
/// 就地内联成自包含页面；外链（http/https/协议相对）与读不到的文件原样留着。
String inlineLocalAssets(String html, String? Function(String relative) read) {
  var out = html.replaceAllMapped(
      RegExp(r'''<link\b[^>]*?href\s*=\s*["']([^"']+\.css)["'][^>]*>''', caseSensitive: false),
      (m) {
    final href = m.group(1)!;
    if (_isRemote(href)) return m.group(0)!;
    final css = read(href.split('?').first.split('#').first);
    return css == null ? m.group(0)! : '<style>\n$css\n</style>';
  });
  out = out.replaceAllMapped(
      RegExp(r'''<script\b[^>]*?src\s*=\s*["']([^"']+)["'][^>]*>\s*</script>''',
          caseSensitive: false), (m) {
    final src = m.group(1)!;
    if (_isRemote(src)) return m.group(0)!;
    final js = read(src.split('?').first.split('#').first);
    if (js == null) return m.group(0)!;
    // 内联脚本里出现 </script> 会把标签截断，转义掉
    return '<script>\n${js.replaceAll('</script>', r'<\/script>')}\n</script>';
  });
  return out;
}

bool _isRemote(String ref) =>
    ref.startsWith('http://') || ref.startsWith('https://') || ref.startsWith('//');

/// 给内置页注入一条 CSP（[applyExtensionCsp] 用的策略串）。
///
/// **默认禁网**：`zip` 拓展是自包含页面，审核过的那份代码就该是手机上跑的那份——
/// 不让它运行时再去作者服务器拉新脚本。声明了 `network` 权限才把 connect / 图片 / 字体
/// 放开到 `https:`。
///
/// `script-src 'unsafe-inline'`：页面的脚本是打包时内联进来的，没法给 hash。
String extensionCsp({required bool allowNetwork}) => allowNetwork
    ? "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
        "img-src data: https:; font-src data: https:; media-src https:; "
        "connect-src https:; form-action 'none'; base-uri 'none'"
    : "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
        "img-src data:; font-src data:; connect-src 'none'; "
        "form-action 'none'; base-uri 'none'";

/// 把上面那条策略塞进 html 的 `<head>`（没有 head 就塞在 `<!doctype>` 之后）。
///
/// CSP 只从它出现的位置往后生效，所以要尽量靠前；插在 `<head>` 之后即满足。
/// 已经带了 CSP 的页面原样返回（不跟作者自己的策略打架）。
String applyExtensionCsp(String html, {required bool allowNetwork}) {
  if (RegExp(r'''http-equiv\s*=\s*["']?content-security-policy''', caseSensitive: false)
      .hasMatch(html)) {
    return html;
  }
  final meta =
      '<meta http-equiv="Content-Security-Policy" content="${extensionCsp(allowNetwork: allowNetwork)}">';
  final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (head != null) return html.replaceRange(head.end, head.end, meta);
  final doctype = RegExp(r'<!doctype[^>]*>', caseSensitive: false).firstMatch(html);
  if (doctype != null) return html.replaceRange(doctype.end, doctype.end, meta);
  return '$meta$html';
}
