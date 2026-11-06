import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'cordis_runtime.dart';
import 'extension_item.dart';

/// Cordis 拓展的清单（`ext.json`）。
class CordisManifest {
  const CordisManifest({
    required this.id,
    required this.name,
    required this.main,
    this.desc = '',
    this.version = '0.1.0',
    this.style = '',
    this.permissions = const [],
    this.minAppVersion = '',
  });

  final String id;
  final String name;
  final String desc;
  final String version;
  final String main;
  final String style;
  final List<String> permissions;
  final String minAppVersion;

  static const int nameMaxLength = ExtensionItem.nameMaxLength;
  static const int descMaxLength = ExtensionItem.descMaxLength;

  /// 只接受简单 id：安装目录、存储 key 都拿它拼接，不能带路径分隔符。
  static final RegExp idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$');

  /// manifest 里的入口 / 样式只能是包内相对路径，不能借 `..` 或盘符逃出目录。
  static String _safePath(String raw, String field) {
    final s = raw.replaceAll('\\', '/');
    if (s.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(s)) {
      throw FormatException('ext.json 的 $field 必须是相对路径');
    }
    final norm = p.posix.normalize(s);
    if (norm == '..' || norm.startsWith('../') || norm.startsWith('/')) {
      throw FormatException('ext.json 的 $field 不能指向目录外');
    }
    return norm;
  }

  static CordisManifest parse(Object? json) {
    if (json is! Map) throw const FormatException('ext.json 必须是一个 JSON 对象');
    String s(String key) => '${json[key] ?? ''}'.trim();
    final id = s('id');
    if (!idPattern.hasMatch(id)) {
      throw const FormatException('ext.json 的 id 只能用小写字母 / 数字 / . _ -，3–64 位');
    }
    final name = s('name');
    if (name.isEmpty) throw const FormatException('ext.json 缺少 name');
    if (name.length > nameMaxLength) {
      throw FormatException('ext.json 的 name 最多 $nameMaxLength 个字');
    }
    final desc = s('desc');
    if (desc.length > descMaxLength) {
      throw FormatException('ext.json 的 desc 最多 $descMaxLength 个字');
    }
    final mainRaw = s('main');
    final main = mainRaw.isEmpty ? '' : _safePath(mainRaw, 'main');
    if (main.isEmpty) throw const FormatException('ext.json 缺少 main（入口 js）');
    if (!main.endsWith('.js')) {
      throw const FormatException('ext.json 的 main 必须是 .js 文件');
    }
    final style = s('style').isEmpty ? '' : _safePath(s('style'), 'style');
    if (style.isNotEmpty && !style.endsWith('.css')) {
      throw const FormatException('ext.json 的 style 必须是 .css 文件');
    }
    final permissions = <String>[];
    final rawPermissions = json['permissions'];
    if (rawPermissions != null) {
      if (rawPermissions is! List) {
        throw const FormatException('ext.json 的 permissions 必须是数组');
      }
      for (final raw in rawPermissions) {
        final value = '$raw'.trim();
        if (value.isEmpty) continue;
        if (!permissions.contains(value)) permissions.add(value);
      }
    }
    return CordisManifest(
      id: id,
      name: name,
      desc: desc,
      version: s('version').isEmpty ? '0.1.0' : s('version'),
      main: main,
      style: style,
      permissions: permissions,
      minAppVersion: s('minAppVersion'),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (desc.isNotEmpty) 'desc': desc,
        'version': version,
        'main': main,
        if (style.isNotEmpty) 'style': style,
        if (permissions.isNotEmpty) 'permissions': permissions,
        if (minAppVersion.isNotEmpty) 'minAppVersion': minAppVersion,
      };
}

/// 读一个已解压的 Cordis 拓展目录，生成 WebView 页面。
class CordisBundleLoader {
  CordisBundleLoader._();

  static const int maxMainBytes = 512 * 1024;
  static const int maxStyleBytes = 128 * 1024;

  /// [mainPath] 是 `ext.json` 里 main 的绝对路径（ExtensionItem.url）。
  /// 目录必须与 `ext.json` 同源，防止清单把入口指到别处。
  static Future<CordisPage> load(
    ExtensionItem item, {
    required String appVersion,
  }) async {
    if (item.url.startsWith('asset:')) {
      return _loadAsset(item, appVersion);
    }
    final mainFile = File(item.url);
    final dir = mainFile.parent;
    final manifestFile = File(p.join(dir.path, 'ext.json'));
    if (!manifestFile.existsSync()) {
      throw const FormatException('缺少 ext.json');
    }
    final manifest = CordisManifest.parse(jsonDecode(manifestFile.readAsStringSync()));
    final expectedMain = p.normalize(p.join(dir.path, manifest.main));
    if (p.normalize(mainFile.path) != expectedMain) {
      throw const FormatException('拓展入口与 ext.json 的 main 不一致，请重新导入');
    }
    final mainJs = _readBounded(mainFile, maxMainBytes, 'main.js');
    var css = '';
    if (manifest.style.isNotEmpty) {
      final styleFile = File(p.normalize(p.join(dir.path, manifest.style)));
      if (!p.isWithin(dir.path, styleFile.path)) {
        throw const FormatException('ext.json 的 style 不能指向目录外');
      }
      if (styleFile.existsSync()) {
        css = _readBounded(styleFile, maxStyleBytes, 'style.css');
      }
    }
    return CordisRuntime.buildPage(
      item: item,
      mainJs: mainJs,
      css: css,
      allowNetwork: item.fromMarket && item.permissions.contains('network'),
      appVersion: appVersion,
    );
  }

  /// 内置 Cordis 拓展直接读 Flutter asset（`asset:<main.js 的 key>`）。
  static Future<CordisPage> _loadAsset(
    ExtensionItem item,
    String appVersion,
  ) async {
    final mainKey = item.url.substring('asset:'.length);
    final dirKey = p.url.dirname(mainKey);
    final manifestKey = p.url.join(dirKey, 'ext.json');
    final manifestRaw = await rootBundle.loadString(manifestKey);
    final manifest = CordisManifest.parse(jsonDecode(manifestRaw));
    final expected = p.url.normalize(p.url.join(dirKey, manifest.main));
    if (p.url.normalize(mainKey) != expected) {
      throw const FormatException('内置拓展入口与 ext.json 的 main 不一致');
    }
    final mainJs = await rootBundle.loadString(mainKey);
    if (mainJs.length > maxMainBytes) {
      throw const FormatException('内置拓展 main.js 超过大小上限');
    }
    var css = '';
    if (manifest.style.isNotEmpty) {
      css = await rootBundle.loadString(p.url.join(dirKey, manifest.style));
      if (css.length > maxStyleBytes) {
        throw const FormatException('内置拓展 style.css 超过大小上限');
      }
    }
    return CordisRuntime.buildPage(
      item: item,
      mainJs: mainJs,
      css: css,
      // 内置拓展只走 antiSIT 通道，不需要页面自己联网。
      allowNetwork: false,
      appVersion: appVersion,
    );
  }

  static String _readBounded(File file, int maxBytes, String label) {
    final length = file.lengthSync();
    if (length > maxBytes) {
      throw FormatException('$label 太大（${(length / 1024).round()} KB，上限 ${maxBytes ~/ 1024} KB）');
    }
    return file.readAsStringSync();
  }
}
