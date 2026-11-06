import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../cordis_bundle.dart';
import '../extension_item.dart';
import '../extension_store.dart';

/// 拓展工坊的一个草稿。
class WorkshopDraft {
  const WorkshopDraft({required this.id, required this.dir, required this.manifest});

  final String id;
  final String dir;
  final CordisManifest manifest;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': manifest.name,
        'desc': manifest.desc,
        'version': manifest.version,
        'permissions': manifest.permissions,
      };
}

class WorkshopFile {
  const WorkshopFile({required this.path, required this.size});

  final String path;
  final int size;

  Map<String, Object?> toJson() => {'path': path, 'size': size};
}

/// 一次读取的结果：内容 + 内容哈希。
///
/// 哈希是「读后写」的版本凭据：Agent 写回时必须带上它，文件在这期间被别处
/// 改过就拒绝写入，避免 Agent 拿着旧内容整文件覆盖。
class WorkshopFileContent {
  const WorkshopFileContent({required this.content, required this.version});

  final String content;
  final String version;
}

/// 「拓展工坊」的草稿工作区：`<文档目录>/ext-workshop/<id>/`。
///
/// 工坊本身是一个内置 Cordis 拓展；它通过 [ExtBridge] 的 `workshop.*` 接口
/// 读写这些草稿，用户点安装后才复制进正式的拓展目录。
///
/// 文件读写带 sha256 版本：读返回版本，写已有文件必须带上它，避免 Agent
/// 拿旧内容整文件覆盖。会话日志放在草稿的 `.workshop/` 隐藏目录，不参与
/// 文件树和安装。
class WorkshopStore {
  WorkshopStore({Future<String> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? ExtensionStore.documentsDirectory;

  final Future<String> Function() _documentsDirectory;

  static const int maxTextBytes = 256 * 1024;
  static const int maxSessionBytes = 2 * 1024 * 1024;
  static const Set<String> allowedExtensions = {
    '.js',
    '.json',
    '.css',
    '.html',
    '.md',
    '.txt',
  };

  Future<String> rootDir() async => '${await _documentsDirectory()}/ext-workshop';

  Future<String> draftDir(String id) async {
    if (!CordisManifest.idPattern.hasMatch(id)) {
      throw const FormatException('草稿 id 不合法');
    }
    return '${await rootDir()}/$id';
  }

  Future<List<WorkshopDraft>> listDrafts() async {
    final root = Directory(await rootDir());
    if (!root.existsSync()) return const [];
    final out = <WorkshopDraft>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final draft = await _load(entity.path);
      if (draft != null) out.add(draft);
    }
    out.sort((a, b) => a.manifest.name.compareTo(b.manifest.name));
    return out;
  }

  Future<WorkshopDraft?> load(String id) async {
    final dir = await draftDir(id);
    return _load(dir);
  }

  Future<WorkshopDraft?> _load(String dir) async {
    final manifestFile = File(p.join(dir, 'ext.json'));
    if (!manifestFile.existsSync()) return null;
    try {
      final manifest =
          CordisManifest.parse(jsonDecode(manifestFile.readAsStringSync()));
      if (p.basename(dir) != manifest.id) {
        debugPrint('[ext-workshop] 草稿目录 $dir 与 ext.json 的 id 不一致，已跳过');
        return null;
      }
      return WorkshopDraft(id: manifest.id, dir: dir, manifest: manifest);
    } catch (e) {
      debugPrint('[ext-workshop] 草稿 $dir 的 ext.json 读不了，已跳过：$e');
      return null;
    }
  }

  Future<WorkshopDraft> create({String? id, String name = '未命名拓展'}) async {
    final draftId =
        id ?? 'sit.agent-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    if (!CordisManifest.idPattern.hasMatch(draftId)) {
      throw const FormatException('草稿 id 只能用小写字母 / 数字 / . _ -，3–64 位');
    }
    final dir = Directory(await draftDir(draftId));
    if (dir.existsSync()) throw const FormatException('同 id 的草稿已经存在');
    dir.createSync(recursive: true);
    final manifest = CordisManifest(
      id: draftId,
      name: name,
      version: '0.1.0',
      main: 'main.js',
      style: 'style.css',
    );
    File(p.join(dir.path, 'ext.json')).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n');
    File(p.join(dir.path, 'main.js')).writeAsStringSync(_templateMain(name));
    File(p.join(dir.path, 'style.css')).writeAsStringSync(_templateCss);
    return WorkshopDraft(id: draftId, dir: dir.path, manifest: manifest);
  }

  /// 会话日志放在草稿的 `.workshop/` 下；[listFiles] 会跳过隐藏目录，
  /// 所以它既不会出现在文件树里，也不会被安装进正式拓展。
  Future<File> _sessionFile(String draftId) async =>
      File(p.join(await draftDir(draftId), '.workshop', 'session.json'));

  Future<String?> loadSession(String draftId) async {
    final file = await _sessionFile(draftId);
    if (!file.existsSync()) return null;
    if (file.lengthSync() > maxSessionBytes) {
      throw FormatException(
          '会话日志太大（${(file.lengthSync() / 1024).round()} KB，上限 ${maxSessionBytes ~/ 1024} KB）');
    }
    return file.readAsStringSync();
  }

  Future<void> saveSession(String draftId, String data) async {
    final bytes = utf8.encode(data);
    if (bytes.length > maxSessionBytes) {
      throw FormatException(
          '会话日志太大（${(bytes.length / 1024).round()} KB，上限 ${maxSessionBytes ~/ 1024} KB）');
    }
    final file = await _sessionFile(draftId);
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsBytesSync(bytes, flush: true);
    try {
      temp.renameSync(file.path);
    } catch (_) {
      // 个别平台不允许 rename 覆盖已有文件：退回直接写，并清掉临时文件。
      file.writeAsBytesSync(bytes, flush: true);
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  Future<List<WorkshopFile>> listFiles(String draftId) async {
    final dir = Directory(await draftDir(draftId));
    if (!dir.existsSync()) return const [];
    final out = <WorkshopFile>[];
    void walk(Directory d, int depth) {
      if (depth > 3) return;
      for (final e in d.listSync(followLinks: false)) {
        if (e is Directory) {
          if (p.basename(e.path).startsWith('.')) continue;
          walk(e, depth + 1);
        } else if (e is File) {
          if (p.basename(e.path).startsWith('.')) continue;
          final rel = p.relative(e.path, from: dir.path).replaceAll('\\', '/');
          if (rel.startsWith('..')) continue;
          out.add(WorkshopFile(path: rel, size: e.lengthSync()));
        }
      }
    }

    walk(dir, 0);
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  Future<String> readFile(String draftId, String path) async =>
      (await readFileVersioned(draftId, path)).content;

  Future<WorkshopFileContent> readFileVersioned(String draftId, String path) async {
    final file = _file(await draftDir(draftId), path);
    if (!file.existsSync()) throw const FormatException('文件不存在');
    final length = file.lengthSync();
    if (length > maxTextBytes) {
      throw FormatException('文件太大（${(length / 1024).round()} KB，上限 ${maxTextBytes ~/ 1024} KB）');
    }
    final bytes = file.readAsBytesSync();
    return WorkshopFileContent(
      content: utf8.decode(bytes),
      version: sha256.convert(bytes).toString(),
    );
  }

  /// 写入前的版本门：已有文件必须带 [expectedVersion]，且内容没变。
  /// 单独暴露给桥接层，先校验再弹确认框，避免用户确认完才发现写入无效。
  Future<void> ensureWritable(String draftId, String path, String? expectedVersion) async {
    final file = _file(await draftDir(draftId), path);
    if (file.existsSync()) {
      if (expectedVersion == null || expectedVersion.isEmpty) {
        throw FormatException('覆盖已有文件前先读取：$path');
      }
      final current = sha256.convert(file.readAsBytesSync()).toString();
      if (current != expectedVersion) {
        throw FormatException('文件在上次读取后已变化，请重新读取：$path');
      }
    } else if (expectedVersion != null && expectedVersion.isNotEmpty) {
      throw FormatException('文件已不存在，请重新读取：$path');
    }
  }

  /// 写入完整文件，返回新内容的哈希。
  ///
  /// 已有文件必须先读（带 [expectedVersion]），否则拒绝覆盖；版本对不上说明
  /// 读完之后文件被改过，同样拒绝，让 Agent 重新读一遍再写。
  Future<String> writeFile(String draftId, String path, String content,
      {String? expectedVersion}) async {
    await ensureWritable(draftId, path, expectedVersion);
    final file = _file(await draftDir(draftId), path);
    final bytes = utf8.encode(content);
    if (bytes.length > maxTextBytes) {
      throw FormatException('内容太大（${(bytes.length / 1024).round()} KB，上限 ${maxTextBytes ~/ 1024} KB）');
    }
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return sha256.convert(bytes).toString();
  }

  Future<void> ensureDeletable(String draftId, String path, String? expectedVersion) async {
    if (path == 'ext.json' || path == 'main.js') {
      throw const FormatException('ext.json 与 main.js 是拓展入口，不能删除');
    }
    final file = _file(await draftDir(draftId), path);
    if (!file.existsSync()) return;
    if (expectedVersion == null || expectedVersion.isEmpty) {
      throw FormatException('删除前先读取文件：$path');
    }
    final current = sha256.convert(file.readAsBytesSync()).toString();
    if (current != expectedVersion) {
      throw FormatException('文件在上次读取后已变化，请重新读取：$path');
    }
  }

  Future<void> deleteFile(String draftId, String path,
      {String? expectedVersion}) async {
    await ensureDeletable(draftId, path, expectedVersion);
    final file = _file(await draftDir(draftId), path);
    if (file.existsSync()) file.deleteSync();
  }

  File _file(String dir, String rawPath) {
    final rel = _safeRelative(rawPath);
    if (rel == null) throw const FormatException('路径必须是草稿目录内的相对路径');
    if (rel.split('/').any((part) => part.startsWith('.'))) {
      throw const FormatException('不能访问草稿里的隐藏文件');
    }
    final ext = p.extension(rel).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw FormatException('只能编辑文本文件（${allowedExtensions.join(' / ')}）');
    }
    final file = File(p.normalize(p.join(dir, rel)));
    if (!p.isWithin(dir, file.path)) {
      throw const FormatException('路径越界');
    }
    return file;
  }

  static String? _safeRelative(String raw) {
    final s = raw.trim().replaceAll('\\', '/');
    if (s.isEmpty || s.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(s)) return null;
    final norm = p.posix.normalize(s);
    if (norm == '..' || norm.startsWith('../') || norm.startsWith('/')) return null;
    return norm;
  }

  /// 校验草稿：清单、入口、明显会在内置页里踩坑的写法。
  Future<List<String>> validate(String draftId) async {
    final draft = await load(draftId);
    if (draft == null) return const ['ext.json 不存在或解析失败'];
    final out = <String>[];
    final hasNetwork = draft.manifest.permissions.contains('network');
    void checkJs(String code, {required bool isMain}) {
      if (isMain && !RegExp(r'export\s+default').hasMatch(code)) {
        out.add('main.js 需要 `export default` 一个 Cordis 插件');
      }
      if (RegExp(r'\blocalStorage\b|\bsessionStorage\b|document\.cookie')
          .hasMatch(code)) {
        out.add('不要用 localStorage / sessionStorage / document.cookie：内联页是 opaque origin，读它会抛错；请用 ctx.storage');
      }
      if (!hasNetwork && RegExp(r'\bfetch\s*\(|XMLHttpRequest').hasMatch(code)) {
        out.add('代码里用了网络请求，但 ext.json 没声明 network 权限（市场包会被 CSP 拦掉）');
      }
      if (RegExp(r"""<script[^>]+src\s*=\s*["']https?://""", caseSensitive: false)
          .hasMatch(code)) {
        out.add('不要引外部脚本：审核过的代码必须就是手机上跑的那份');
      }
    }

    final mainFile = File(p.normalize(p.join(draft.dir, draft.manifest.main)));
    if (!mainFile.existsSync()) {
      out.add('main.js 不存在：${draft.manifest.main}');
    } else {
      checkJs(mainFile.readAsStringSync(), isMain: true);
    }
    for (final f in await listFiles(draftId)) {
      if (!f.path.toLowerCase().endsWith('.js') || f.path == draft.manifest.main) {
        continue;
      }
      checkJs(await readFile(draftId, f.path), isMain: false);
    }
    if (draft.manifest.style.isNotEmpty) {
      final style = File(p.normalize(p.join(draft.dir, draft.manifest.style)));
      if (!style.existsSync()) out.add('style 文件不存在：${draft.manifest.style}');
    }
    return out;
  }

  /// 草稿对应的临时 ExtensionItem（预览用）。
  ExtensionItem itemOf(WorkshopDraft draft) => ExtensionItem(
        id: draft.id,
        name: draft.manifest.name,
        url: p.normalize(p.join(draft.dir, draft.manifest.main)),
        desc: draft.manifest.desc,
        bundled: true,
        runtime: ExtensionItem.runtimeCordis,
        version: draft.manifest.version,
        permissions: draft.manifest.permissions,
        minAppVersion: draft.manifest.minAppVersion,
      );

  /// 把草稿装进正式拓展清单。
  Future<ExtensionItem> install(String draftId) async {
    final draft = await load(draftId);
    if (draft == null) throw const FormatException('草稿不存在或 ext.json 已损坏');
    final problems = await validate(draftId);
    if (problems.isNotEmpty) throw FormatException(problems.join('\n'));
    final store = ExtensionStore.I;
    if (store.isBuiltin(draft.id)) {
      throw const FormatException('这是内置拓展的 id，换一个 id 再安装');
    }
    final target = await store.bundleDir(draft.id);
    final targetDir = Directory(target);
    if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
    targetDir.createSync(recursive: true);
    for (final f in await listFiles(draftId)) {
      final source = File(p.join(draft.dir, f.path));
      final dest = File(p.join(target, f.path));
      dest.parent.createSync(recursive: true);
      source.copySync(dest.path);
    }
    final existingList = store.items.where((e) => e.id == draft.id).toList();
    final existing = existingList.isEmpty ? null : existingList.first;
    final url = p.normalize(p.join(target, draft.manifest.main));
    final item = existing == null
        ? ExtensionItem(
            id: draft.id,
            name: draft.manifest.name,
            url: url,
            desc: draft.manifest.desc,
            bundled: true,
            runtime: ExtensionItem.runtimeCordis,
            version: draft.manifest.version,
            permissions: draft.manifest.permissions,
            minAppVersion: draft.manifest.minAppVersion,
          )
        : existing.copyWith(
            url: url,
            bundled: true,
            runtime: ExtensionItem.runtimeCordis,
            version: draft.manifest.version,
            permissions: draft.manifest.permissions,
            minAppVersion: draft.manifest.minAppVersion,
          );
    if (existing == null) {
      await store.add(item);
    } else {
      await store.update(item);
    }
    return item;
  }

  static String _templateMain(String name) => '''
// Cordis 拓展入口。保存后点右上角「预览」即可在 App 里运行。
export default {
  name: 'agent-extension',
  inject: ['ui'],
  apply(ctx) {
    ctx.ui.root.innerHTML = `
      <main class="wrap">
        <h1>${_jsString(name)}</h1>
        <p>这是拓展工坊生成的 Cordis 拓展。</p>
        <button id="hello">点我</button>
      </main>`;
    const button = ctx.ui.root.querySelector('#hello');
    button.addEventListener('click', () => ctx.ui.toast('你好'));
  },
};
''';

  static String _jsString(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');

  static const String _templateCss = '''
.wrap { padding: 20px; font-family: system-ui, sans-serif; }
h1 { font-size: 20px; margin: 0 0 8px; }
button { padding: 8px 14px; border-radius: 10px; border: 1px solid var(--antisit-border, #ddd); }
''';
}
