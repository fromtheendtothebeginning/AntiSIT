/// 拓展的文件读写：只碰用户通过**系统文件选择器**明确选中的文件。
///
/// * `pick` —— 打开系统文件选择器，把选中文件的内容（文本 / base64）交给拓展；
/// * `save` —— 打开系统「保存到」选择器，把拓展给的内容写进用户选的位置。
///
/// 刻意不做「按任意路径读写」：那需要 MANAGE_EXTERNAL_STORAGE 之类的宽权限，
/// 也会让市场拓展拿到 App 沙盒之外的入口。系统选择器本身就是用户的一次明确授权，
/// 每次读写都由用户挑文件 / 挑位置，拓展拿不到路径，只拿到内容。
///
/// 大小上限：单文件 8 MB、一次最多 10 个、合计 16 MB。超过就报错，不做截断——
/// 截断过的文件交回拓展只会留下难查的损坏数据。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class ExtFilesException implements Exception {
  const ExtFilesException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ExtFilesService {
  ExtFilesService._();

  static final ExtFilesService I = ExtFilesService._();

  /// 单个文件上限：base64 后约 10.7 MB，WebView 通道能扛住，也不至于把手机内存吃满。
  static const int maxFileBytes = 8 * 1024 * 1024;

  /// 一次最多带回几个文件。
  static const int maxFiles = 10;

  /// 一次调用合计上限（防止选 10 个 8 MB 的文件）。
  static const int maxTotalBytes = 16 * 1024 * 1024;

  /// Android 侧用 ACTION_CREATE_DOCUMENT 保存（见 `ExtFilesBridge.kt`）。
  static const MethodChannel _channel = MethodChannel('antisit/ext_files');

  /// `files.pick({accept?, multiple?, encoding?})`。
  ///
  /// 返回 `{files: [{name, size, mime, text? | base64?}]}`；用户取消时 `files` 为空。
  Future<Map<String, Object?>> pick(Object? args) async {
    final a = args is Map
        ? args
        : args is String
            ? <String, Object?>{'accept': args}
            : const <String, Object?>{};
    final multiple = a['multiple'] == true;
    final encoding = '${a['encoding'] ?? 'text'}'.trim().toLowerCase();
    if (encoding != 'text' && encoding != 'base64') {
      throw const ExtFilesException('encoding 只能是 text 或 base64');
    }
    final groups = typeGroupsFromAccept(a['accept']);

    List<XFile> files;
    try {
      if (multiple) {
        files = await openFiles(acceptedTypeGroups: groups);
      } else {
        final file = await openFile(acceptedTypeGroups: groups);
        files = file == null ? const [] : [file];
      }
    } on PlatformException catch (e) {
      throw ExtFilesException(e.message ?? '打开文件选择器失败');
    } on MissingPluginException {
      throw const ExtFilesException('当前平台不支持文件选择器');
    }

    if (files.length > maxFiles) {
      throw ExtFilesException('一次最多选 $maxFiles 个文件');
    }
    var total = 0;
    final out = <Map<String, Object?>>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.length > maxFileBytes) {
        throw ExtFilesException(
            '「${file.name}」太大（${_sizeText(bytes.length)}，上限 ${_sizeText(maxFileBytes)}）');
      }
      total += bytes.length;
      if (total > maxTotalBytes) {
        throw ExtFilesException('选中的文件合计太大（上限 ${_sizeText(maxTotalBytes)}）');
      }
      out.add({
        'name': file.name,
        'size': bytes.length,
        'mime': _mimeOf(file),
        if (encoding == 'text')
          'text': utf8.decode(bytes, allowMalformed: true)
        else
          'base64': base64Encode(bytes),
      });
    }
    return {'files': out};
  }

  /// `files.save({name, text? | base64?, mime?})`。
  ///
  /// 用户在系统「保存到」里选好位置并确认后返回 true；取消返回 false。
  Future<bool> save(Object? args) async {
    if (args is! Map) throw const ExtFilesException('files.save 要带 {name, text|base64}');
    var name = _safeFileName('${args['name'] ?? ''}');
    if (name.isEmpty) name = '文件.txt';
    final text = args['text'];
    final base64Text = args['base64'];
    final Uint8List bytes;
    if (base64Text is String && base64Text.trim().isNotEmpty) {
      try {
        bytes = base64Decode(base64Text.trim());
      } catch (_) {
        throw const ExtFilesException('base64 不是合法内容');
      }
    } else if (text != null) {
      bytes = Uint8List.fromList(utf8.encode('$text'));
    } else {
      throw const ExtFilesException('files.save 要带 text 或 base64');
    }
    if (bytes.length > maxFileBytes) {
      throw ExtFilesException('文件太大（${_sizeText(bytes.length)}，上限 ${_sizeText(maxFileBytes)}）');
    }
    final mimeRaw = '${args['mime'] ?? ''}'.trim();
    final mime = mimeRaw.contains('/') ? mimeRaw : _mimeForName(name);

    if (Platform.isAndroid) {
      final saved = await _channel.invokeMethod<bool>('save', {
        'name': name,
        'mime': mime,
        'bytes': bytes,
      });
      return saved == true;
    }
    // 桌面端（Windows / macOS / Linux）file_selector 自带保存对话框；
    // iOS 目前没有实现，调用会抛 UnimplementedError，给一句人话。
    try {
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          XTypeGroup(label: '文件', extensions: [_extensionOf(name)]),
        ],
      );
      if (location == null) return false;
      await XFile.fromData(bytes, mimeType: mime, name: name).saveTo(location.path);
      return true;
    } on UnimplementedError {
      throw const ExtFilesException('保存文件目前只支持 Android / 桌面端');
    } on PlatformException catch (e) {
      throw ExtFilesException(e.message ?? '保存文件失败');
    }
  }

  /// `accept` 支持字符串或数组：`.csv` / `csv` 当扩展名，`text/csv` / `image/*` 当 MIME。
  /// 不传 = 任意文件。
  static List<XTypeGroup> typeGroupsFromAccept(Object? raw) {
    final items = <String>[];
    if (raw is String) {
      items.addAll(raw.split(','));
    } else if (raw is List) {
      for (final item in raw) {
        items.addAll('$item'.split(','));
      }
    }
    final extensions = <String>{};
    final mimeTypes = <String>{};
    for (final item in items) {
      var value = item.trim().toLowerCase();
      if (value.isEmpty) continue;
      if (value.startsWith('.')) value = value.substring(1);
      if (value.contains('/')) {
        mimeTypes.add(value);
      } else if (RegExp(r'^[a-z0-9+_-]+$').hasMatch(value)) {
        extensions.add(value);
      }
    }
    if (extensions.isEmpty && mimeTypes.isEmpty) return const [];
    return [
      XTypeGroup(
        label: '文件',
        extensions: extensions.isEmpty ? null : extensions.toList(),
        mimeTypes: mimeTypes.isEmpty ? null : mimeTypes.toList(),
      ),
    ];
  }

  /// 保存时的文件名：去掉路径分隔符与控制字符，避免把清单/路径写穿。
  /// 空串由调用方补默认名。
  static String _safeFileName(String raw) {
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    if (name.length > 120) {
      final ext = p.extension(name);
      final base = name.substring(0, name.length - ext.length);
      name = '${base.substring(0, (120 - ext.length).clamp(0, base.length))}$ext';
    }
    return name;
  }

  static String _mimeOf(XFile file) {
    final declared = file.mimeType?.trim() ?? '';
    if (declared.contains('/')) return declared;
    return _mimeForName(file.name);
  }

  /// 只认常见的几类；认不出来按二进制处理（base64 照样能读）。
  static String _mimeForName(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.txt':
      case '.md':
      case '.log':
      case '.ini':
      case '.cfg':
      case '.conf':
        return 'text/plain';
      case '.json':
        return 'application/json';
      case '.csv':
        return 'text/csv';
      case '.html':
      case '.htm':
        return 'text/html';
      case '.xml':
        return 'text/xml';
      case '.js':
        return 'text/javascript';
      case '.css':
        return 'text/css';
      case '.pdf':
        return 'application/pdf';
      case '.zip':
        return 'application/zip';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';
      case '.mp3':
        return 'audio/mpeg';
      case '.mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  static String _extensionOf(String name) {
    final ext = p.extension(name);
    return ext.isEmpty ? 'txt' : ext.substring(1).toLowerCase();
  }

  static String _sizeText(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}
