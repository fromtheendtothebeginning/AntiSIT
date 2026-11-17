import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../workshop/workshop_store.dart';
import 'publish_models.dart';
import 'publish_repository.dart';
import 'publish_settings.dart';

typedef PublishRepositoryFactory = PublishRepository Function(
    PublishConfig config, String token);

/// 把工坊草稿发布成一份「第三方市场源」：
/// 仓库里维护 `ext/<id>/`、`dist/<id>/<版本>.zip`、`market.json` 与签名。
///
/// 目录用本机生成的 Ed25519 私钥签名、并内嵌公钥；别人在 App 里添加这个源时
/// 会看到公钥指纹，之后刷新都用固定的公钥验签。私钥只在本机加密存储，绝不上传。
class PublishService {
  PublishService({WorkshopStore? workshop, PublishRepositoryFactory? repositoryFactory})
      : workshop = workshop ?? WorkshopStore(),
        _repositoryFactory = repositoryFactory ?? defaultPublishRepository;

  final WorkshopStore workshop;
  final PublishRepositoryFactory _repositoryFactory;

  /// 与市场工具 `kMaxZipBytes` 一致。
  static const int maxBundleBytes = 2 * 1024 * 1024;

  Future<PublishResult> publish({
    required WorkshopDraft draft,
    required PublishConfig config,
    required String token,
    required Future<bool> Function() confirmCreateRepo,
    void Function(String step)? onStep,
  }) async {
    onStep?.call('检查拓展…');
    final problems = await workshop.validate(draft.id);
    if (problems.isNotEmpty) {
      throw FormatException('拓展还没通过自检：\n${problems.join('\n')}');
    }

    onStep?.call('打包拓展…');
    final sources = <String, List<int>>{};
    for (final f in await workshop.listFiles(draft.id)) {
      sources[f.path] = utf8.encode(await workshop.readFile(draft.id, f.path));
    }
    final zip = _zip(sources);
    if (zip.length > maxBundleBytes) {
      throw StateError('拓展包 ${(zip.length / 1024).toStringAsFixed(0)} KB，'
          '超过 ${maxBundleBytes ~/ 1024} KB 上限');
    }
    final sha = sha256.convert(zip).toString();

    onStep?.call('连接 ${config.provider.label}…');
    final repo = _repositoryFactory(config, token);
    var info = await repo.repo();
    if (info == null) {
      final ok = await confirmCreateRepo();
      if (!ok) throw StateError('仓库不存在，已取消发布');
      onStep?.call('新建仓库…');
      info = await repo.create();
    }
    if (info.private) {
      throw StateError('仓库是私有的：别人拿不到目录和拓展包，请改成公开仓库');
    }
    final branch = config.branch.trim().isEmpty ? info.defaultBranch : config.branch.trim();
    if (branch.isEmpty) throw StateError('这个仓库没有默认分支，请在高级设置里填一个');

    onStep?.call('生成目录与签名…');
    final key = await PublishSettings.ensureKey();
    final manifest = draft.manifest;
    final version = manifest.version.trim().isEmpty ? '0.1.0' : manifest.version.trim();
    final zipRel = 'dist/${manifest.id}/$version.zip';
    final entry = await _catalogEntry(
      draft: draft,
      owner: config.owner,
      version: version,
      zipRel: zipRel,
      sha: sha,
      size: zip.length,
    );
    final existing = await _existingEntries(repo, branch, key);
    final entries = <Map<String, Object?>>[
      for (final e in existing)
        if ('${e['id'] ?? ''}'.trim() != manifest.id) e,
      entry,
    ]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final catalog = _catalogJson(key: key, entries: entries);
    final signature = await _sign(catalog, key);

    onStep?.call('上传文件…');
    final message = '发布 ${manifest.id} v$version';
    for (final file in sources.entries) {
      await repo.putFile('ext/${manifest.id}/${file.key}', file.value,
          branch: branch, message: message);
    }
    await repo.putFile(zipRel, zip, branch: branch, message: message);
    // 先传包、再传目录、最后传签名：别人任何时刻拉到的都是「验签通过且产物齐全」的版本
    await repo.putFile('market.json', utf8.encode(catalog),
        branch: branch, message: message);
    await repo.putFile('market.json.sig', utf8.encode('$signature\n'),
        branch: branch, message: message);

    final zipUrl = '${config.zipBase(branch)}$zipRel';
    onStep?.call('完成');
    return PublishResult(
      provider: config.provider,
      owner: config.owner,
      repo: config.repo,
      branch: branch,
      sourceInput: config.sourceInput(branch),
      fingerprint: publishKeyFingerprint(key.publicKey),
      installCode: jsonEncode({
        'antisit': 'ext',
        'url': zipUrl,
        'sha256': sha,
        'id': manifest.id,
        'name': manifest.name,
        'version': version,
      }),
      zipUrl: zipUrl,
      id: manifest.id,
      name: manifest.name,
      version: version,
    );
  }

  /// 目录里的一条：字段与 AntiSIT-market 的 `CatalogEntry` 对齐。
  /// 作者 / 分类优先取 `ext.json` 里作者自己写的，没有就用仓库所有者 / 其他。
  Future<Map<String, Object?>> _catalogEntry({
    required WorkshopDraft draft,
    required String owner,
    required String version,
    required String zipRel,
    required String sha,
    required int size,
  }) async {
    Map<String, Object?> ext = const {};
    try {
      final raw = jsonDecode(await workshop.readFile(draft.id, 'ext.json'));
      if (raw is Map) ext = Map<String, Object?>.from(raw);
    } catch (_) {}
    final m = draft.manifest;
    String s(String key) => '${ext[key] ?? ''}'.trim();
    final author = s('author').isEmpty ? owner : s('author');
    final category = s('category').isEmpty ? '其他' : s('category');
    final icon = s('icon');
    return {
      'id': m.id,
      'name': m.name,
      'desc': m.desc,
      'author': author,
      'category': category,
      if (icon.isNotEmpty) 'icon': icon,
      'type': 'bundle',
      'runtime': 'cordis',
      'version': version,
      'zip': zipRel,
      'sha256': sha,
      'size': size,
      'permissions': m.permissions,
      if (m.minAppVersion.isNotEmpty) 'minAppVersion': m.minAppVersion,
    };
  }

  /// 仓库里已有的目录条目（同一个仓库可以放多条拓展）。
  /// 目录来自**另一把密钥**或没有内嵌公钥时直接停：不能把别人的源接管过来。
  Future<List<Map<String, Object?>>> _existingEntries(
    PublishRepository repo,
    String branch,
    PublishKey key,
  ) async {
    final file = await repo.file('market.json', branch: branch);
    if (file == null) return const [];
    if (file.bytes == null) {
      throw StateError('仓库里的 market.json 读取失败（文件太大？），为免覆盖已停止');
    }
    final catalogText = utf8.decode(file.bytes!);
    final Object? raw;
    try {
      raw = jsonDecode(catalogText);
    } catch (e) {
      throw StateError('仓库里的 market.json 解析失败，为免覆盖已停止：$e');
    }
    if (raw is! Map) throw StateError('仓库里的 market.json 不是对象，为免覆盖已停止');
    if (raw['schema'] != 1) {
      throw StateError('仓库里的目录 schema 不认识（${raw['schema']}），为免覆盖已停止');
    }
    final declared = '${raw['publicKey'] ?? ''}'.trim();
    if (declared.isEmpty) {
      throw StateError('仓库里已有一份不带公钥的目录（可能是官方目录），换一个仓库发布');
    }
    if (declared != key.publicKey) {
      throw StateError('仓库里的目录是另一把发布密钥签的；换一个仓库，或先清空市场文件');
    }
    final sigFile = await repo.file('market.json.sig', branch: branch);
    if (sigFile?.bytes == null) {
      throw StateError('仓库里的目录缺签名（market.json.sig），为免覆盖已停止');
    }
    final valid = await _verify(
      catalogText,
      signature: utf8.decode(sigFile!.bytes!).trim(),
      publicKey: key.publicKey,
    );
    if (!valid) {
      throw StateError('仓库里的目录签名校验不过（内容被改过？），为免覆盖已停止');
    }
    final list = raw['extensions'];
    if (list is! List) throw StateError('仓库里的目录没有 extensions 数组');
    return [
      for (final e in list)
        if (e is Map) Map<String, Object?>.from(e),
    ];
  }

  static List<int> _zip(Map<String, List<int>> sources) {
    final names = sources.keys.where((n) => !_skipInZip(n)).toList()..sort();
    final archive = Archive();
    for (final name in names) {
      archive.addFile(ArchiveFile.bytes(name, sources[name]!));
    }
    // 固定时间戳 + 固定压缩级别：内容不变时 sha256 不变，避免「同一版算更新」
    return ZipEncoder().encodeBytes(
      archive,
      level: DeflateLevel.defaultCompression,
      modified: DateTime.utc(2020, 1, 1),
    );
  }

  /// 与市场工具 `skipInZip` 一致：说明文件 / 版本控制文件 / `_` 开头的目录不进包，
  /// 但源码仍然会上传到 `ext/<id>/` 让仓库可读。
  static bool _skipInZip(String relative) {
    for (final seg in relative.split('/')) {
      if (seg.startsWith('_')) return true;
    }
    final base = relative.split('/').last;
    return base == 'README.md' ||
        base == '.gitignore' ||
        base == '.DS_Store' ||
        base == 'Thumbs.db';
  }

  static String _catalogJson({
    required PublishKey key,
    required List<Map<String, Object?>> entries,
  }) {
    final map = <String, Object?>{
      'schema': 1,
      'keyId': key.keyId,
      'publicKey': key.publicKey,
      'extensions': entries,
    };
    return '${const JsonEncoder.withIndent('  ').convert(map)}\n';
  }

  static Future<String> _sign(String catalog, PublishKey key) async {
    final pair = SimpleKeyPairData(
      base64Decode(key.privateKey),
      publicKey: SimplePublicKey(base64Decode(key.publicKey), type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final sig = await Ed25519().sign(utf8.encode(catalog), keyPair: pair);
    return base64Encode(sig.bytes);
  }

  static Future<bool> _verify(
    String catalog, {
    required String signature,
    required String publicKey,
  }) async {
    try {
      final sig = base64Decode(signature);
      final pub = base64Decode(publicKey);
      if (sig.length != 64 || pub.length != 32) return false;
      return await Ed25519().verify(
        utf8.encode(catalog),
        signature: Signature(sig,
            publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
      );
    } catch (_) {
      return false;
    }
  }
}
