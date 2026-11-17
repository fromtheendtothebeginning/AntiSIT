import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// WebView 内核替身：只回答「在不在」，够 [EvaluatePlugin.tools] 判断用。
class _FakeKernel extends WebViewCapability {
  const _FakeKernel({required this.available});

  @override
  final bool available;

  @override
  Widget view({String? url, String? html}) => const SizedBox.shrink();

  @override
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
    WebBridge? bridge,
  }) async {}
}

/// 能力的提供方插件（[PluginRegistry.capability] 只对「已安装且已启用」的提供方返回）。
class _KernelOwner extends FeaturePlugin {
  const _KernelOwner();
  @override
  String get id => PluginIds.webview;
  @override
  String get name => 'WebView 内核';
  @override
  String get description => '测试替身';
}

/// 评教助手插件的接线：工具卡片只在「内核可用 + 非演示模式」时出现。
void main() {
  const plugin = EvaluatePlugin();

  setUp(() {
    AppState.I.demo = false;
    // 注入的脚本与消息通道名是约定的一部分，别让人改坏
    expect(kEvaluateChannel, 'antiSITEval');
    expect(evaluateInjectorJs(), contains("'antiSITEval'"));
    expect(evaluateInjectorJs(channel: 'x'), contains("'x'"));
    expect(evaluateApplyAllCall(5), contains('applyAll(5.0)'));
    expect(evaluateApplyOneCall(2, 3), contains('applyOne(2, 3.0)'));
  });

  test('硬依赖 WebView 内核（没有内核就没有可填的网页）', () {
    expect(plugin.dependencies, contains(PluginIds.webview));
    expect(plugin.id, 'evaluate');
    expect(plugin.navItems(PluginRegistry.I, ValueNotifier<int>(0)), isEmpty);
  });

  test('内核可用且非演示模式：工具宫格出现「学生评教」卡片', () {
    final registry = PluginRegistry(
      features: const [_KernelOwner()],
      capabilities: const {PluginIds.webview: _FakeKernel(available: true)},
    );
    final tools = plugin.tools(registry);
    expect(tools, hasLength(1));
    expect(tools.single.title, '学生评教');
    expect(tools.single.open(), isA<EvaluatePage>());
  });

  test('内核停用 / 平台不支持：入口直接不出现', () {
    expect(plugin.tools(PluginRegistry(features: const [])), isEmpty);
    final desktop = PluginRegistry(
      features: const [_KernelOwner()],
      capabilities: const {PluginIds.webview: _FakeKernel(available: false)},
    );
    expect(plugin.tools(desktop), isEmpty);
  });

  test('演示模式（本地假数据）不出现评教入口', () {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);
    final registry = PluginRegistry(
      features: const [_KernelOwner()],
      capabilities: const {PluginIds.webview: _FakeKernel(available: true)},
    );
    expect(plugin.tools(registry), isEmpty);
  });
}
