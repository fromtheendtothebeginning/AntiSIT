import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_tools/plugin_tools.dart';

/// 工具页顶栏的二维码入口：与二课活动页同一个「扫一扫能力」，插件停用时不显示。
void main() {
  testWidgets('扫一扫插件在 → 顶栏有二维码按钮，点开就是扫码页', (tester) async {
    final opened = <String>[];
    PluginRegistry.I = PluginRegistry(
      features: const [_FakeScanPlugin()],
      capabilities: {PluginIds.scan: _RecordingScan(opened)},
    );
    addTearDown(() => PluginRegistry.I = PluginRegistry());

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ToolsPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.qr_code_scanner_outlined));
    await tester.pumpAndSettle();
    expect(opened, ['open'], reason: '按钮应当调起扫一扫能力');
  });
}

/// 只提供扫码能力的假插件（工具页按能力取用，不 import 扫一扫的包）。
class _FakeScanPlugin extends FeaturePlugin {
  const _FakeScanPlugin();

  @override
  String get id => PluginIds.scan;
  @override
  String get name => '扫一扫';
  @override
  String get description => '测试用';
}

class _RecordingScan extends ScanCapability {
  _RecordingScan(this.calls);

  final List<String> calls;

  @override
  Future<ScanOutcome?> open(
    BuildContext context, {
    ScanMode mode = ScanMode.generic,
  }) async {
    calls.add('open');
    return null;
  }
}