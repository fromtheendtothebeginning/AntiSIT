import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('接口：workshop.*（只给内置「拓展工坊」）', () {
    late Directory dir;
    late WorkshopStore workshop;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ext_workshop_bridge_');
      workshop = WorkshopStore(documentsDirectory: () async => dir.path);
      // 装拓展会往「文档目录」里复制：测试里没有 path_provider，必须换成临时目录
      final savedDocs = ExtensionStore.documentsDirectory;
      ExtensionStore.documentsDirectory = () async => dir.path;
      addTearDown(() => ExtensionStore.documentsDirectory = savedDocs);
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<ExtBridge> bridge(WidgetTester tester, String extId) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      return ExtBridge(
        extId: extId,
        context: tester.element(find.byType(SizedBox)),
        workshop: workshop,
      );
    }

    testWidgets('别的拓展调 workshop.* 直接拒；工坊能建草稿、读文件、自检', (tester) async {
      final draft = await workshop.create(name: '喝水记录');
      final other = await bridge(tester, 'e1');
      await expectLater(
        other.call('workshop.list', null),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('只允许内置「拓展工坊」调用'),
          ),
        ),
      );

      final ws = await bridge(tester, ExtBridge.workshopExtId);
      final list = await ws.call('workshop.list', null) as Map;
      expect((list['drafts'] as List).single['id'], draft.id);

      final files =
          await ws.call('workshop.files', {'draftId': draft.id}) as Map;
      expect(
        (files['files'] as List).map((f) => f['path']),
        containsAll(['ext.json', 'main.js', 'style.css']),
      );

      final read =
          await ws.call('workshop.read', {
                'draftId': draft.id,
                'path': 'main.js',
              })
              as Map;
      expect(read['content'], contains('export default'));
      expect(read['version'], matches(RegExp(r'^[0-9a-f]{64}$')));
      final check =
          await ws.call('workshop.validate', {'draftId': draft.id}) as Map;
      expect(check['ok'], isTrue);
    });

    testWidgets('自检：用了 ctx.background 但清单没声明 background → 报出来', (tester) async {
      // 真实事故回归：清单漏权限时权限门直接拒绝调用，插件只表现成一条 Invalid argument(s)，自检要提前说清楚。
      final draft = await workshop.create(name: '后台刷新');
      final ws = await bridge(tester, ExtBridge.workshopExtId);
      // 直接走 store 写盘：workshop.write 每次都要弹原生确认，这里测的是自检本身
      final main = await workshop.readFileVersioned(draft.id, 'main.js');
      await workshop.writeFile(draft.id, 'main.js',
          'export default { apply(ctx) { ctx.background.keepAlive({ enabled: true }); } }',
          expectedVersion: main.version);

      var check = await ws.call('workshop.validate', {'draftId': draft.id}) as Map;
      expect(check['ok'], isFalse);
      expect((check['problems'] as List).join('\n'), contains('background'));

      // 清单里补上就通过
      final manifest = await workshop.readFileVersioned(draft.id, 'ext.json');
      final raw = jsonDecode(manifest.content) as Map<String, Object?>;
      raw['permissions'] = ['background'];
      await workshop.writeFile(draft.id, 'ext.json',
          '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
          expectedVersion: manifest.version);
      check = await ws.call('workshop.validate', {'draftId': draft.id}) as Map;
      expect(check['ok'], isTrue, reason: '${check['problems']}');
    });

    testWidgets('写文件前弹原生确认；确认后才落盘', (tester) async {
      final draft = await workshop.create(name: '喝水记录');
      final ws = await bridge(tester, ExtBridge.workshopExtId);
      const code =
          'export default { apply(ctx) { ctx.ui.root.textContent = "hi" } }';
      final read = await workshop.readFileVersioned(draft.id, 'main.js');

      final pending = ws.call('workshop.write', {
        'draftId': draft.id,
        'path': 'main.js',
        'content': code,
        'expectedVersion': read.version,
      });
      await tester.pumpAndSettle();
      expect(find.text('写入 main.js'), findsOneWidget, reason: '确认框写清是哪个文件');
      expect(
        await workshop.readFile(draft.id, 'main.js'),
        isNot(code),
        reason: '用户点确认前不能写',
      );

      await tester.tap(find.widgetWithText(FilledButton, '写入'));
      await tester.pumpAndSettle();
      final result = await pending as Map;
      expect(result['ok'], isTrue);
      expect(result['version'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await workshop.readFile(draft.id, 'main.js'), code);
    });

    testWidgets('已有文件没读就写：直接拒，连确认框都不弹', (tester) async {
      final draft = await workshop.create(name: '喝水记录');
      final ws = await bridge(tester, ExtBridge.workshopExtId);

      await expectLater(
        ws.call('workshop.write', {
          'draftId': draft.id,
          'path': 'main.js',
          'content': 'export default {}',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('覆盖已有文件前先读取'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('写入 main.js'), findsNothing);
    });

    testWidgets('取消写入：草稿保持原样，工具结果告诉 Agent 被拒', (tester) async {
      final draft = await workshop.create(name: '喝水记录');
      final ws = await bridge(tester, ExtBridge.workshopExtId);
      final before = await workshop.readFileVersioned(draft.id, 'main.js');

      final pending = ws.call('workshop.write', {
        'draftId': draft.id,
        'path': 'main.js',
        'content': 'export default {}',
        'expectedVersion': before.version,
      });
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      final result = await pending as Map;
      expect(result['ok'], isFalse);
      expect(result['denied'], isTrue);
      expect(
        (await workshop.readFileVersioned(draft.id, 'main.js')).content,
        before.content,
      );
    });

    test('读后写版本门、隐藏文件与草稿 id 边界', () async {
      final draft = await workshop.create(name: '喝水记录');
      final first = await workshop.readFileVersioned(draft.id, 'main.js');
      await workshop.writeFile(
        draft.id,
        'main.js',
        'export default {}',
        expectedVersion: first.version,
      );
      await expectLater(
        workshop.writeFile(
          draft.id,
          'main.js',
          'export default { apply() {} }',
          expectedVersion: first.version,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('已变化'),
          ),
        ),
        reason: '拿旧版本覆盖要拒绝',
      );

      await expectLater(
        workshop.readFile(draft.id, '.workshop/session.json'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('隐藏文件'),
          ),
        ),
      );
      await expectLater(
        workshop.loadSession('../outside'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('id 不合法'),
          ),
        ),
      );

      final bad = await workshop.create(name: '坏清单');
      final manifest = await workshop.readFileVersioned(bad.id, 'ext.json');
      await workshop.writeFile(
        bad.id,
        'ext.json',
        '{"id":"sit.bad","name":"坏清单","main":"../evil.js"}',
        expectedVersion: manifest.version,
      );
      expect((await workshop.validate(bad.id)).join(), contains('ext.json'));
    });

    testWidgets('会话日志按草稿保存与读取', (tester) async {
      final draft = await workshop.create(name: '喝水记录');
      final ws = await bridge(tester, ExtBridge.workshopExtId);
      const payload =
          '{"version":1,"events":[{"type":"user/message","content":"hi"}]}';
      expect(
        await ws.call('workshop.session.get', {'draftId': draft.id}),
        isNull,
      );

      expect(
        await ws.call('workshop.session.set', {
          'draftId': draft.id,
          'data': payload,
        }),
        isTrue,
      );
      expect(
        await ws.call('workshop.session.get', {'draftId': draft.id}),
        payload,
      );
      expect(File('${draft.dir}/.workshop/session.json').existsSync(), isTrue);
      expect(
        (await workshop.listFiles(draft.id)).map((f) => f.path),
        isNot(contains('.workshop/session.json')),
        reason: '会话日志不该出现在文件树 / 安装内容里',
      );
    });

    testWidgets('一个草稿多段对话：新建 / 列表 / 读写 / 删除', (tester) async {
      final draft = await workshop.create(name: '多对话');
      final ws = await bridge(tester, ExtBridge.workshopExtId);

      final created =
          await ws.call('workshop.session.create', {
                'draftId': draft.id,
                'title': '第一段',
              })
              as Map;
      final cid = created['id'] as String;
      expect(cid, isNotEmpty);

      const payload = '{"title":"第一段","events":[]}';
      await ws.call('workshop.session.set', {
        'draftId': draft.id,
        'conversationId': cid,
        'data': payload,
      });
      final list =
          await ws.call('workshop.session.list', {'draftId': draft.id}) as Map;
      final conversations = (list['conversations'] as List).cast<Map>();
      expect(
        conversations.any((c) => c['id'] == cid && c['title'] == '第一段'),
        isTrue,
      );
      expect(
        await ws.call('workshop.session.get', {
          'draftId': draft.id,
          'conversationId': cid,
        }),
        payload,
      );

      final pending = ws.call('workshop.session.delete', {
        'draftId': draft.id,
        'conversationId': cid,
      });
      await tester.pumpAndSettle();
      expect(find.text('删除这段对话'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认执行'));
      await tester.pumpAndSettle();
      expect((await pending as Map)['ok'], isTrue);
      final after =
          await ws.call('workshop.session.list', {'draftId': draft.id}) as Map;
      expect(
        (after['conversations'] as List).any((c) => (c as Map)['id'] == cid),
        isFalse,
      );
    });

    testWidgets('删除未安装的拓展：确认后整个目录消失；已安装的拒绝', (tester) async {
      final draft = await workshop.create(name: '待删拓展');
      final ws = await bridge(tester, ExtBridge.workshopExtId);

      final pending = ws.call('workshop.deleteDraft', {'draftId': draft.id});
      await tester.pumpAndSettle();
      expect(find.textContaining('删除拓展'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认执行'));
      await tester.pumpAndSettle();
      expect((await pending as Map)['ok'], isTrue);
      expect(Directory(draft.dir).existsSync(), isFalse);

      final installed = await workshop.create(name: '已安装拓展');
      await ExtensionStore.I.add(
        ExtensionItem(
          id: installed.id,
          name: '已安装',
          url: 'https://example.com/x',
        ),
      );
      await expectLater(
        ws.call('workshop.deleteDraft', {'draftId': installed.id}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('已安装'),
          ),
        ),
      );
      expect(Directory(installed.dir).existsSync(), isTrue);
    });

    testWidgets('重命名拓展与对话：落盘、列表更新，已安装的卡片同步改名', (tester) async {
      final draft = await workshop.create(name: '旧名字');
      // 先装一份：重命名草稿时，已安装卡片也要跟着改
      final item = await workshop.install(draft.id);
      await ExtensionStore.I.add(item);

      final ws = await bridge(tester, ExtBridge.workshopExtId);
      final renamed =
          await ws.call('workshop.renameDraft', {
                'draftId': draft.id,
                'name': '新名字',
              })
              as Map;
      expect(renamed['name'], '新名字');
      expect(renamed['installed'], isTrue);
      expect(
        ExtensionStore.I.items.firstWhere((e) => e.id == draft.id).name,
        '新名字',
        reason: '已安装的卡片一起改名',
      );
      expect(File('${draft.dir}/ext.json').readAsStringSync(), contains('新名字'));

      final conv = await workshop.createConversation(draft.id, title: '新对话');
      final pending =
          await ws.call('workshop.session.rename', {
                'draftId': draft.id,
                'conversationId': conv.id,
                'title': '改过的对话名',
              })
              as Map;
      expect(pending['title'], '改过的对话名');
      final list = await workshop.listConversations(draft.id);
      expect(list.firstWhere((c) => c.id == conv.id).title, '改过的对话名');
      final raw = await workshop.loadConversation(draft.id, conv.id);
      expect(raw, contains('改过的对话名'), reason: '标题写进会话文件');
    });

    testWidgets('技能库：安装要确认，能列表 / 读取 / 删除', (tester) async {
      final ws = await bridge(tester, ExtBridge.workshopExtId);

      final pending = ws.call('workshop.skills.install', {
        'name': '代码审查',
        'description': '改完 JS 后逐项检查',
        'content': '# 代码审查\n1. 检查 localStorage\n2. 检查工具调用配对',
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('安装技能'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '写入'));
      await tester.pumpAndSettle();
      final installed = await pending as Map;
      expect(installed['ok'], isTrue);
      final id = installed['id'] as String;

      final list = await ws.call('workshop.skills.list', null) as Map;
      expect((list['skills'] as List).single['name'], '代码审查');
      final read = await ws.call('workshop.skills.read', {'id': id}) as Map;
      expect(read['content'], contains('localStorage'));

      final deleting = ws.call('workshop.skills.delete', {'id': id});
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认执行'));
      await tester.pumpAndSettle();
      expect((await deleting as Map)['ok'], isTrue);
      final after = await ws.call('workshop.skills.list', null) as Map;
      expect(after['skills'], isEmpty);
    });

    testWidgets('完全访问：开启要确认，之后写入不再弹确认', (tester) async {
      final draft = await workshop.create(name: '完全访问');
      final ws = await bridge(tester, ExtBridge.workshopExtId);
      final before = await workshop.readFileVersioned(draft.id, 'main.js');

      final enabling = ws.call('workshop.setFullAccess', {'enabled': true});
      await tester.pumpAndSettle();
      expect(find.text('开启完全访问模式'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认执行'));
      await tester.pumpAndSettle();
      expect((await enabling as Map)['enabled'], isTrue);

      const code = 'export default { apply() {} }';
      final written =
          await ws.call('workshop.write', {
                'draftId': draft.id,
                'path': 'main.js',
                'content': code,
                'expectedVersion': before.version,
              })
              as Map;
      expect(written['ok'], isTrue);
      expect(await workshop.readFile(draft.id, 'main.js'), code);
      expect(find.text('写入 main.js'), findsNothing, reason: '完全访问下不再弹确认');
    });
  });
}

