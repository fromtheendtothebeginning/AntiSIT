import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'cordis_bundle.dart';

/// 导入的 Cordis 拓展压缩包解出来之后的样子。
class ExtBundle {
  const ExtBundle({required this.dir, required this.entry, required this.manifest});

  /// 解压目录（绝对路径）。
  final String dir;

  /// 入口 main.js 的绝对路径。
  final String entry;

  final CordisManifest manifest;
}

/// 只读压缩包里的 `ext.json`（导入前先拿 id / 名称，避免先解压到错目录）。
CordisManifest readBundleManifest(List<int> bytes) {
  final entries = <String, ArchiveFile>{};
  for (final f in ZipDecoder().decodeBytes(bytes).files) {
    if (!f.isFile) continue;
    final name = normalizeEntryPath(f.name);
    if (name != null) entries[name] = f;
  }
  final rel = _stripSingleTopDir(entries);
  final manifestFile = rel['ext.json'];
  if (manifestFile == null) {
    throw const FormatException('压缩包里没找到 ext.json（Cordis 拓展的清单）');
  }
  try {
    return CordisManifest.parse(
      jsonDecode(utf8.decode(manifestFile.content as List<int>, allowMalformed: true)),
    );
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('ext.json 解析失败：$e');
  }
}

/// 把 zip 解开到 [dir]，返回 Cordis 清单与入口。
///
/// 约定（也写给拓展作者看，见 docs/extensions.md）：
/// * 所有文件都在同一个顶层目录里时自动去掉这层（`zip -r x.zip myapp/` 也能直接用）；
/// * 根目录必须有 `ext.json`，其中 `main` 指向入口 `.js`；
/// * **安全**：绝对路径 / `..` / 盘符这类条目整条丢掉，绝不写到目标目录外面（zip-slip）。
///
/// 清单不合法 / 缺入口抛 [FormatException]，消息直接拿去给用户看。
ExtBundle extractBundle({required List<int> bytes, required String dir}) {
  final entries = <String, ArchiveFile>{};
  var total = 0;
  for (final f in ZipDecoder().decodeBytes(bytes).files) {
    if (!f.isFile) continue;
    final name = normalizeEntryPath(f.name);
    if (name == null) continue;
    total += f.size;
    if (entries.length >= 200 || total > 8 * 1024 * 1024) {
      throw const FormatException('压缩包太大（最多 200 个文件 / 解压后 8 MB）');
    }
    entries[name] = f;
  }

  final rel = _stripSingleTopDir({
    for (final e in entries.entries) e.key: e.value,
  });
  final manifestFile = rel['ext.json'];
  if (manifestFile == null) {
    throw const FormatException('压缩包里没找到 ext.json（Cordis 拓展的清单）');
  }
  final CordisManifest manifest;
  try {
    manifest = CordisManifest.parse(
      jsonDecode(utf8.decode(manifestFile.content as List<int>, allowMalformed: true)),
    );
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('ext.json 解析失败：$e');
  }
  if (!rel.containsKey(manifest.main)) {
    throw FormatException('ext.json 的 main「${manifest.main}」在压缩包里不存在');
  }
  if (manifest.style.isNotEmpty && !rel.containsKey(manifest.style)) {
    throw FormatException('ext.json 的 style「${manifest.style}」在压缩包里不存在');
  }

  final out = Directory(dir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);
  for (final e in rel.entries) {
    final target = File('$dir/${e.key}');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(e.value.content as List<int>);
  }
  return ExtBundle(
    dir: dir,
    entry: '$dir/${manifest.main}',
    manifest: manifest,
  );
}

/// 「所有文件都在同一个顶层目录」时去掉这层。
Map<String, ArchiveFile> _stripSingleTopDir(Map<String, ArchiveFile> entries) {
  if (entries.isEmpty) return entries;
  final tops = {for (final n in entries.keys) n.split('/').first};
  if (tops.length != 1 || entries.keys.every((n) => !n.contains('/'))) {
    return entries;
  }
  final prefix = '${tops.first}/';
  return {
    for (final e in entries.entries)
      if (e.key.startsWith(prefix)) e.key.substring(prefix.length): e.value,
  };
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
