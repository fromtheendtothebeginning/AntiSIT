import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 组 1（顶栏适配）的回归测试。
///
/// * #10 悬浮切换器收起后不能画到顶栏上面——关掉悬浮顶栏时（切换器自己只有 48 高）
///   以前只上移约 50px，正好停在状态栏 + 标题栏那一条里，浮在标题上；
/// * #14 下拉刷新圈从顶栏底边开始，而不是屏幕最上沿；
/// * #12 拓展页的顶栏留白要随「悬浮玻璃顶栏」开关重算；
/// * #15 评教表单的内容要穿过顶栏（留白在列表 padding 里，不是外层 Padding）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    PluginRegistry.I = PluginRegistry(
      features: const [WebViewPlugin(), ExtPlugin()],
      themes: const [GlassTheme()],
      capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
    );
    addTearDown(() => AppState.I.glassTopBar = true);
  });

  /// 切换器 + 够长可滚的内容。header 用纯红，方便按像素查「有没有画到顶栏区」。
  Widget tabsHost({required double topInset}) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('标题')),
      body: FloatingTabsHeader(
        topInset: topInset,
        header: const SizedBox(
          height: 32,
          child: ColoredBox(color: Color(0xFFFF0000)),
        ),
        child: ListView(
          padding: EdgeInsets.only(top: topInset),
          children: const [SizedBox(height: 4000, child: Text('内容'))],
        ),
      ),
    ),
  );

  /// 往上滚一大段，把切换器收起来。
  Future<void> collapse(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
  }

  /// 取整屏像素：返回 (width, data)。
  Future<(int, ByteData)> grab(WidgetTester tester, GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    return (boundary.size.width.round(), bytes!);
  }

  group('#10 切换器收起后不越界到顶栏', () {
    testWidgets('收起时整块移出自己那格，且靠外层 ClipRect 裁住', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(tabsHost(topInset: 0));
      await tester.pumpAndSettle();
      await collapse(tester);

      final slide = tester.widget<AnimatedSlide>(
        find.byType(AnimatedSlide).first,
      );
      expect(slide.offset.dy, lessThan(-1.0), reason: '收起要整块移出自身盒子');
      // 位移是相对自身高度的比例，而**关掉顶栏后自身只剩 48 高**：48×1.05 ≈ 50px，
      // 只够把自己那点盒子推出可视区一点点。位移发生在 paint 期，Stack 的
      // clipBehavior 管不住它，必须靠外层这层 ClipRect（issue #10 的根因）。
      expect(
        find.ancestor(
          of: find.byType(AnimatedSlide).first,
          matching: find.byType(ClipRect),
        ),
        findsOneWidget,
        reason: '收起依赖 paint 期位移，外层必须有 ClipRect 才裁得住',
      );
    });

    testWidgets('关掉悬浮顶栏（topInset=0）：收起后顶栏区没有药丸像素', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: tabsHost(topInset: 0)),
      );
      await tester.pumpAndSettle();
      await collapse(tester);

      final (w, bytes) = await grab(tester, key);
      // 药丸是纯红：红通道远高于绿/蓝。顶栏底色是浅色、标题文字是深灰——
      // 两者都「红≈绿」，只有药丸（以及它扫过的红块）满足红占优。
      int pillPixels() {
        var n = 0;
        for (var y = 0; y < kToolbarHeight; y += 2) {
          for (var x = 0; x < w; x += 2) {
            final o = (y * w + x) * 4;
            final r = bytes.getUint8(o);
            final g = bytes.getUint8(o + 1);
            if (r > 140 && r - g > 120) n++;
          }
        }
        return n;
      }

      expect(pillPixels(), 0, reason: '顶栏区画出了红色切换器：收起时没被裁掉');
    });

    testWidgets('开着悬浮顶栏时：展开可见、收起后顶栏区干净', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: tabsHost(topInset: 80)),
      );
      await tester.pumpAndSettle();

      // 展开：药丸贴在顶栏（80）下沿
      expect(
        tester.getRect(find.byType(BackdropFilter)).top,
        greaterThanOrEqualTo(80 - 0.5),
        reason: '展开时贴在顶栏下沿',
      );
      final (w, before) = await grab(tester, key);
      int pillPixels(ByteData b) {
        var n = 0;
        for (var y = 0; y < kToolbarHeight; y += 2) {
          for (var x = 0; x < w; x += 2) {
            final o = (y * w + x) * 4;
            final r = b.getUint8(o);
            final g = b.getUint8(o + 1);
            if (r > 140 && r - g > 120) n++;
          }
        }
        return n;
      }

      // 展开态药丸在 80 以下，顶栏区不该有它（基准）
      expect(pillPixels(before), 0);

      await collapse(tester);
      final (_, after) = await grab(tester, key);
      expect(pillPixels(after), 0, reason: '收起后顶栏区不能有药丸');
    });
  });

  group('#14 下拉刷新圈从顶栏底边开始', () {
    testWidgets('RefreshIndicator 的 edgeOffset = glassTopInset', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(viewPadding: EdgeInsets.only(top: 24)),
            child: Builder(
              builder: (context) {
                final topInset = glassTopInset(context);
                return Scaffold(
                  extendBodyBehindAppBar: glassTopBarEnabled,
                  appBar: glassAppBar(context, title: const Text('标题')),
                  body: RefreshIndicator(
                    edgeOffset: topInset,
                    onRefresh: () async {},
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [SizedBox(height: 900)],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .edgeOffset,
        24 + kToolbarHeight,
      );
    });

    testWidgets('评教列表把顶栏留白同时交给列表 padding 与 edgeOffset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EvaluateListView(
              targets: const [],
              summary: const EvalSummary(),
              topPadding: 80,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .edgeOffset,
        80,
      );
      expect(
        (tester.widget<ListView>(find.byType(ListView)).padding as EdgeInsets)
            .top,
        88,
        reason: '列表顶部 = 8 基础间距 + 顶栏留白',
      );
    });
  });

  group('#15 评教表单内容穿过顶栏', () {
    test('表单列表的 padding 里含顶栏留白（不是外层 Padding 顶下来）', () {
      const inset = 24 + kToolbarHeight;
      expect(evaluateFormListPadding(inset).top, 8 + inset);
    });

    test('关掉悬浮顶栏时留白归零（普通 AppBar 自己占位）', () {
      expect(evaluateFormListPadding(0).top, 8);
    });
  });

  group('#12 拓展页留白跟随开关重算', () {
    testWidgets('切「悬浮玻璃顶栏」后拓展页顶部留白立刻重算', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(viewPadding: EdgeInsets.only(top: 24)),
            child: ExtensionsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double padTop() {
        final scroll = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        return (scroll.padding as EdgeInsets).top;
      }

      expect(
        padTop(),
        20 + 24 + kToolbarHeight,
        reason: '开了悬浮顶栏：内容要让出状态栏 + 标题栏',
      );

      // 走真实路径改开关并通知：以前 topInset 算在 builder 外面，
      // 通知只重建 builder、不重算留白，开关切换后留白仍是旧值（issue #12）。
      await AppState.I.setGlassTopBar(false);
      await tester.pumpAndSettle();
      expect(padTop(), 20, reason: '关掉悬浮顶栏后留白要归零');
    });
  });
}
