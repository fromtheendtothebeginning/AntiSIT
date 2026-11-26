import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('Cordis 压缩包导入', () {
    Map<String, String> manifestZip({
      String id = 'sit.demo',
      String main = 'main.js',
    }) => {
      'myapp/ext.json':
          '{"id":"$id","name":"示例","version":"1.0.0","main":"$main","style":"style.css"}',
      'myapp/$main':
          'export default { apply(ctx) { ctx.ui.root.textContent = "hi" } }',
      'myapp/style.css': 'body{color:red}',
    };

    test('解开 Cordis 拓展：ext.json 找到、main.js / style.css 都解出来', () {
      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final bundle = extractBundle(
        bytes: makeZip(manifestZip()),
        dir: dir.path,
      );
      expect(bundle.manifest.id, 'sit.demo');
      expect(bundle.entry, endsWith('main.js'), reason: '顶层目录只去掉一层');
      expect(File(bundle.entry).existsSync(), isTrue);
      expect(
        File('${File(bundle.entry).parent.path}/style.css').existsSync(),
        isTrue,
      );
    });

    test('缺 ext.json / 缺入口就报错', () {
      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      expect(
        () => extractBundle(
          bytes: makeZip({'index.html': '<h1>x</h1>'}),
          dir: dir.path,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => extractBundle(
          bytes: makeZip({
            'ext.json': '{"id":"sit.bad","name":"坏","main":"missing.js"}',
          }),
          dir: dir.path,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('zip-slip：绝对路径 / .. 的条目整条丢掉，绝不写到目标目录外面', () {
      expect(normalizeEntryPath('/etc/passwd'), isNull);
      expect(normalizeEntryPath('../evil.txt'), isNull);
      expect(normalizeEntryPath('a/../../b.txt'), isNull);
      expect(normalizeEntryPath(r'C:\Windows\x.dll'), isNull);
      expect(normalizeEntryPath('./app/index.html'), 'app/index.html');

      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final bundle = extractBundle(
        bytes: makeZip({...manifestZip(), '../evil.txt': 'bad'}),
        dir: dir.path,
      );
      expect(
        File('${dir.parent.path}/evil.txt').existsSync(),
        isFalse,
        reason: '没写到目标目录外面',
      );
      expect(File(bundle.entry).existsSync(), isTrue);
    });

    test('Cordis 页面：市场包默认禁网，声明 network 才放开；入口代码不裸奔', () async {
      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final bundle = extractBundle(
        bytes: makeZip(manifestZip()),
        dir: dir.path,
      );

      final closed = await CordisBundleLoader.load(
        ExtensionItem(
          id: 'sit.demo',
          name: '示例',
          url: bundle.entry,
          bundled: true,
          runtime: ExtensionItem.runtimeCordis,
          fromMarket: true,
          permissions: const [],
        ),
        appVersion: '1.25.0',
      );
      expect(closed.html, contains('Content-Security-Policy'));
      expect(closed.html, contains("connect-src 'none'"));
      expect(
        closed.html,
        contains("script-src 'unsafe-inline' blob:"),
        reason: 'Cordis 运行时和拓展代码要能跑',
      );
      expect(closed.html, contains('antisit-ready'));
      expect(closed.html, contains('au-btn'), reason: '每个拓展页都自动注入 AntiUI 样式');
      expect(
        closed.html,
        contains('AntiUI'),
        reason: 'AntiUI JS 要自动注入，作者不用自己带组件',
      );
      expect(
        closed.html,
        contains('ctx.plugin(Files)'),
        reason: 'ctx.files 服务要注册进 Cordis 上下文',
      );
      expect(
        closed.html,
        contains("antiSIT.on('theme.change'"),
        reason: '主题 / 夜间模式变化要能实时推给拓展页',
      );
      expect(
        closed.html,
        contains('--antisit-menu-bg'),
        reason: '完整色板要映射成 CSS 变量',
      );
      expect(closed.html, contains('--antisit-wells'), reason: '玻璃主题的场景光斑也要共享');
      expect(
        closed.html,
        isNot(contains('ctx.ui.root.textContent')),
        reason: 'main.js 走 base64 注入，不能直接摊在 HTML 里',
      );

      final open = await CordisBundleLoader.load(
        ExtensionItem(
          id: 'sit.demo',
          name: '示例',
          url: bundle.entry,
          bundled: true,
          runtime: ExtensionItem.runtimeCordis,
          fromMarket: true,
          permissions: const ['network'],
        ),
        appVersion: '1.25.0',
      );
      expect(open.html, contains('connect-src https:'));
      expect(open.html, isNot(contains("connect-src 'none'")));
    });
  });
}

