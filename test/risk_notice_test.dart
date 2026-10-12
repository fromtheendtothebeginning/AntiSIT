import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:campus_service/pages/plugin_manager_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ecard/plugin_ecard.dart';
import 'package:plugin_electricity/plugin_electricity.dart';
import 'package:plugin_risk/plugin_risk.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「风险提醒」组件（默认开启）的验收：
/// * 校园码：二维码区域换成引导（不显示付款码）、引导能跳插件管理；关掉后立刻恢复取码；
/// * 电费：点「充值」只弹提醒，不进金额输入；关掉后恢复；
/// * 关闭前必须过一遍条款：取消 = 不关，同意 = 才真的关。
void main() {
  /// 校园码页会给屏幕常亮加锁，测试环境没有平台实现，把通道应答成成功。
  const wakelockToggle =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = true; // 演示数据：页面能真的渲染出来，LoginGate 也放行
    // 宿主在 main() 里注入的「插件管理」页构建器，测试里补上（引导按钮要跳它）
    hostPluginManagerBuilder = () => const PluginManagerPage();
    PluginRegistry.I = PluginRegistry(
      features: const [EcardPlugin(), ElectricityPlugin(), RiskPlugin()],
      themes: const [GlassTheme()],
      capabilities: const {PluginIds.risk: RiskNoticeCapabilityImpl()},
    );
  });

  tearDown(() => AppState.I.demo = false);

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(wakelockToggle,
        (ByteData? _) async => const StandardMessageCodec().encodeMessage(<Object?>[null]));
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(GlassPalette.light), home: page));
    await tester.pumpAndSettle();
  }

  /// 页面常驻定时器，测试收尾要主动 dispose，否则报「Timer 还挂着」。
  Future<void> closePage(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  testWidgets('校园码：风险提醒开着时不给码，二维码区域给引导并能跳插件管理', (tester) async {
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isTrue, reason: '默认开启');
    await pumpPage(tester, const EcardPage());

    expect(find.text('「风险提醒」已开启'), findsOneWidget, reason: '二维码区域换成引导');
    expect(find.byType(QrPlate), findsNothing, reason: '不显示付款码（整块二维码区域都不给）');
    expect(find.textContaining('不会请求付款码'), findsOneWidget);

    await tester.tap(find.text('去插件管理关闭'));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget, reason: '引导要能跳到关闭入口');

    await closePage(tester);
  });

  testWidgets('校园码：关掉风险提醒立刻恢复取码，再开回来立刻重新拦住', (tester) async {
    await pumpPage(tester, const EcardPage());
    expect(find.byType(QrPlate), findsNothing);

    await PluginRegistry.I.disable(PluginIds.risk);
    await tester.pumpAndSettle();
    expect(find.text('「风险提醒」已开启'), findsNothing);
    expect(find.byType(QrPlate), findsOneWidget, reason: '放行后立即取码（演示数据有 code）');

    await PluginRegistry.I.enable(PluginIds.risk);
    await tester.pumpAndSettle();
    expect(find.text('「风险提醒」已开启'), findsOneWidget, reason: '再开回来立刻重新拦');
    expect(find.byType(QrPlate), findsNothing);

    await closePage(tester);
  });

  testWidgets('电费：风险提醒开着时点充值只弹提醒，关掉后恢复金额输入', (tester) async {
    await pumpPage(tester, const ElectricityPage());

    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();
    expect(find.text('操作已暂停'), findsOneWidget);
    expect(find.textContaining('宿舍电费充值已暂停'), findsOneWidget);
    expect(find.text('充值金额（元）'), findsNothing, reason: '被拦时不进充值流程');

    // 弹窗里的「去插件管理关闭」：先关弹窗再跳管理页
    await tester.tap(find.text('去插件管理关闭'));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await PluginRegistry.I.disable(PluginIds.risk);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();
    expect(find.text('充值金额（元）'), findsOneWidget, reason: '关掉风险提醒后充值恢复');

    await closePage(tester);
  });

  testWidgets('关掉风险提醒要先过条款：取消 = 不关，同意 = 才关', (tester) async {
    await pumpPage(tester, const PluginManagerPage());
    final tile = find.widgetWithText(SwitchListTile, '风险提醒');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue, reason: '默认开启');

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('风险提醒与免责声明'), findsOneWidget, reason: '关闭前先弹条款');
    expect(find.textContaining('由你自行承担'), findsWidgets, reason: '后果自负条款要在正文里');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isTrue, reason: '取消就不关');

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已阅读并同意，关闭风险提醒'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isFalse, reason: '同意后才真的关掉');
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '风险提醒'))
            .value,
        isFalse);

    await closePage(tester);
  });
}
