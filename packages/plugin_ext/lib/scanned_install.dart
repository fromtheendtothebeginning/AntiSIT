import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:campus_core/campus_core.dart';

import 'bundle_import.dart';
import 'cordis_bundle.dart';
import 'extension_item.dart';
import 'extension_store.dart';

/// 下载并校验过、但还没解压安装的扫码拓展包。
class ScannedBundle {
  const ScannedBundle({
    required this.bytes,
    required this.manifest,
    required this.sha256,
  });

  final List<int> bytes;
  final CordisManifest manifest;

  /// 实际算出来的（也就是二维码里要求的）sha256，入列时一起存。
  final String sha256;
}

/// 扫码安装：二维码 → 下载 → **校验 sha256** → 读 ext.json → 解压入列。
///
/// 只接受 https 且必须带 sha256：二维码可以在任何地方被换成另一张图，
/// 下载完先核对内容，对不上连解压都不做。安装前由页面把包里的名称 / id / 权限
/// 列给用户确认。
class ScannedBundleInstaller {
  ScannedBundleInstaller({ExtensionStore? store}) : store = store ?? ExtensionStore.I;

  final ExtensionStore store;

  /// 压缩包原始字节上限（解压后的 8 MB / 200 文件限制在 [extractBundle] 里）。
  static const int maxBytes = 12 * 1024 * 1024;

  /// 测试注入点：替身下载（不联网）。默认走真实 HTTP。
  @visibleForTesting
  static Future<List<int>> Function(Uri url)? debugDownload;

  Future<ScannedBundle> download(ScanBundleOutcome spec) async {
    final uri = Uri.tryParse(spec.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('下载地址必须是 https');
    }
    final bytes = debugDownload != null
        ? await debugDownload!(uri)
        : await _httpDownload(uri);
    if (bytes.length > maxBytes) {
      throw StateError('拓展包太大（超过 ${maxBytes ~/ 1024 ~/ 1024} MB）');
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != spec.sha256.toLowerCase()) {
      throw StateError('下载到的内容和二维码里的 sha256 不一致，已放弃安装');
    }
    final manifest = readBundleManifest(bytes);
    if (spec.id != null && spec.id!.isNotEmpty && spec.id != manifest.id) {
      throw StateError('拓展包里的 id（${manifest.id}）与二维码里的（${spec.id}）不一致，已放弃安装');
    }
    return ScannedBundle(bytes: bytes, manifest: manifest, sha256: actual);
  }

  Future<ExtensionItem> install(ScannedBundle bundle) async {
    final manifest = bundle.manifest;
    if (store.isBuiltin(manifest.id)) {
      throw StateError('拓展 id「${manifest.id}」与内置拓展冲突，装不了');
    }
    if (store.items.any((e) => e.id == manifest.id)) {
      throw StateError('已存在 id 为「${manifest.id}」的拓展，请先卸载或让作者换一个 id');
    }
    final dir = await store.bundleDir(manifest.id);
    final ExtBundle extracted;
    try {
      extracted = extractBundle(bytes: bundle.bytes, dir: dir);
    } on FormatException catch (e) {
      throw StateError('这个拓展包有问题：${e.message}');
    } on FileSystemException catch (e) {
      throw StateError('解压失败（${e.message}）');
    }
    final item = ExtensionItem(
      id: manifest.id,
      name: manifest.name,
      url: extracted.entry,
      desc: manifest.desc,
      bundled: true,
      runtime: ExtensionItem.runtimeCordis,
      version: manifest.version,
      sha256: bundle.sha256,
      permissions: manifest.permissions,
      minAppVersion: manifest.minAppVersion,
    );
    await store.add(item);
    return item;
  }

  static Future<List<int>> _httpDownload(Uri uri) async {
    final res = await http.get(
      uri,
      headers: const {'Accept': 'application/zip,application/octet-stream,*/*'},
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw StateError('下载失败：HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }
}
