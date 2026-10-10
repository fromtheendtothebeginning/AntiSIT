import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「外观」滑块拖到中间时整站配色怎么渐变：
/// 位置 → 深浅程度（[appearanceDarkness]）→ 色板差值（[GlassPalette.lerp]）。
void main() {
  group('外观滑块位置 → 该暗到什么程度', () {
    test('两个端点档位：浅色=0、深色=1', () {
      expect(appearanceDarkness(1, systemDark: false), 0);
      expect(appearanceDarkness(1, systemDark: true), 0, reason: '浅色档与系统无关');
      expect(appearanceDarkness(2, systemDark: false), 1);
      expect(appearanceDarkness(2, systemDark: true), 1);
    });

    test('「跟随系统」那端取系统的实际深浅', () {
      expect(appearanceDarkness(0, systemDark: false), 0);
      expect(appearanceDarkness(0, systemDark: true), 1);
    });

    test('中间段线性插值（拖到 1.5 = 浅深各一半）', () {
      expect(appearanceDarkness(1.5, systemDark: false), closeTo(0.5, 1e-9));
      expect(appearanceDarkness(1.25, systemDark: false), closeTo(0.25, 1e-9));
      // 系统是深色时，从「跟随系统」到「浅色」这一段就是在往回变浅
      expect(appearanceDarkness(0.5, systemDark: true), closeTo(0.5, 1e-9));
      expect(appearanceDarkness(0.5, systemDark: false), 0);
    });

    test('超出范围也夹在 0..1', () {
      expect(appearanceDarkness(-3, systemDark: true), 1);
      expect(appearanceDarkness(9, systemDark: false), 1);
    });
  });

  group('色板差值', () {
    final light = GlassPalette.light;
    final dark = GlassPalette.dark;

    test('两端点取原色板（不做多余的舍入）', () {
      expect(identical(GlassPalette.lerp(light, dark, 0), light), isTrue);
      expect(identical(GlassPalette.lerp(light, dark, 1), dark), isTrue);
    });

    test('中间值为两档的线性混合（含 alpha）', () {
      final mid = GlassPalette.lerp(light, dark, 0.5);
      expect(mid.bg, Color.lerp(light.bg, dark.bg, 0.5));
      expect(mid.textPrimary, Color.lerp(light.textPrimary, dark.textPrimary, 0.5));
      expect(mid.card, Color.lerp(light.card, dark.card, 0.5));
      // 卡面是半透明白：混出来也该是半透明，且夹在两者之间
      final a = light.card.a;
      final b = dark.card.a;
      expect(mid.card.a, closeTo((a + b) / 2, 0.005));
      expect(mid.isDark, dark.isDark, reason: '过半就算深色（状态栏图标/光斑按它选）');
      expect(GlassPalette.lerp(light, dark, 0.4).isDark, light.isDark);
    });
  });

  group('外观控件把连续位置交出来', () {
    testWidgets('拖动中写中间值，松手落到整档', (tester) async {
      final pos = ValueNotifier<double>(1);
      addTearDown(pos.dispose);
      var picked = -1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: GlassTabs(
                labels: const ['跟随系统', '浅色', '深色'],
                index: 1,
                position: pos,
                onChanged: (i) => picked = i,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(pos.value, 1, reason: '初始位置 = 当前档');

      // 从「浅色」往「深色」拖过半段
      final center = tester.getCenter(find.text('浅色'));
      final g = await tester.startGesture(center);
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(pos.value, greaterThan(1.05), reason: '拖动中写的是连续位置');
      expect(pos.value, lessThan(1.95), reason: '还没到整档');
      expect(picked, -1, reason: '拖动中不提交，落格才提交');

      await g.up();
      await tester.pumpAndSettle();
      // 落点由弹簧 + 甩动动量决定（测试里一步位移的速度估计很大，会多滑一格），
      // 这里钉的是「位置收敛到整档、提交的档位与落点一致」这条不变量。
      expect(pos.value, closeTo(pos.value.roundToDouble(), 0.01), reason: '松手后落在整档');
      expect(picked, pos.value.round(), reason: '提交的档位 = 落点');
    });
  });

  group('预览值量化（整站重建要省着来）', () {
    setUp(() => AppState.I.appearancePreviewDark = null);

    test('5% 一步：小抖动不触发，跨档才更新', () {
      var notified = 0;
      void onChanged() => notified++;
      AppState.I.addListener(onChanged);
      addTearDown(() => AppState.I.removeListener(onChanged));

      AppState.I.setAppearancePreview(0.52);
      expect(AppState.I.appearancePreviewDark, 0.5);
      expect(notified, 1);

      AppState.I.setAppearancePreview(0.53);
      expect(AppState.I.appearancePreviewDark, 0.55);
      expect(notified, 2);

      AppState.I.setAppearancePreview(0.54); // 还是 0.55
      expect(notified, 2, reason: '同一个量化档不重复通知');

      AppState.I.setAppearancePreview(null);
      expect(AppState.I.appearancePreviewDark, isNull);
      expect(notified, 3);
      AppState.I.setAppearancePreview(null); // 已经是 null
      expect(notified, 3, reason: '没变化就不通知');
    });
  });
}
