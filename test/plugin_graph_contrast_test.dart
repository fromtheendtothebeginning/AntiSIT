import 'dart:math' as math;

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/plugin_manager_page.dart';
import 'package:campus_service/widgets/plugin_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// bug 回归：深色模式下依赖关系图看不清。
/// 起因是节点底色写成 `card.withValues(alpha: 0.92)`——card 自带透明度（深色白 8%），
/// withValues 把它覆盖成 92%，节点被刷成近白色，而节点文字是 textPrimary（深色下白 95%），
/// 于是白底白字。这里用真实渲染出来的节点/画布颜色钉住对比度。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PluginRegistry.I = PluginRegistry(
      features: const [_Node('lib'), _Node('app', deps: ['lib'])],
      themes: const [GlassTheme()],
    );
  });

  /// WCAG 对比度
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  for (final dark in [true, false]) {
    final mode = dark ? '深色' : '浅色';

    testWidgets('$mode模式：节点文字在节点底色上读得清，且节点浮在画布上', (tester) async {
      SemColors.p = dark ? GlassPalette.dark : GlassPalette.light;
      addTearDown(() => SemColors.p = GlassPalette.light);
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PluginManagerPage()));
      await tester.pumpAndSettle();

      // 画布（内凹的井）
      final canvasBox = tester.widget<Container>(find
          .ancestor(of: find.byType(PluginGraphView), matching: find.byType(Container))
          .first);
      final canvas = canvasBox.color!;

      // 节点（关系图里的那个「插件app」，不是下面列表里同名的行）
      final label = find.text('插件app').first;
      final nodeText = tester.widget<Text>(label);
      final nodeBox = tester.widget<Container>(
          find.ancestor(of: label, matching: find.byType(Container)).first);
      final fill = (nodeBox.decoration! as BoxDecoration).color!;

      expect(contrast(nodeText.style!.color!, fill), greaterThan(4.5),
          reason: '$mode：节点文字与节点底色对比不足（深色下曾是白底白字）');
      expect(fill.computeLuminance(), greaterThan(canvas.computeLuminance()),
          reason: '$mode：节点要浮在画布上');
      if (dark) {
        expect(contrast(fill, canvas), greaterThan(1.15),
            reason: '深色下节点与画布几乎同色，就看不出节点边界了');
      }
    });
  }
}

class _Node extends FeaturePlugin {
  const _Node(this.id, {this.deps = const []});

  @override
  final String id;
  final List<String> deps;

  @override
  String get name => '插件$id';
  @override
  String get description => '测试插件';
  @override
  List<String> get dependencies => deps;
}
