import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'extensions/harness.dart';

/// 融合门户这类「只有校内网能打开」的网页拓展：服务器模式必须把 WebView 的
/// 流量指到校园隧道代理上，否则手机在外网只能看到一个加载失败页。
class _RecordingKernel extends WebViewCapability {
  _RecordingKernel();

  final List<String?> urls = <String?>[];
  final List<String> proxies = <String>[];

  @override
  bool get available => true;

  @override
  Widget view({String? url, String? html}) => const SizedBox.shrink();

  @override
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
    WebBridge? bridge,
    String proxy = '',
  }) async {
    urls.add(url);
    proxies.add(proxy);
  }
}

void main() {
  setUpExtensionEnv();
  setUp(() {
    campusProxyRetryDelay = Duration.zero;
    // 默认当公网：真查 DNS 会让用例依赖网络
    campusHostLookup = (host) async => [InternetAddress('203.0.113.9')];
  });
  tearDown(() {
    resetCampusProxyProbe();
    AppState.I.mode = AppMode.server;
    AppState.I.serverUrl = '';
  });

  ExtensionItem portal({
    List<String> permissions = const ['network', 'campus_net'],
  }) => ExtensionItem(
    id: 'sit.portal',
    name: 'SIT融合门户',
    url: 'https://portal.sit.edu.cn/',
    desc: '学校融合门户',
    permissions: permissions,
    fromMarket: true,
  );

  Future<void> open(
    WidgetTester tester,
    ExtensionItem item,
    List<String> said,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openExtension(context, item, onMessage: said.add),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('服务器模式：校内网页经校园隧道代理打开', (tester) async {
    final kernel = _RecordingKernel();
    PluginRegistry.I = PluginRegistry(
      features: const [ExtPlugin(), WebViewPlugin()],
      themes: const [GlassTheme()],
      capabilities: {PluginIds.webview: kernel},
    );
    AppState.I.mode = AppMode.server;
    AppState.I.serverUrl = 'https://anticraft.top';
    campusProxyProbe = () async => 'http://anticraft.top:10004';

    final said = <String>[];
    await open(tester, portal(), said);

    expect(kernel.urls, ['https://portal.sit.edu.cn/']);
    expect(kernel.proxies, [
      'http://anticraft.top:10004',
    ], reason: '融合门户在内网，服务器模式下必须走校园隧道出去');
    expect(said, isEmpty, reason: '代理拿到了，不该再提示「只有校内网能打开」');
  });

  testWidgets('直连模式：本机就在校内网，直接加载不带代理', (tester) async {
    final kernel = _RecordingKernel();
    PluginRegistry.I = PluginRegistry(
      features: const [ExtPlugin(), WebViewPlugin()],
      themes: const [GlassTheme()],
      capabilities: {PluginIds.webview: kernel},
    );
    AppState.I.mode = AppMode.direct;
    var probed = 0;
    campusProxyProbe = () async {
      probed++;
      return 'http://anticraft.top:10004';
    };

    final said = <String>[];
    await open(tester, portal(), said);

    expect(kernel.proxies, [''], reason: '直连模式不该碰隧道代理');
    expect(probed, 0);
    expect(said, isEmpty);
  });

  testWidgets('隧道一直没连上：按直连打开并提示先连校园网', (tester) async {
    final kernel = _RecordingKernel();
    PluginRegistry.I = PluginRegistry(
      features: const [ExtPlugin(), WebViewPlugin()],
      themes: const [GlassTheme()],
      capabilities: {PluginIds.webview: kernel},
    );
    AppState.I.mode = AppMode.server;
    AppState.I.serverUrl = 'https://anticraft.top';
    campusProxyProbe = () async => '';

    final said = <String>[];
    await open(tester, portal(), said);

    expect(kernel.proxies, ['']);
    expect(said.single, contains('校园'), reason: '没代理要让用户知道为什么打不开');
  });

  testWidgets('公网网页（没声明 campus_net）：不探测代理，也不提示', (tester) async {
    final kernel = _RecordingKernel();
    PluginRegistry.I = PluginRegistry(
      features: const [ExtPlugin(), WebViewPlugin()],
      themes: const [GlassTheme()],
      capabilities: {PluginIds.webview: kernel},
    );
    AppState.I.mode = AppMode.server;
    AppState.I.serverUrl = 'https://anticraft.top';
    var probed = 0;
    campusProxyProbe = () async {
      probed++;
      return 'http://anticraft.top:10004';
    };

    final said = <String>[];
    await open(
      tester,
      ExtensionItem(
        id: 'sit.campus-map',
        name: 'SIT校园地图',
        url: 'https://www.sitmc.club/pixelsit/',
        desc: '校园地图',
        permissions: const ['network'],
        fromMarket: true,
      ),
      said,
    );

    expect(probed, 0, reason: '公网站点不需要校园隧道，别白等');
    expect(kernel.proxies, ['']);
    expect(said, isEmpty);
  });

  testWidgets('没声明 campus_net 但域名解析到内网：也走隧道', (tester) async {
    // 存量用户装的是「只有 network」的旧条目：靠 DNS 判出来，不必等作者发新版
    final kernel = _RecordingKernel();
    PluginRegistry.I = PluginRegistry(
      features: const [ExtPlugin(), WebViewPlugin()],
      themes: const [GlassTheme()],
      capabilities: {PluginIds.webview: kernel},
    );
    AppState.I.mode = AppMode.server;
    AppState.I.serverUrl = 'https://anticraft.top';
    campusProxyProbe = () async => 'http://anticraft.top:10004';
    campusHostLookup = (host) async => [
      InternetAddress('172.24.9.115'),
      InternetAddress('210.35.96.2'),
    ];

    final said = <String>[];
    await open(tester, portal(permissions: const ['network']), said);

    expect(kernel.proxies, [
      'http://anticraft.top:10004',
    ], reason: '融合门户解析到 172.24.x，服务器模式下必须走隧道');
    expect(said, isEmpty);
  });

  test('内网判定的网段边界', () {
    expect(isPrivateAddress(InternetAddress('10.1.2.3')), isTrue);
    expect(isPrivateAddress(InternetAddress('172.16.0.1')), isTrue);
    expect(isPrivateAddress(InternetAddress('172.24.9.115')), isTrue);
    expect(isPrivateAddress(InternetAddress('172.31.255.254')), isTrue);
    // 172.32 与 172.15 已经出了 172.16/12
    expect(isPrivateAddress(InternetAddress('172.32.0.1')), isFalse);
    expect(isPrivateAddress(InternetAddress('172.15.0.1')), isFalse);
    expect(isPrivateAddress(InternetAddress('192.168.1.10')), isTrue);
    expect(isPrivateAddress(InternetAddress('192.169.1.10')), isFalse);
    expect(isPrivateAddress(InternetAddress('210.35.96.2')), isFalse);
    expect(isPrivateAddress(InternetAddress('fd00::1')), isTrue);
    expect(isPrivateAddress(InternetAddress('2001:da8::1')), isFalse);
  });
}
