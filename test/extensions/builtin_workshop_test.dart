import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('拓展工坊（内置 Cordis 拓展）', () {
    test('内置工坊的 asset 能拼出 Cordis 页面，main.js 不裸奔', () async {
      final item = kBuiltinExtensions.first;
      expect(item.id, 'builtin.workshop');
      expect(item.runtime, ExtensionItem.runtimeCordis);
      final page = await CordisBundleLoader.load(item, appVersion: '1.25.0');
      expect(page.html, contains('正在启动「拓展工坊」'));
      expect(page.html, contains('workshop.list'), reason: '宿主服务已注入');
      expect(
        page.html,
        contains('workshop.session.create'),
        reason: '多对话接口已注入',
      );
      expect(
        page.html,
        contains('workshop.session.rename'),
        reason: '重命名对话接口已注入',
      );
      expect(page.html, contains('workshop.renameDraft'), reason: '重命名拓展接口已注入');
      expect(page.html, contains('ai.chatToolsStream'), reason: '流式 AI 接口已注入');
      expect(page.html, contains("script-src 'unsafe-inline' blob:"));
      expect(
        page.html,
        isNot(contains('你是 AntiSIT「拓展工坊」里的编码 Agent')),
        reason: 'main.js 走 base64，不应直接出现在 HTML 里',
      );
    });

    test('草稿工作区：新建 / 读写 / 校验 / 安装', () async {
      final dir = Directory.systemTemp.createTempSync('ext_workshop_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final savedDocs = ExtensionStore.documentsDirectory;
      ExtensionStore.documentsDirectory = () async => dir.path;
      addTearDown(() => ExtensionStore.documentsDirectory = savedDocs);

      final workshop = WorkshopStore(documentsDirectory: () async => dir.path);
      final draft = await workshop.create(name: '喝水记录');
      expect(draft.manifest.name, '喝水记录');
      final files = await workshop.listFiles(draft.id);
      expect(
        files.map((f) => f.path),
        containsAll(['ext.json', 'main.js', 'style.css']),
      );

      final main = await workshop.readFileVersioned(draft.id, 'main.js');
      expect(main.content, contains('export default'));
      expect(main.version, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await workshop.validate(draft.id), isEmpty);

      await workshop.writeFile(
        draft.id,
        'main.js',
        'export default { apply(ctx) { ctx.ui.root.textContent = "hi" } }',
        expectedVersion: main.version,
      );
      expect((await workshop.validate(draft.id)), isEmpty);

      await workshop.writeFile(
        draft.id,
        'app.js',
        'localStorage.setItem("x", 1)',
      );
      expect(
        (await workshop.validate(draft.id)).join(),
        contains('localStorage'),
      );

      expect(
        () => workshop.readFile(draft.id, '../evil.txt'),
        throwsA(isA<FormatException>()),
      );

      final app = await workshop.readFileVersioned(draft.id, 'app.js');
      await workshop.deleteFile(
        draft.id,
        'app.js',
        expectedVersion: app.version,
      );
      await workshop.writeFile(
        draft.id,
        'files.js',
        'const picked = await ctx.files.pick({ accept: ".txt" });',
      );
      expect(
        (await workshop.validate(draft.id)).join(),
        contains('ctx.files'),
        reason: '用了 ctx.files 却没声明 files 权限要提醒',
      );
      final filesJs = await workshop.readFileVersioned(draft.id, 'files.js');
      await workshop.deleteFile(
        draft.id,
        'files.js',
        expectedVersion: filesJs.version,
      );
      await expectLater(
        workshop.deleteFile(draft.id, 'ext.json'),
        throwsA(isA<FormatException>()),
      );
      final item = await workshop.install(draft.id);
      expect(item.id, draft.id);
      expect(item.runtime, ExtensionItem.runtimeCordis);
      expect(item.bundled, isTrue);
      expect(File(item.url).existsSync(), isTrue);
      expect(File(item.url).readAsStringSync(), contains('ctx.ui.root'));
      expect(ExtensionStore.I.items.any((e) => e.id == draft.id), isTrue);
    });
  });
}

