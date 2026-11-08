import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/scan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/plugin_activities.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「扫一扫」页与两处入口的验收：
/// * 扫码页：识码弹结果面板（复制 / 网址才给打开链接 / 继续扫回取景）；
/// * 相册识别：识出弹面板、没识出给一句提示、用户取消不吭声；
/// * 入口：第二课堂活动 / 拓展页右上角的镂空扫码图标，由宿主经
///   `hostOpenScanner` 反向注入——没注入（纯 core 环境）就不显示。
/// 相机用注入的替身（widget 测试没有平台通道），识码与入口接线才是主角。
void main() {
  String? clipboard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.I.demo = false;
    ScanPage.debugCamera = (context) => const ColoredBox(
        color: Colors.green, child: Center(child: Text('假相机')));
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
    // url_launcher 通道没人应答时 launchUrl 的 Future 永不完成——挂个必抛的 mock，
    // 让 openExternalUrl 稳定走「复制链接」兜底分支。
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
    hostOpenScanner = null;
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

      expect(find.textContaining('已复制下载链接'), findsOneWidget,
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

    test('服务器模式：提交经 /api/campus-open/activities/sign，参数透传', () async {
      // 真 HTTP 打本地假服务。不放 testWidgets：测试框架的假 HttpClient 会把所有
      // 请求拦成 400，普通 test 里才是真套接字（按钮 → 提交的接线已由上面的
      // debugSign 用例覆盖，这里只验证双模式路由）。
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = null);
      SharedPreferences.setMockInitialValues({});
      await AppState.I.load();
      AppState.I.demo = false;
      AppState.I.mode = AppMode.server;
      AppState.I.token = 'test-token';
      addTearDown(() {
        AppState.I.demo = false;
        AppState.I.mode = AppMode.direct;
      });

      String? path;
      Map<String, dynamic>? body;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      AppState.I.serverUrl = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        path = req.uri.path;
        body = jsonDecode(await utf8.decoder.bind(req).single);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'ok': true, 'data': {'msg': '签退成功'}}));
        await req.response.close();
      });

      final r = await ApiClient.I.activitySignInOrSignOut(
          '94b69a40f38eedd060cf9ecec1fe78cd', 'c4f2a32a171df39ee5ba8834c8a425ee');

      expect(path, '/api/campus-open/activities/sign');
      expect(body, {'hdId': '94b69a40f38eedd060cf9ecec1fe78cd', 'hdActId': 'c4f2a32a171df39ee5ba8834c8a425ee'});
      expect(r['data']['msg'], '签退成功');
    });
  });

  group('入口：右上角镂空扫码图标（宿主注入）', () {
    /// 宿主注入的替身：推一页带标志文本的页面，证明「点了真的进扫码页」，
    /// 不把真 ScanPage（相机平台通道）拖进 widget 测试。
    Future<void> Function(BuildContext) fakeHost() => (context) async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                  body: Center(child: Text('扫码页替身')))));
        };

    Future<void> pumpExt(WidgetTester tester) async {
      ExtensionStore.I = ExtensionStore();
      ExtensionStore.builtins = const [];
      MarketSource.I = MarketSource();
      // 市场目录不真发网络请求（失败即可，别让 loading 的不定动画卡住 settle）
      MarketSource.fetcher = (Uri url) => throw Exception('offline');
      PluginRegistry.I = PluginRegistry(
        features: const [WebViewPlugin(), ExtPlugin()],
        themes: const [GlassTheme()],
        capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
      );
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('拓展页右上角有扫一扫，点了进扫码页', (tester) async {
      hostOpenScanner = fakeHost();
      await pumpExt(tester);

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
      await tester.pumpAndSettle();

      expect(find.text('扫码页替身'), findsOneWidget, reason: '扫码页推入了');
    });

    testWidgets('宿主没注入扫码：拓展页不给入口（其余按钮照旧）', (tester) async {
      await pumpExt(tester);

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget, reason: '添加拓展按钮还在');
    });

    testWidgets('第二课堂活动页右上角有扫一扫', (tester) async {
      AppState.I.demo = true;
      addTearDown(() => AppState.I.demo = false);
      hostOpenScanner = fakeHost();

      await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
      await tester.pumpAndSettle();
      expect(find.text('扫码页替身'), findsOneWidget, reason: '扫码页推入了');
    });

    testWidgets('宿主没注入扫码：活动页不给入口', (tester) async {
      AppState.I.demo = true;
      addTearDown(() => AppState.I.demo = false);

      await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_scanner_outlined), findsNothing);
    });
  });
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
