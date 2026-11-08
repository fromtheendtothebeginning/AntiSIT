import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_camera/plugin_camera.dart';
import 'package:plugin_scan/plugin_scan.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 摄像头插件与扫一扫插件的接线验收：
/// * 两个插件是独立的包：扫一扫硬依赖摄像头（停用摄像头会连带停用扫一扫）；
/// * 扫码页只认 [CameraCapability]：换掉能力实现（测试替身）照样能取景识码，
///   说明页面不再直接碰 `mobile_scanner`；
/// * 能力缺席时页面给出启用提示，不开天窗。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() => PluginRegistry.I = PluginRegistry());

  test('扫一扫硬依赖摄像头；停用摄像头会连带停用扫一扫', () async {
    final r = PluginRegistry(features: const [CameraPlugin(), ScanPlugin()]);
    expect(r.disableClosure(PluginIds.camera), contains(PluginIds.scan));

    await r.disable(PluginIds.camera);
    expect(r.isEnabled(PluginIds.camera), isFalse);
    expect(r.isEnabled(PluginIds.scan), isFalse, reason: '硬依赖被停用，扫码一起停');

    await r.enable(PluginIds.scan);
    expect(r.isEnabled(PluginIds.camera), isTrue, reason: '启用扫码会连带打开摄像头');
  });

  testWidgets('扫码页从摄像头能力取景：识码回调直接进入扫码流程', (tester) async {
    final session = _FakeCameraSession();
    PluginRegistry.I = PluginRegistry(
      features: const [CameraPlugin(), ScanPlugin()],
      themes: const [GlassTheme()],
      capabilities: {
        PluginIds.camera: _FakeCameraCapability(session),
        PluginIds.scan: const ScanCapabilityImpl(),
      },
    );

    await tester.pumpWidget(const MaterialApp(home: ScanPage()));
    await tester.pumpAndSettle();

    expect(find.text('假取景'), findsOneWidget, reason: '取景画面来自能力实现');
    await tester.tap(find.text('假取景'));
    await tester.pumpAndSettle();

    expect(find.text('扫码结果'), findsOneWidget);
    expect(find.text('hello-camera'), findsOneWidget);
  });

  testWidgets('摄像头能力不可用：页面给出启用提示', (tester) async {
    PluginRegistry.I = PluginRegistry(
      features: const [ScanPlugin()],
      themes: const [GlassTheme()],
    );

    await tester.pumpWidget(const MaterialApp(home: ScanPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('摄像头不可用'), findsOneWidget);
    expect(find.text('相册识别'), findsNothing, reason: '没有摄像头能力时底部按钮也不给');
  });
}

/// 摄像头能力替身：不碰平台通道，取景画面点一下就「识出」一枚码。
class _FakeCameraCapability extends CameraCapability {
  const _FakeCameraCapability(this.session);

  final _FakeCameraSession session;

  @override
  bool get available => true;

  @override
  CameraSession openSession({
    required ValueChanged<String> onDetected,
    Widget Function(CameraFailure failure)? errorBuilder,
  }) {
    session.onDetected = onDetected;
    return session;
  }
}

class _FakeCameraSession implements CameraSession {
  ValueChanged<String>? onDetected;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: ElevatedButton(
          onPressed: () => onDetected?.call('hello-camera'),
          child: const Text('假取景'),
        ),
      );

  @override
  Future<bool> toggleTorch() async => false;

  @override
  Future<String?> pickImage() async => null;

  @override
  Future<List<String>> scanImage(String path) async => const [];

  @override
  Future<void> dispose() async {}
}
