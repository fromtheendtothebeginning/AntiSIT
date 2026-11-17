import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late WorkshopStore workshop;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStore.I = MemorySecureStore();
    dir = Directory.systemTemp.createTempSync('publish_test_');
    workshop = WorkshopStore(documentsDirectory: () async => dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    SecureStore.I = MemorySecureStore();
  });

  Future<WorkshopDraft> makeDraft() async {
    final created = await workshop.create(id: 'sit.demo', name: '演示');
    File('${created.dir}/ext.json').writeAsStringSync(jsonEncode({
      'id': 'sit.demo',
      'name': '演示拓展',
      'desc': '一句话',
      'version': '1.0.0',
      'main': 'main.js',
      'permissions': ['storage'],
    }));
    File('${created.dir}/main.js').writeAsStringSync(
        'export default { apply(ctx) { ctx.ui.root.textContent = "hi" } }');
    return (await workshop.load('sit.demo'))!;
  }

  const config = PublishConfig(
    provider: PublishProvider.github,
    owner: 'me',
    repo: 'antisit-ext',
  );

  test('仓库输入：owner/repo 与仓库网址都能解析，平台要对得上', () {
    expect(PublishConfig.parse(provider: PublishProvider.github, input: 'me/repo').repo,
        'repo');
    final fromUrl = PublishConfig.parse(
        provider: PublishProvider.github,
        input: 'https://github.com/me/repo.git/');
    expect(fromUrl.owner, 'me');
    expect(fromUrl.repo, 'repo');
    expect(
        PublishConfig.parse(
                provider: PublishProvider.gitee,
                input: 'https://gitee.com/me/repo')
            .provider,
        PublishProvider.gitee);
    expect(
        () => PublishConfig.parse(
            provider: PublishProvider.github, input: 'https://gitee.com/me/repo'),
        throwsFormatException);
    expect(
        () => PublishConfig.parse(provider: PublishProvider.github, input: 'me'),
        throwsFormatException);
  });

  test('发布：打包 → 目录 → 签名 → 上传；二维码信息可直装', () async {
    final draft = await makeDraft();
    final repo = _FakeRepo();
    final service = PublishService(
      workshop: workshop,
      repositoryFactory: (_, __) => repo,
    );
    final result = await service.publish(
      draft: draft,
      config: config,
      token: 't',
      confirmCreateRepo: () async => true,
    );

    expect(repo.files.keys,
        containsAll(['ext/sit.demo/ext.json', 'ext/sit.demo/main.js']));
    final zipPath = 'dist/sit.demo/1.0.0.zip';
    final zipBytes = repo.files[zipPath]!;
    expect(zipBytes.length, lessThan(PublishService.maxBundleBytes));
    final zip = ZipDecoder().decodeBytes(zipBytes);
    expect(zip.files.map((f) => f.name),
        containsAll(['ext.json', 'main.js', 'style.css']));
    final sha = crypto.sha256.convert(zipBytes).toString();

    final catalogBytes = repo.files['market.json']!;
    final catalog = jsonDecode(utf8.decode(catalogBytes)) as Map;
    expect(catalog['schema'], 1);
    expect(catalog['keyId'], 'author');
    expect(catalog['publicKey'], isNotEmpty);
    final entry = (catalog['extensions'] as List).single as Map;
    expect(entry['id'], 'sit.demo');
    expect(entry['type'], 'bundle');
    expect(entry['runtime'], 'cordis');
    expect(entry['version'], '1.0.0');
    expect(entry['zip'], zipPath);
    expect(entry['sha256'], sha);
    expect(entry['permissions'], ['storage']);

    // 目录签名必须能验过（别人添加源时会做同一件事）
    final sig = base64Decode(utf8.decode(repo.files['market.json.sig']!).trim());
    final pub = base64Decode(catalog['publicKey'] as String);
    expect(
      await Ed25519().verify(
        catalogBytes,
        signature: Signature(sig,
            publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
      ),
      isTrue,
    );

    final code = jsonDecode(result.installCode) as Map;
    expect(code['url'], contains('cdn.jsdelivr.net/gh/me/antisit-ext@'));
    expect(code['url'], endsWith(zipPath));
    expect(code['sha256'], sha);
    expect(code['id'], 'sit.demo');
    expect(result.sourceInput, 'me/antisit-ext');
    expect(result.fingerprint, publishKeyFingerprint(catalog['publicKey'] as String));
  });

  test('发布结果能被 App 的「添加第三方源」直接识别', () async {
    final draft = await makeDraft();
    final repo = _FakeRepo();
    final result = await PublishService(
      workshop: workshop,
      repositoryFactory: (_, __) => repo,
    ).publish(
      draft: draft,
      config: config,
      token: 't',
      confirmCreateRepo: () async => true,
    );

    final saved = ExtSourceStore.fetcher;
    addTearDown(() => ExtSourceStore.fetcher = saved);
    ExtSourceStore.fetcher = (url) async {
      final bytes = repo.files[url.pathSegments.last];
      if (bytes == null) throw StateError('404 ${url.path}');
      return bytes;
    };

    final preview = await ExtSourceStore().preview('me/antisit-ext');
    expect(preview.entries.single.id, 'sit.demo');
    expect(preview.entries.single.name, '演示拓展');
    expect(preview.entries.single.zip, 'dist/sit.demo/1.0.0.zip');
    expect(preview.draft.fingerprint, result.fingerprint,
        reason: '作者看到的指纹与用户添加源时核对的是同一串');
  });

  test('同一仓库多条拓展：合并已有目录，不丢别的条目', () async {
    final key = await PublishSettings.ensureKey();
    final repo = _FakeRepo();
    final existing = jsonEncode({
      'schema': 1,
      'keyId': 'author',
      'publicKey': key.publicKey,
      'extensions': [
        {
          'id': 'sit.other',
          'name': '别人的条目',
          'desc': '已有',
          'author': 'me',
          'category': '工具',
          'type': 'bundle',
          'runtime': 'cordis',
          'version': '2.0.0',
          'zip': 'dist/sit.other/2.0.0.zip',
          'sha256': 'b' * 64,
          'permissions': <String>[],
        }
      ],
    });
    final pair = SimpleKeyPairData(
      base64Decode(key.privateKey),
      publicKey: SimplePublicKey(base64Decode(key.publicKey), type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final sig = await Ed25519().sign(utf8.encode(existing), keyPair: pair);
    repo.files['market.json'] = utf8.encode(existing);
    repo.files['market.json.sig'] = utf8.encode('${base64Encode(sig.bytes)}\n');

    final draft = await makeDraft();
    await PublishService(workshop: workshop, repositoryFactory: (_, __) => repo)
        .publish(
      draft: draft,
      config: config,
      token: 't',
      confirmCreateRepo: () async => true,
    );

    final catalog =
        jsonDecode(utf8.decode(repo.files['market.json']!)) as Map;
    final ids = [for (final e in catalog['extensions'] as List) (e as Map)['id']];
    expect(ids, ['sit.demo', 'sit.other'], reason: '按 id 排序且旧的条目还在');
  });

  test('仓库里的目录是另一把密钥签的：拒绝覆盖', () async {
    final repo = _FakeRepo();
    repo.files['market.json'] = utf8.encode(jsonEncode({
      'schema': 1,
      'keyId': 'other',
      'publicKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'extensions': <Object>[],
    }));
    final draft = await makeDraft();
    await expectLater(
      PublishService(workshop: workshop, repositoryFactory: (_, __) => repo)
          .publish(
        draft: draft,
        config: config,
        token: 't',
        confirmCreateRepo: () async => true,
      ),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('另一把发布密钥'))),
    );
  });

  test('私有仓库 / 用户取消新建仓库：都在上传前停下', () async {
    final draft = await makeDraft();
    final privateRepo = _FakeRepo(private: true);
    await expectLater(
      PublishService(workshop: workshop, repositoryFactory: (_, __) => privateRepo)
          .publish(
        draft: draft,
        config: config,
        token: 't',
        confirmCreateRepo: () async => true,
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('私有'))),
    );

    final missing = _FakeRepo(exists: false);
    await expectLater(
      PublishService(workshop: workshop, repositoryFactory: (_, __) => missing)
          .publish(
        draft: draft,
        config: config,
        token: 't',
        confirmCreateRepo: () async => false,
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('取消'))),
    );
    expect(missing.created, isFalse);
  });

  test('仓库不存在但用户同意：先新建再发布', () async {
    final draft = await makeDraft();
    final repo = _FakeRepo(exists: false);
    await PublishService(workshop: workshop, repositoryFactory: (_, __) => repo)
        .publish(
      draft: draft,
      config: config,
      token: 't',
      confirmCreateRepo: () async => true,
    );
    expect(repo.created, isTrue);
    expect(repo.files.keys, contains('market.json'));
  });

  testWidgets('发布页：填表 → 发布 → 展示直装二维码与源地址', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final draft = await makeDraft();
    final repo = _FakeRepo();
    final service = PublishService(
      workshop: workshop,
      repositoryFactory: (_, __) => repo,
    );
    await tester.pumpWidget(MaterialApp(
      home: PublishPage(draft: draft, service: service),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'tok');
    await tester.enterText(find.byType(TextField).at(1), 'me/antisit-ext');
    await tester.tap(find.text('发布到 GitHub'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已发布「演示拓展」'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => '${w.runtimeType}' == 'QrImageView'),
        findsOneWidget);
    expect(find.text('me/antisit-ext'), findsWidgets,
        reason: '结果卡片里展示源地址（输入框也留着同一串）');
    expect(repo.files, contains('market.json'));
  });

  group('GitHub API 映射', () {
    test('新建文件用 PUT、带 branch；更新带旧 sha；内容没变不写', () async {
      final calls = <String>[];
      final requests = <http.Request>[];
      var exist = false;
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        requests.add(req);
        if (req.url.path == '/repos/me/ext' && req.method == 'GET') {
          return http.Response(jsonEncode({'default_branch': 'main', 'private': false}), 200);
        }
        if (req.method == 'GET' && req.url.path.contains('/contents/market.json')) {
          if (!exist) return http.Response('{}', 404);
          final body = base64Encode(utf8.encode('hello'));
          return http.Response(
              jsonEncode({'sha': 'blob-1', 'content': body}), 200);
        }
        if (req.method == 'PUT' && req.url.path.contains('/contents/')) {
          exist = true;
          return http.Response('{}', 201);
        }
        return http.Response('{}', 404);
      });
      final repo = GitHubPublishRepository(
          owner: 'me', repo: 'ext', token: 'tok', client: client);

      await repo.putFile('market.json', utf8.encode('hello'),
          branch: 'main', message: 'm');
      final put = requests.last;
      expect(put.method, 'PUT');
      expect(put.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(put.body)['branch'], 'main');
      expect(jsonDecode(put.body)['content'],
          base64Encode(utf8.encode('hello')));
      expect(jsonDecode(put.body).containsKey('sha'), isFalse);

      // 同内容：不产生写请求
      await repo.putFile('market.json', utf8.encode('hello'),
          branch: 'main', message: 'm');
      expect(requests.where((r) => r.method == 'PUT'), hasLength(1));

      // 改内容：PUT 带旧 sha
      await repo.putFile('market.json', utf8.encode('hello2'),
          branch: 'main', message: 'm');
      final second = requests.where((r) => r.method == 'PUT').last;
      expect(jsonDecode(second.body)['sha'], 'blob-1');
    });
  });

  group('Gitee API 映射', () {
    test('token 走参数；新建用 POST，更新用 PUT 并带旧 sha', () async {
      final requests = <http.Request>[];
      var exist = false;
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/api/v5/repos/me/ext' && req.method == 'GET') {
          return http.Response(
              jsonEncode({'default_branch': 'master', 'private': false}), 200);
        }
        if (req.method == 'GET' && req.url.path.contains('/contents/')) {
          if (!exist) return http.Response('{}', 404);
          return http.Response(
              jsonEncode({
                'sha': 'gitee-blob',
                'content': base64Encode(utf8.encode('hello')),
              }),
              200);
        }
        if ((req.method == 'POST' || req.method == 'PUT') &&
            req.url.path.contains('/contents/')) {
          exist = true;
          return http.Response('{}', 200);
        }
        return http.Response('{}', 404);
      });
      final repo = GiteePublishRepository(
          owner: 'me', repo: 'ext', token: 'tok', client: client);

      await repo.putFile('market.json', utf8.encode('hello'),
          branch: 'master', message: 'm');
      final post = requests.last;
      expect(post.method, 'POST');
      expect(post.url.queryParameters['access_token'], 'tok');
      final body = jsonDecode(post.body) as Map;
      expect(body['access_token'], 'tok');
      expect(body['branch'], 'master');
      expect(body.containsKey('sha'), isFalse);

      await repo.putFile('market.json', utf8.encode('hello2'),
          branch: 'master', message: 'm');
      final put = requests.last;
      expect(put.method, 'PUT');
      expect(jsonDecode(put.body)['sha'], 'gitee-blob');
    });
  });
}

/// 内存里的发布仓库：文件、是否存在、是否私有都由测试控制。
class _FakeRepo implements PublishRepository {
  _FakeRepo({this.exists = true, this.private = false});

  bool exists;
  bool private;
  bool created = false;
  final Map<String, List<int>> files = {};

  @override
  Future<String> login() async => 'me';

  @override
  Future<RemoteRepo?> repo() async => exists || created
      ? RemoteRepo(defaultBranch: 'main', private: private)
      : null;

  @override
  Future<RemoteRepo> create() async {
    created = true;
    exists = true;
    return RemoteRepo(defaultBranch: 'main', private: private);
  }

  @override
  Future<RemoteFile?> file(String path, {required String branch}) async {
    final bytes = files[path];
    if (bytes == null) return null;
    return RemoteFile(bytes: bytes, sha: 'sha-${bytes.length}');
  }

  @override
  Future<void> putFile(String path, List<int> bytes,
      {required String branch, required String message}) async {
    files[path] = List<int>.from(bytes);
  }
}
