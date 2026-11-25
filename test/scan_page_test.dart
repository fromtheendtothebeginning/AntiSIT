import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/plugin_activities.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_scan/plugin_scan.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 扫一扫页与两处入口：识码结果面板、相册识别的三种结果、二课活动 / 拓展页右上角扫码图标按 ScanCapability 取用；相机用注入的替身。
void main() {
  String? clipboard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.I.demo = false;
    ScanPage.debugCamera = (context) => const ColoredBox(
        color: Colors.green, child: Center(child: Text('假相机')));
    // 扫码页用活动插件的能力、入口测试用扫一扫插件的能力；相机走 debugCamera 替身，不注册真摄像头能力。
    PluginRegistry.I = PluginRegistry(
      features: const [ActivitiesPlugin(), ScanPlugin()],
      themes: const [GlassTheme()],
      capabilities: const {
        PluginIds.activities: ActivitiesCapabilityImpl(),
        PluginIds.scan: _StubScanCapability(),
      },
    );
    // widget 测试里平台通道没人应答会永远等下去，给剪贴板挂个 mock
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboard};
      }
      return null;
    });
    // url_launcher 通道没人应答时 Future 永不完成：挂个必抛的 mock，让 openExternalUrl 稳定走「复制链接」兜底。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      throw PlatformException(code: 'test-no-browser');
    });
  });

  tearDown(() {
    ScanPage.debugCamera = null;
    ScanPage.debugPickImage = null;
    ScanPage.debugAnalyzeImage = null;
    ScanPage.debugSign = null;
    PluginRegistry.I = PluginRegistry();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), null);
  });

  Future<void> pumpScanPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScanPage()));
    await tester.pumpAndSettle();
  }

  Future<void> detect(WidgetTester tester, String value) async {
    final state = tester.state(find.byType(ScanPage));
    // debugDetect 要等面板关掉才返回，不能 await——否则测试卡死等不到 pump
    unawaited((state as dynamic).debugDetect(value));
    await tester.pumpAndSettle();
  }

  group('扫码结果面板', () {
    testWidgets('内容可复制；不是网址不给「打开链接」；继续扫回到取景', (tester) async {
      await pumpScanPage(tester);
      await detect(tester, 'hello-qr');

      expect(find.text('扫码结果'), findsOneWidget);
      expect(find.text('hello-qr'), findsOneWidget);
      expect(find.text('打开链接'), findsNothing, reason: '不是网址不给打开');

      await tester.tap(find.text('复制'));
      await tester.pump();
      expect(clipboard, 'hello-qr', reason: '复制进了剪贴板');

      await tester.tap(find.text('继续扫码'));
      await tester.pumpAndSettle();
      expect(find.text('扫码结果'), findsNothing, reason: '面板关了，回到取景继续扫');
    });

    testWidgets('网址结果给「打开链接」入口', (tester) async {
      await pumpScanPage(tester);
      await detect(tester, 'https://example.com/join');
      expect(find.text('打开链接'), findsOneWidget);
    });

    testWidgets('打开链接：用本机 WebView 内核整页打开', (tester) async {
      final opened = <String>[];
      PluginRegistry.I = PluginRegistry(
        features: const [WebViewPlugin()],
        themes: const [GlassTheme()],
        capabilities: {
          PluginIds.webview: _FakeWebViewCapability((url) => opened.add(url!)),
        },
      );
      await pumpScanPage(tester);
      await detect(tester, 'https://example.com/open');

      await tester.tap(find.text('打开链接'));
      await tester.pumpAndSettle();

      expect(opened, ['https://example.com/open'], reason: '网址交给内置内核打开');
      expect(find.text('扫码结果'), findsNothing, reason: '面板先关掉再打开网页');
    });

    testWidgets('WebView 内核不可用：退回系统浏览器（复制链接兜底）', (tester) async {
      await pumpScanPage(tester);
      await detect(tester, 'https://example.com/fallback');

      await tester.tap(find.text('打开链接'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已复制链接'), findsOneWidget,
          reason: 'launchUrl 在测试环境必失败 → 走复制兜底，证明没走内核');
      expect(clipboard, 'https://example.com/fallback');
    });

    testWidgets('面板开着时同一枚码不会反复弹', (tester) async {
      await pumpScanPage(tester);
      await detect(tester, 'hello-qr');

      final state = tester.state(find.byType(ScanPage));
      await (state as dynamic).debugDetect('hello-qr');
      await tester.pumpAndSettle();

      expect(find.text('扫码结果'), findsOneWidget, reason: '还是一个面板，没叠第二个');
    });
  });

  group('相册识别', () {
    testWidgets('识出二维码：弹结果面板', (tester) async {
      await pumpScanPage(tester);
      ScanPage.debugPickImage = () async => '/tmp/qr.png';
      ScanPage.debugAnalyzeImage = (path) async {
        expect(path, '/tmp/qr.png');
        return ['photo-qr'];
      };

      await tester.tap(find.text('相册识别'));
      await tester.pumpAndSettle();

      expect(find.text('扫码结果'), findsOneWidget);
      expect(find.text('photo-qr'), findsOneWidget);
    });

    testWidgets('图片里没二维码：提示一句，不弹面板', (tester) async {
      await pumpScanPage(tester);
      ScanPage.debugPickImage = () async => '/tmp/none.png';
      ScanPage.debugAnalyzeImage = (path) async => [];

      await tester.tap(find.text('相册识别'));
      await tester.pumpAndSettle();

      expect(find.text('这张图片里没识别出二维码'), findsOneWidget);
      expect(find.text('扫码结果'), findsNothing);
      expect(find.text('相册识别'), findsOneWidget, reason: '还在取景页，可以再挑一张');
    });

    testWidgets('用户取消选图：什么都不发生', (tester) async {
      await pumpScanPage(tester);
      ScanPage.debugPickImage = () async => null;

      await tester.tap(find.text('相册识别'));
      await tester.pumpAndSettle();

      expect(find.text('扫码结果'), findsNothing);
      expect(find.text('相册识别'), findsOneWidget);
    });

    testWidgets('一张图识出多个码：弹选择面板，点选哪个就用哪个', (tester) async {
      await pumpScanPage(tester);
      ScanPage.debugPickImage = () async => '/tmp/multi.png';
      ScanPage.debugAnalyzeImage = (path) async => ['code-b', 'code-a', 'code-b'];

      await tester.tap(find.text('相册识别'));
      await tester.pumpAndSettle();

      expect(find.text('识别到 2 个二维码，点选要用的一个'), findsOneWidget,
          reason: '重复码去重后 2 个，弹选择面板');
      expect(find.text('code-a'), findsOneWidget);
      expect(find.text('code-b'), findsOneWidget);

      await tester.tap(find.text('code-a'));
      await tester.pumpAndSettle();

      expect(find.text('扫码结果'), findsOneWidget);
      expect(find.text('code-a'), findsOneWidget, reason: '选中的码走通用结果面板');
      expect(find.text('code-b'), findsNothing);
    });

    testWidgets('多码里混着签到码：点选后走签到面板', (tester) async {
      const signQr = 'https://xg.sit.edu.cn/hdgl/hdxq/qd/'
          '94b69a40f38eedd060cf9ecec1fe78cd/'
          'c4f2a32a171df39ee5ba8834c8a425ee/1793874178304';
      await pumpScanPage(tester);
      ScanPage.debugPickImage = () async => '/tmp/multi2.png';
      ScanPage.debugAnalyzeImage = (path) async => [signQr, 'https://example.com/other'];
      ScanPage.debugSign = (hdId, hdActId) async =>
          {'ok': true, 'data': {'msg': '签到成功'}};

      await tester.tap(find.text('相册识别'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining(signQr.substring(0, 40)));
      await tester.pumpAndSettle();

      expect(find.text('第二课堂 · 扫码签到'), findsOneWidget, reason: '选中的签到码走签到面板');
      expect(find.text('打开链接'), findsNothing);
    });
  });

  group('二课签到码（第二课堂活动的签到 / 签退）', () {
    const signQr = 'https://xg.sit.edu.cn/hdgl/hdxq/qd/'
        '94b69a40f38eedd060cf9ecec1fe78cd/'
        'c4f2a32a171df39ee5ba8834c8a425ee/1793874178304';

    test('识别规则：qd / qt 变体都算，别的网址不算', () {
      expect(ScanPage.dektSignRe.hasMatch(signQr), isTrue);
      expect(ScanPage.dektSignRe.hasMatch(
          'https://xg.sit.edu.cn/hdgl/hdxq/qt/abc-def/abc-def/1793874178304'), isTrue);
      expect(ScanPage.dektSignRe.hasMatch(
          'https://example.com/hdgl/hdxq/qd/a/b/1793874178304'), isFalse);
      expect(ScanPage.dektSignRe.hasMatch(
          'https://xg.sit.edu.cn/hdgl/hdxq/qd/a/b'), isFalse, reason: '缺时间戳段');
    });

    test('识别规则：报名（培训）码 pxqd 两段也算', () {
      expect(
          ScanPage.dektTrainSignRe.hasMatch(
              'https://xg.sit.edu.cn/hdgl/pxqd/ee49d370b72dceef4c7b5a6d3580ebfc/a50571f3af113b02945b5309fe815f93'),
          isTrue);
      expect(
          ScanPage.dektTrainSignRe.hasMatch(
              'https://xg.sit.edu.cn/hdgl/hdxq/qd/a/b/1793874178304'),
          isFalse,
          reason: '签到码走 signInOrSignOut，不混用');
      expect(
          ScanPage.dektTrainSignRe.hasMatch(
              'https://xg.sit.edu.cn/hdgl/pxqd/a/b/1793874178304'),
          isFalse,
          reason: '报名码没有时间戳段，多出来的不是报名码');
    });

    testWidgets('报名（培训）码：走报名签到面板，提交走另一个接口', (tester) async {
      const trainQr = 'https://xg.sit.edu.cn/hdgl/pxqd/'
          'ee49d370b72dceef4c7b5a6d3580ebfc/a50571f3af113b02945b5309fe815f93';
      final calls = <(String, String)>[];
      ScanPage.debugSign = (hdId, pxId) async {
        calls.add((hdId, pxId));
        return {'ok': true, 'data': {'msg': '签到成功'}};
      };
      await pumpScanPage(tester);
      await detect(tester, trainQr);

      expect(find.text('第二课堂 · 报名签到'), findsOneWidget, reason: '报名码走单向签到面板');
      expect(find.text('完成签到'), findsOneWidget, reason: '没有签退语义');

      await tester.tap(find.text('完成签到'));
      await tester.pumpAndSettle();

      expect(calls, const [
        ('ee49d370b72dceef4c7b5a6d3580ebfc', 'a50571f3af113b02945b5309fe815f93'),
      ]);
      expect(find.text('签到成功'), findsOneWidget);
    });

    test('识别规则：活动详情码（门户包装 / 裸路径）都解析出 hdId', () {
      const raw = 'https://xg.sit.edu.cn/login?redirect=/hdgl/hdxq/'
          '94b69a40f38eedd060cf9ecec1fe78cd';
      expect(ScanPage.dektDetailId(raw),
          '94b69a40f38eedd060cf9ecec1fe78cd', reason: '用户实测的门户包装形态');
      expect(ScanPage.dektDetailId('https://xg.sit.edu.cn/login'
          '?redirect=%2Fhdgl%2Fhdxq%2F94b69a40f38eedd060cf9ecec1fe78cd'),
          '94b69a40f38eedd060cf9ecec1fe78cd', reason: '整段百分号编码也兼容');
      expect(ScanPage.dektDetailId(
          'https://xg.sit.edu.cn/hdgl/hdxq/94b69a40f38eedd060cf9ecec1fe78cd'),
          '94b69a40f38eedd060cf9ecec1fe78cd', reason: '裸路径形态');
      expect(ScanPage.dektDetailId('https://other.com/login?redirect=/hdgl/hdxq/abc'),
          isNull, reason: '别的域名不认');
      expect(ScanPage.dektDetailId('https://xg.sit.edu.cn/login'), isNull);
    });

    testWidgets('活动详情码：面板给出「查看活动详情」，点开推入 App 的活动详情页', (tester) async {
      const raw = 'https://xg.sit.edu.cn/login?redirect=/hdgl/hdxq/'
          '94b69a40f38eedd060cf9ecec1fe78cd';
      await pumpScanPage(tester);
      await detect(tester, raw);

      expect(find.text('第二课堂 · 活动码'), findsOneWidget);
      expect(find.text('查看活动详情'), findsOneWidget);
      expect(find.text('打开链接'), findsNothing, reason: '详情码不走通用网页面板');

      await tester.tap(find.text('查看活动详情'));
      await tester.pumpAndSettle();

      expect(find.byType(ActivityDetailPage), findsOneWidget,
          reason: '推入 App 自己的活动详情页（报名在详情页里完成）');
      expect(find.text('复制码内容'), findsNothing);
    });

    testWidgets('hdId 能对上演示活动时：详情页带完整元信息（名称 / 报名按钮）', (tester) async {
      AppState.I.demo = true; // 元信息按 hdId 从演示活动列表里捞
      addTearDown(() => AppState.I.demo = false);
      await pumpScanPage(tester);
      await detect(tester, 'https://xg.sit.edu.cn/login?redirect=/hdgl/hdxq/a001');
      await tester.tap(find.text('查看活动详情'));
      await tester.pumpAndSettle();

      expect(find.text('AI 赋能学习效率提升讲座'), findsOneWidget,
          reason: '元信息按 hdId 从活动列表捞到并带进详情页，页面不开天窗');
      expect(find.textContaining('报名'), findsWidgets);
    });

    testWidgets('识出签到码：专门面板，提交后显示学校判定原文', (tester) async {
      final calls = <(String, String)>[];
      ScanPage.debugSign = (hdId, hdActId) async {
        calls.add((hdId, hdActId));
        return {'ok': true, 'data': {'msg': '签到成功'}};
      };
      await pumpScanPage(tester);
      await detect(tester, signQr);

      expect(find.text('第二课堂 · 扫码签到'), findsOneWidget);
      expect(find.text('完成签到 / 签退'), findsOneWidget);
      expect(find.text('打开链接'), findsNothing, reason: '签到码走专门面板，不按普通网址处理');

      await tester.tap(find.text('完成签到 / 签退'));
      await tester.pumpAndSettle();

      expect(calls, const [
        ('94b69a40f38eedd060cf9ecec1fe78cd', 'c4f2a32a171df39ee5ba8834c8a425ee'),
      ], reason: 'hdId / hdActId 取自二维码路径段');
      expect(find.text('签到成功'), findsOneWidget, reason: '学校判定原文直接展示');
      expect(find.text('完成签到 / 签退'), findsNothing, reason: '成功后按钮收起，防重复提交');
    });

    testWidgets('学校拒绝（未报名 / 不在时间范围等）：原文摆出来，可重试', (tester) async {
      ScanPage.debugSign = (hdId, hdActId) async =>
          throw ApiError('您未报名该活动，无法进行该活动签到签退操作！');
      await pumpScanPage(tester);
      await detect(tester, signQr);

      await tester.tap(find.text('完成签到 / 签退'));
      await tester.pumpAndSettle();

      expect(find.text('您未报名该活动，无法进行该活动签到签退操作！'), findsOneWidget);
      expect(find.text('完成签到 / 签退'), findsOneWidget, reason: '失败后按钮还在，可重试');
    });

  });

  group('入口：右上角镂空扫码图标（扫一扫能力）', () {
    Future<void> pumpExt(WidgetTester tester, {bool withScan = true}) async {
      ExtensionStore.I = ExtensionStore();
      ExtensionStore.builtins = const [];
      MarketSource.I = MarketSource();
      // 市场目录不真发网络请求（失败即可，别让 loading 的不定动画卡住 settle）
      MarketSource.fetcher = (Uri url) => throw Exception('offline');
      PluginRegistry.I = PluginRegistry(
        features: const [WebViewPlugin(), ExtPlugin(), ScanPlugin()],
        themes: const [GlassTheme()],
        capabilities: {
          PluginIds.webview: const WebViewCapabilityImpl(),
          if (withScan) PluginIds.scan: const _StubScanCapability(),
        },
      );
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('拓展页右上角有扫一扫，点了进扫码页', (tester) async {
      await pumpExt(tester);

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
      await tester.pumpAndSettle();

      expect(find.text('扫码页替身'), findsOneWidget, reason: '扫码页推入了');
    });

    testWidgets('扫一扫插件不可用：拓展页不给入口（其余按钮照旧）', (tester) async {
      await pumpExt(tester, withScan: false);

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget, reason: '添加拓展按钮还在');
    });

    testWidgets('第二课堂活动页右上角有扫一扫', (tester) async {
      AppState.I.demo = true;
      addTearDown(() => AppState.I.demo = false);

      await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
      await tester.pumpAndSettle();
      expect(find.text('扫码页替身'), findsOneWidget, reason: '扫码页推入了');
    });

    testWidgets('扫一扫插件不可用：活动页不给入口', (tester) async {
      AppState.I.demo = true;
      addTearDown(() => AppState.I.demo = false);
      PluginRegistry.I = PluginRegistry(
        features: const [ActivitiesPlugin(), ScanPlugin()],
        themes: const [GlassTheme()],
        capabilities: const {PluginIds.activities: ActivitiesCapabilityImpl()},
      );

      await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsNothing);
    });
  });

  group('拓展模式扫码（网址 / 安装码）', () {
    Future<void> pumpScan(
      WidgetTester tester, {
      required void Function(ScanOutcome?) onResult,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push<ScanOutcome>(
                    MaterialPageRoute(
                      builder: (_) => const ScanPage(mode: ScanMode.addExtension),
                    ),
                  );
                  onResult(r);
                },
                child: const Text('打开扫码'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开扫码'));
      await tester.pumpAndSettle();
    }

    final sha = 'a' * 64;
    final bundleCode = jsonEncode({
      'antisit': 'ext',
      'url': 'https://example.com/sit.demo.zip',
      'sha256': sha,
      'name': '扫码演示',
      'id': 'sit.demo',
    });

    test('安装码格式：https + 64 位 sha256 才算；普通网址按链接；坏格式不算', () {
      final bundle = ScanPage.extensionOutcome(bundleCode);
      expect(bundle, isA<ScanBundleOutcome>());
      expect((bundle as ScanBundleOutcome).url, 'https://example.com/sit.demo.zip');
      expect(bundle.sha256, sha);
      expect(bundle.name, '扫码演示');
      expect(bundle.id, 'sit.demo');

      expect(ScanPage.extensionOutcome('https://example.com/a'),
          isA<ScanLinkOutcome>());
      expect(ScanPage.extensionOutcome('http://example.com/a'),
          isA<ScanLinkOutcome>(), reason: '普通 http 网址仍是可添加的链接');
      expect(ScanPage.extensionOutcome('ftp://example.com/a'), isNull);
      expect(ScanPage.extensionOutcome('hello'), isNull);
      expect(
          ScanPage.extensionOutcome(
              '{"antisit":"ext","url":"http://example.com/x.zip","sha256":"$sha"}'),
          isNull,
          reason: '安装包只认 https');
      expect(
          ScanPage.extensionOutcome(
              '{"antisit":"ext","url":"https://example.com/x.zip","sha256":"abc"}'),
          isNull,
          reason: 'sha256 不是 64 位就不算安装码');
      expect(ScanPage.looksLikeExtensionCode('{"antisit":"ext"}'), isTrue);
      expect(ScanPage.looksLikeExtensionCode('{"hello":1}'), isFalse);
    });

    test('源安装码：repo + 可选指纹；owner/repo 与 https 地址都认，坏格式不算', () {
      final outcome = ScanPage.extensionOutcome(jsonEncode({
        'antisit': 'source',
        'repo': 'someone/antisit-plugins',
        'fingerprint': 'abcd-ef01-2345',
        'name': '小明的源',
      }));
      expect(outcome, isA<ScanSourceOutcome>());
      final source = outcome as ScanSourceOutcome;
      expect(source.repo, 'someone/antisit-plugins');
      expect(source.fingerprint, 'ABCD-EF01-2345');
      expect(source.name, '小明的源');

      expect(
          ScanPage.extensionOutcome(
              '{"antisit":"source","repo":"https://cdn.example.com/market/"}'),
          isA<ScanSourceOutcome>());
      expect(
          ScanPage.extensionOutcome(
              '{"antisit":"source","repo":"http://example.com/market/"}'),
          isNull,
          reason: '完整地址只认 https');
      expect(
          ScanPage.extensionOutcome(
              '{"antisit":"source","repo":"not a repo"}'),
          isNull);
      expect(
          ScanPage.extensionOutcome(
              '{"antisit":"source","repo":"a/b","fingerprint":"xyz"}'),
          isNull,
          reason: '指纹必须是 12 位十六进制');
    });

    testWidgets('扫到网址：给「添加链接」，点下去带着网址回到调用方', (tester) async {
      ScanOutcome? outcome;
      await pumpScan(tester, onResult: (r) => outcome = r);
      await detect(tester, 'https://example.com/web');

      expect(find.text('网址'), findsOneWidget);
      expect(find.text('下载拓展'), findsNothing);
      final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('添加链接'),
        matching: find.bySubtype<FilledButton>(),
      ));
      expect(button.style?.backgroundColor?.resolve({}), SemColors.success,
          reason: '「添加链接」用成功绿，和「下载拓展」区分开');

      await tester.tap(find.text('添加链接'));
      await tester.pumpAndSettle();
      expect(outcome, isA<ScanLinkOutcome>());
      expect((outcome as ScanLinkOutcome).url, 'https://example.com/web');
      expect(find.byType(ScanPage), findsNothing, reason: '确认后关掉扫码页');
    });

    testWidgets('扫到安装码：给「下载拓展」，点下去带着安装信息回到调用方', (tester) async {
      ScanOutcome? outcome;
      await pumpScan(tester, onResult: (r) => outcome = r);
      await detect(tester, bundleCode);

      expect(find.text('拓展安装码'), findsOneWidget);
      expect(find.text('添加链接'), findsNothing);
      final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('下载拓展'),
        matching: find.bySubtype<FilledButton>(),
      ));
      expect(button.style?.backgroundColor?.resolve({}), SemColors.accent,
          reason: '「下载拓展」用主题强调色');

      await tester.tap(find.text('下载拓展'));
      await tester.pumpAndSettle();
      expect(outcome, isA<ScanBundleOutcome>());
      final spec = outcome as ScanBundleOutcome;
      expect(spec.url, 'https://example.com/sit.demo.zip');
      expect(spec.sha256, sha);
      expect(find.byType(ScanPage), findsNothing);
    });

    testWidgets('安装码字段不合法：提示格式不对，不弹结果面板', (tester) async {
      await pumpScan(tester, onResult: (_) {});
      await detect(
          tester, '{"antisit":"ext","url":"http://example.com/x.zip","sha256":"$sha"}');

      expect(find.textContaining('格式不对'), findsOneWidget);
      expect(find.text('下载拓展'), findsNothing);
      expect(find.byType(ScanPage), findsOneWidget, reason: '还在取景页');
    });
  });

  group('拓展页：扫码结果直接落库', () {
    Future<void> pumpExtWith(WidgetTester tester, ScanOutcome? outcome) async {
      ExtensionStore.I = ExtensionStore();
      ExtensionStore.builtins = const [];
      MarketSource.I = MarketSource();
      MarketSource.fetcher = (Uri url) => throw Exception('offline');
      PluginRegistry.I = PluginRegistry(
        features: const [WebViewPlugin(), ExtPlugin(), ScanPlugin()],
        themes: const [GlassTheme()],
        capabilities: {
          PluginIds.webview: const WebViewCapabilityImpl(),
          PluginIds.scan: _OutcomeScanCapability(outcome),
        },
      );
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('扫码得到网址：弹添加弹窗，确认后成为 web 拓展', (tester) async {
      await pumpExtWith(
          tester, const ScanLinkOutcome(url: 'https://example.com/app', raw: 'qr'));
      await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
      await tester.pumpAndSettle();

      expect(find.text('添加拓展'), findsOneWidget);
      final values = tester
          .widgetList<TextField>(find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)))
          .map((f) => f.controller?.text)
          .toList();
      expect(values, contains('https://example.com/app'), reason: '网址预填');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      final item = ExtensionStore.I.items.single;
      expect(item.url, 'https://example.com/app');
      expect(item.name, 'example.com', reason: '名称默认用域名');
      expect(item.bundled, isFalse);
    });

    testWidgets('扫码得到安装码：下载校验 → 权限确认 → 入列', (tester) async {
      final dir = Directory.systemTemp.createTempSync('scan_ext_page_');
      final savedDocs = ExtensionStore.documentsDirectory;
      ExtensionStore.documentsDirectory = () async => dir.path;
      addTearDown(() {
        ExtensionStore.documentsDirectory = savedDocs;
        ScannedBundleInstaller.debugDownload = null;
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final bytes = _makeZip({
        'ext.json': '{"id":"sit.qr-ui","name":"扫码拓展","desc":"扫码装的",'
            '"version":"2.0.0","main":"main.js","permissions":["notification"]}',
        'main.js': 'export default { apply(ctx) { ctx.ui.root.textContent = "hi" } }',
      });
      ScannedBundleInstaller.debugDownload = (_) async => bytes;
      final raw = jsonEncode({
        'antisit': 'ext',
        'url': 'https://example.com/sit.qr-ui.zip',
        'sha256': sha256.convert(bytes).toString(),
      });
      await pumpExtWith(tester, ScanPage.extensionOutcome(raw));

      await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
      await tester.pumpAndSettle();

      expect(find.text('安装「扫码拓展」？'), findsOneWidget);
      expect(find.textContaining('给你发通知'), findsOneWidget, reason: '敏感权限要列给用户');
      await tester.tap(find.text('安装'));
      await tester.pumpAndSettle();

      final item = ExtensionStore.I.items.single;
      expect(item.id, 'sit.qr-ui');
      expect(item.version, '2.0.0');
      expect(item.bundled, isTrue);
      expect(File(item.url).existsSync(), isTrue);
    });
  });
}

List<int> _makeZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

class _OutcomeScanCapability extends ScanCapability {
  const _OutcomeScanCapability(this.outcome);

  final ScanOutcome? outcome;

  @override
  Future<ScanOutcome?> open(BuildContext context,
          {ScanMode mode = ScanMode.generic}) async =>
      outcome;
}

/// 扫一扫替身：推一页带标志文本的页面，证明入口真的打开了扫码功能，不把真 ScanPage 拖进来。
class _StubScanCapability extends ScanCapability {
  const _StubScanCapability();

  @override
  Future<ScanOutcome?> open(BuildContext context,
          {ScanMode mode = ScanMode.generic}) =>
      Navigator.of(context).push<ScanOutcome>(
        MaterialPageRoute<ScanOutcome>(
            builder: (_) => const Scaffold(
                body: Center(child: Text('扫码页替身')))),
      );
}

/// WebView 内核替身：只记录 openPage 收到的网址，不真的建 WebView。
class _FakeWebViewCapability extends WebViewCapability {
  _FakeWebViewCapability(this.onOpen);

  final void Function(String? url) onOpen;

  @override
  bool get available => true;

  @override
  Widget view({String? url, String? html}) => const SizedBox.shrink();

  @override
  Future<void> openPage(BuildContext context,
      {String? url, String? html, String title = '', WebBridge? bridge}) async {
    onOpen(url);
  }
}
