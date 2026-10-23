import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/plugin_manager_page.dart';
import 'package:campus_service/plugins/bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「WebView 内核插件（默认开启）」的验收：
/// * defaultEnabled 机制：默认关闭的插件 isEnabled 为假，显式 enable 后才可用，
///   选择被持久化（重启读得回），disable 后回到默认关闭；
/// * 普通插件（默认启用）行为不变；
/// * 能力接线：内核默认可用，停用后查不到 WebViewCapability；
///   桌面测试环境（Windows）引擎 available == false；
/// * 真实注册表（buildAppRegistry）里带着 webview，默认开启；
/// * 硬依赖是默认关闭插件时，启用方会被 _repair 修掉。
class _Normal extends FeaturePlugin {
  const _Normal(this.id, {this.deps = const []});

  @override
  final String id;
  final List<String> deps;

  @override
  String get name => '插件$id';
  @override
  String get description => '说明 $id';
  @override
  List<String> get dependencies => deps;
}

/// 内核本身已随「拓展」默认开启，这里另造一个默认关闭的插件来验机制。
class _Off extends _Normal {
  const _Off(super.id);

  @override
  bool get defaultEnabled => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('defaultEnabled 机制', () {
    PluginRegistry reg() => PluginRegistry(
          features: const [
            _Off('off'), // 默认关闭
            _Normal('normal'), // 默认启用（对照组）
            _Normal('hardDependant', deps: ['off']), // 硬依赖默认关闭插件
          ],
          themes: const [GlassTheme()],
        );

    test('默认关闭：isEnabled 为假，enable 后可用并记入 userEnabled', () async {
      final r = reg();
      expect(r.isEnabled('off'), isFalse, reason: '默认关闭');
      expect(r.isDisabled('off'), isFalse, reason: '不是被停用，是默认关闭');

      final turned = await r.enable('off');
      expect(turned, contains('off'));
      expect(r.isEnabled('off'), isTrue);
      expect(r.enabled.map((p) => p.id), contains('off'));
    });

    test('disable 后回到默认关闭，userEnabled 存档被清掉', () async {
      final r = reg();
      await r.enable('off');
      await r.disable('off');
      expect(r.isEnabled('off'), isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getStringList('plugin_user_enabled') ?? const <String>[],
          isNot(contains('off')),
          reason: '用户关掉了就是回到默认态，不该留在显式打开名单里');
    });

    test('选择持久化：新注册表 load 后读得回', () async {
      final r = reg();
      await r.enable('off');
      final r2 = reg();
      await r2.load();
      expect(r2.isEnabled('off'), isTrue, reason: '用户打开过，重启仍开');
    });

    test('普通插件不受 defaultEnabled 影响：默认启用、disable 后关闭', () async {
      final r = reg();
      expect(r.isEnabled('normal'), isTrue);
      await r.disable('normal');
      expect(r.isEnabled('normal'), isFalse);
      final r2 = reg();
      await r2.load();
      expect(r2.isEnabled('normal'), isFalse, reason: '普通插件的停用照旧走 plugin_disabled');
    });

    test('enable 连带：启用依赖方会顺手打开默认关闭的硬依赖', () async {
      final r = reg();
      await r.load();
      expect(r.isEnabled('hardDependant'), isFalse,
          reason: '它硬依赖的 off 默认关闭，repair 会把它修掉');
      // 运行期直接启用：闭包连带打开 off（hardDependant 是普通插件、本来就算
      // 启用态，所以 turned 里只有 off）
      final turned = await r.enable('hardDependant');
      expect(turned, contains('off'),
          reason: '硬依赖是默认关闭插件时，启用方要连带把它打开');
      expect(r.isEnabled('hardDependant'), isTrue);
      expect(r.isEnabled('off'), isTrue);
    });
  });

  group('WebView 内核能力', () {
    PluginRegistry reg() => PluginRegistry(
          features: const [WebViewPlugin()],
          themes: const [GlassTheme()],
          capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
        );

    test('默认开启：能力直接可用（拓展默认就要用它）', () {
      final r = reg();
      final cap = r.capability<WebViewCapability>(PluginIds.webview);
      expect(cap, isNotNull);
      // CI / 开发机是 Windows，webview_flutter 不支持 → 内核自报不可用
      expect(cap!.available, isFalse);
    });

    test('停用后能力查不到（依赖它的拓展也会一起停）', () async {
      final r = reg();
      await r.disable(WebViewPlugin.pluginId);
      expect(r.capability<WebViewCapability>(PluginIds.webview), isNull);
    });

    test('真实注册表带着 webview 且默认开启', () {
      final r = buildAppRegistry();
      expect(r.byId(WebViewPlugin.pluginId), isNotNull);
      expect(r.byId(WebViewPlugin.pluginId)!.name, 'WebView 内核');
      expect(r.isEnabled(WebViewPlugin.pluginId), isTrue);
      expect(r.byId(WebViewPlugin.pluginId)!.removable, isTrue,
          reason: '用户可以自由开关它');
    });

    testWidgets('插件管理列表显示「WebView 内核」，开关默认开、可关闭', (tester) async {
      PluginRegistry.I = buildAppRegistry();
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PluginManagerPage()));
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'WebView 内核'));
      expect(tile.value, isTrue, reason: '默认开启');
      expect(tile.onChanged, isNotNull, reason: '用户可以关掉它');
    });
  });
}
