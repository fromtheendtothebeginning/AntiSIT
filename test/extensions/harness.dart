import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:campus_core/campus_core.dart';
export 'package:plugin_ext/plugin_ext.dart';
export 'package:plugin_theme_glass/plugin_theme_glass.dart' hide pluginBundle;
export 'package:plugin_webview/plugin_webview.dart' hide pluginBundle;

// 拓展相关测试共用的夹具：环境、页面泵、造包工具，以及桥 / 通知 / AI 的假实现。

/// 弹窗里的输入框（「添加拓展」页自带市场搜索框，不能再按类型找全部 TextField）。
Finder dialogFields() =>
    find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));

/// 每个用例的环境：内存存档 + 干净的单例 + 只装 WebView 内核与拓展的注册表。
void setUpExtensionEnv() {
  // 有 testWidgets 的文件本来就会在声明期装好绑定；Cordis 页面要读 asset，纯 test 文件也得先装。
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    SiteIcon.loader = SiteIcon.forPage;
    SiteIcon.clearCache();
    PluginRegistry.I = PluginRegistry(
      features: const [WebViewPlugin(), ExtPlugin()],
      themes: const [GlassTheme()],
      capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
    );
  });
}

Future<void> pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
  await tester.pumpAndSettle();
}

/// 现造一个 zip（压缩包导入的测试用）。
List<int> makeZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

/// 造一个「只有一帧、那一帧是 PNG」的 ICO。
Uint8List icoWithFrame(Uint8List frame) {
  final out = BytesBuilder()
    ..add(const [0, 0, 1, 0, 1, 0]) // ICONDIR：1 帧
    ..add(const [32, 32, 0, 0, 1, 0, 32, 0]); // 宽 32 高 32、32bpp
  final size = frame.length;
  final offset = 6 + 16;
  out
    ..add([
      size & 0xff,
      (size >> 8) & 0xff,
      (size >> 16) & 0xff,
      (size >> 24) & 0xff,
    ])
    ..add([
      offset & 0xff,
      (offset >> 8) & 0xff,
      (offset >> 16) & 0xff,
      (offset >> 24) & 0xff,
    ])
    ..add(frame);
  return out.takeBytes();
}

/// 1×1 的透明 PNG（真的能解码，用来验渲染）。
Uint8List fakePng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 测试用通知实现：只记录调用，不碰系统通知。
class FakeNotifier implements ExtNotificationService {
  final List<String> calls = <String>[];
  String? extId;
  String? key;
  String? title;
  String? body;
  DateTime? at;
  bool popup = false;

  void _record(String extId, String? key, String? title, String? body) {
    this.extId = extId;
    this.key = key;
    this.title = title;
    this.body = body;
  }

  @override
  Future<void> show({
    required String extId,
    String? extName,
    String? key,
    required String title,
    String? body,
    bool popup = false,
  }) async {
    calls.add('show');
    this.popup = popup;
    _record(extId, key, title, body);
  }

  @override
  Future<void> schedule({
    required String extId,
    required String key,
    required String title,
    String? body,
    required DateTime at,
    bool popup = false,
  }) async {
    calls.add('schedule');
    this.popup = popup;
    _record(extId, key, title, body);
    this.at = at;
  }

  @override
  Future<void> cancel({required String extId, required String key}) async {
    calls.add('cancel');
    this.extId = extId;
    this.key = key;
  }

  @override
  Future<void> cancelAll({required String extId}) async {
    calls.add('cancelAll');
    this.extId = extId;
  }

  @override
  void watchForeground() {}
}

/// 市场装的拓展条目（桥的权限门用例用）。
ExtensionItem marketExtItem({List<String> permissions = const []}) =>
    ExtensionItem(
      id: 'sit.ai-demo',
      name: 'AI 小助手',
      url: '/data/ext/sit.ai-demo/index.html',
      bundled: true,
      version: '1.0.0',
      sha256: 'a' * 64,
      permissions: permissions,
      fromMarket: true,
    );

/// 测试用 AI 功能插件：只为了让注册表里存在 PluginIds.ai（capability 查询要求已启用）。
class FakeAiPlugin extends FeaturePlugin {
  FakeAiPlugin(this.capability);

  final AiCapability capability;

  @override
  String get id => PluginIds.ai;
  @override
  String get name => 'AI（测试）';
  @override
  String get description => '测试用 AI 能力提供方';
}

/// 记录 ai.chat 收到什么、返回什么（桥的单测用）。
class FakeAiCapability implements AiCapability {
  @override
  bool available = true;
  int calls = 0;
  String? lastPrompt;
  String? lastSystem;
  int? lastMaxTokens;

  int chatToolsCalls = 0;
  int chatToolsStreamCalls = 0;
  List<AiChatMessage>? lastMessages;
  List<AiToolSpec>? lastTools;
  int? lastChatToolsMaxTokens;
  AiChatReply chatToolsReply = const AiChatReply(text: '好的');

  @override
  Future<void> load() async {}

  @override
  String get providerLabel => '测试提供商';
  @override
  String get providerId => 'fake';

  @override
  Future<String?> solveCaptcha(Uint8List image) async => null;

  @override
  Future<List<HolidayRule>> parseHolidayImage(
    Uint8List image, {
    required String startDate,
    required int weekCount,
    String mime = 'image/png',
  }) async => const [];

  @override
  Future<String> chat(String prompt, {String? system, int? maxTokens}) async {
    calls++;
    lastPrompt = prompt;
    lastSystem = system;
    lastMaxTokens = maxTokens;
    return '好的';
  }

  @override
  Future<AiChatReply> chatWithTools(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int? maxTokens,
  }) async {
    chatToolsCalls++;
    lastMessages = messages;
    lastTools = tools;
    lastChatToolsMaxTokens = maxTokens;
    return chatToolsReply;
  }

  @override
  Future<AiChatReply> chatWithToolsStream(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int? maxTokens,
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  }) async {
    chatToolsStreamCalls++;
    lastMessages = messages;
    lastTools = tools;
    lastChatToolsMaxTokens = maxTokens;
    if (chatToolsReply.reasoning.isNotEmpty) {
      onReasoning?.call(chatToolsReply.reasoning);
    }
    if (chatToolsReply.text.isNotEmpty) onText?.call(chatToolsReply.text);
    return chatToolsReply;
  }
}

/// 记录桥推给网页的下行事件（流式 AI 增量）。
class RecordingSink implements WebBridgeEventSink {
  final events = <(String, Object?)>[];

  @override
  void emit(String event, Object? data) => events.add((event, data));
}
