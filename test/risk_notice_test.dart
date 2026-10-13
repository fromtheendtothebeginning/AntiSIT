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

/// 「风险提醒」组件（默认启用）的验收：
/// * 校园码：二维码区域换成引导（不显示付款码）、引导能跳插件管理；停用后立刻恢复取码；
/// * 电费：点「充值」只弹提醒，不进金额输入；停用后恢复；
/// * 停用前必须过一遍条款：读完才能同意（取消 / 返回手势 = 未作出同意，组件维持启用）；
/// * 条款正文是法律条文形式（条 → 款 → 项，先定义后使用）；
/// * 卡片与页面的进出动画跟全站一致（AnimatedSize 高度过渡 / 普通路由）。
void main() {
  /// 校园码页会给屏幕常亮加锁，测试环境没有平台实现，把通道应答成成功。
  const wakelockToggle =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  /// 模拟系统返回手势（与 predictive_back_test 同一套通道手法）。
  Future<void> backGesture(WidgetTester tester, String method,
      [Map<String, Object?> args = const {}]) async {
    final message =
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/backgesture', message, (_) {});
    await tester.pump();
  }

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

  Future<void> pumpPage(WidgetTester tester, Widget page,
      {Size size = const Size(1080, 2200)}) async {
    tester.view.physicalSize = size;
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

  /// 中文数字 → 数字（够用到「二十」）。
  int cnNum(String s) {
    const digit = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9,
    };
    if (s == '十') return 10;
    if (s.startsWith('十')) return 10 + digit[s.substring(1)]!;
    if (s.contains('十')) {
      final p = s.split('十');
      return digit[p[0]]! * 10 + (p[1].isEmpty ? 0 : digit[p[1]]!);
    }
    return digit[s]!;
  }

  /// 某一条里（一）（二）… 的项编号（按出现顺序）。
  /// 只认行首的项标记——正文里的援引（「本条第（五）项」「第四条第（一）项」）不算项。
  List<int> itemsOf(String no) =>
      RegExp(r'^（([一二三四五六七八九十]+)）', multiLine: true)
          .allMatches(RiskTerms.clauses.firstWhere((c) => c.no == no).body)
          .map((m) => cnNum(m.group(1)!))
          .toList();

  String bodyOf(String no) => RiskTerms.clauses.firstWhere((c) => c.no == no).body;

  group('条款正文（法律条文形式）', () {
    test('条号从第一条起逐条加一，每条标题与正文都不为空', () {
      final nums = [
        for (final c in RiskTerms.clauses)
          cnNum(RegExp(r'^第([一二三四五六七八九十]+)条$').firstMatch(c.no)!.group(1)!),
      ];
      expect(nums, List.generate(RiskTerms.clauses.length, (i) => i + 1),
          reason: '条号连续，不能跳号');
      for (final c in RiskTerms.clauses) {
        expect(c.title.trim(), isNotEmpty);
        expect(c.body.trim(), isNotEmpty);
      }
    });

    test('第二条按（一）（二）… 连续分项，后文用到的名词都在这里定义过', () {
      final items = itemsOf('第二条');
      expect(items, List.generate(items.length, (i) => i + 1), reason: '定义项连续编号');
      expect(items.length, greaterThanOrEqualTo(15), reason: '先把要用的名词定义齐');
      final defined = bodyOf('第二条');
      for (final term in const [
        '本应用', '本组件', '用户', '付款码', '校园码付款码', '宿舍电费充值', '受拦截行为',
        '第三方', '校方', '非官方通道', '风险控制措施', '扣款', '到账', '后果', '用户数据',
        '启用', '停用', '开发者', '同意', '账号', '卡片', '账户', '余额', '账务记录',
      ]) {
        expect(defined, contains('「$term」'), reason: '「$term」必须先定义后使用');
      }
    });

    test('援引的条与项都真的存在（内容改了也不会留下悬空引用）', () {
      final all = RiskTerms.clauses.map((c) => c.body).join('\n');
      final nos = {for (final c in RiskTerms.clauses) c.no};
      for (final m in RegExp(r'第([一二三四五六七八九十]+)条').allMatches(all)) {
        expect(nos, contains('第${m.group(1)}条'), reason: '援引了不存在的条');
      }
      // 条款页横幅援引「第三条第（四）项」、拦截引导援引「第三条第（一）项」
      expect(itemsOf('第三条'), containsAll(<int>[1, 4]));
      // 第七条第（三）项援引第四条的前三项
      expect(itemsOf('第四条'), containsAll(<int>[1, 2, 3]));
    });

    test('不口语化：无第二 / 第一人称口语指代，无感叹与疑问', () {
      // 「我的」是底栏页面名（第八条里的查阅路径），不是第一人称用法，检查前先摘掉。
      final all = [
        RiskTerms.title,
        for (final c in RiskTerms.clauses) '${c.no}${c.title}${c.body}',
      ].join('\n').replaceAll('「我的 → 设置 → 风险提醒」', '（设置路径）');
      for (final bad in const ['你', '我', '！', '？', '没关系', '后果自负', '一下子']) {
        expect(all, isNot(contains(bad)), reason: '法律条文里不该出现「$bad」');
      }
    });
  });

  testWidgets('校园码：风险提醒启用时不给码，二维码区域给引导并能跳插件管理', (tester) async {
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isTrue, reason: '默认启用');
    await pumpPage(tester, const EcardPage());

    expect(find.text('风险提醒组件已启用'), findsOneWidget, reason: '二维码区域换成引导');
    expect(find.byType(QrPlate), findsNothing, reason: '不显示付款码（整块二维码区域都不给）');
    expect(find.textContaining('不请求付款码'), findsOneWidget);
    expect(find.text('校园码付款码'), findsOneWidget, reason: '点明被拦的是哪一项行为');

    await tester.tap(find.text('前往插件管理页停用'));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget, reason: '引导要能跳到停用入口');

    await closePage(tester);
  });

  testWidgets('校园码：停用风险提醒立刻恢复取码，再启用立刻重新拦住', (tester) async {
    await pumpPage(tester, const EcardPage());
    expect(find.byType(QrPlate), findsNothing);

    await PluginRegistry.I.disable(PluginIds.risk);
    await tester.pumpAndSettle();
    expect(find.text('风险提醒组件已启用'), findsNothing);
    expect(find.byType(QrPlate), findsOneWidget, reason: '放行后立即取码（演示数据有 code）');

    await PluginRegistry.I.enable(PluginIds.risk);
    await tester.pumpAndSettle();
    expect(find.text('风险提醒组件已启用'), findsOneWidget, reason: '再启用立刻重新拦');
    expect(find.byType(QrPlate), findsNothing);

    await closePage(tester);
  });

  testWidgets('电费：风险提醒启用时点充值只弹提醒，停用后恢复金额输入', (tester) async {
    await pumpPage(tester, const ElectricityPage());

    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();
    expect(find.text('风险提醒组件已启用'), findsOneWidget);
    expect(find.text('宿舍电费充值'), findsOneWidget, reason: '点明被拦的是哪一项行为');
    expect(find.textContaining('后果由用户自行承担'), findsOneWidget, reason: '后果条款要在拦截界面里点明');
    expect(find.text('充值金额（元）'), findsNothing, reason: '被拦时不进充值流程');

    // 弹窗里的「前往插件管理页停用」：先关弹窗再跳管理页
    await tester.tap(find.text('前往插件管理页停用'));
    await tester.pumpAndSettle();
    expect(find.text('插件管理'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await PluginRegistry.I.disable(PluginIds.risk);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();
    expect(find.text('充值金额（元）'), findsOneWidget, reason: '停用风险提醒后充值恢复');

    await closePage(tester);
  });

  /// 条款页滚到底（内容一屏放得下时拖不动，重复拖也不会出错）。
  /// 只拖条款页自己那个 ListView——管理页底下也有一个，别拖错。
  Future<void> scrollToEnd(WidgetTester tester) async {
    final list = find.descendant(
        of: find.byType(RiskNoticePage), matching: find.byType(ListView));
    if (list.evaluate().isEmpty) return;
    await tester.drag(list.first, const Offset(0, -4000));
    await tester.pumpAndSettle();
  }

  testWidgets('停用风险提醒要先过条款：不同意 = 不停用，同意 = 才停用', (tester) async {
    await pumpPage(tester, const PluginManagerPage());
    final tile = find.widgetWithText(SwitchListTile, '风险提醒');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue, reason: '默认启用');

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text(RiskTerms.title), findsOneWidget, reason: '停用前先过条款');
    expect(find.textContaining('由用户自行承担'), findsWidgets, reason: '责任限制条款要在正文里');

    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isTrue, reason: '未作出同意就不停用');

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    await tester.tap(find.text('已阅读并同意，停用本组件'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isFalse, reason: '同意后才真的停用');

    await closePage(tester);
  });

  testWidgets('条款页要读到底才能同意：滚动前按钮是灰的，读到底才点亮', (tester) async {
    // 视口压小逼出滚动（大屏上条款一屏放得下 → 直接算读完，见下一条用例的注释）
    await pumpPage(tester, const RiskNoticePage(confirmMode: true),
        size: const Size(800, 900));
    final agree = find.widgetWithText(FilledButton, '已阅读并同意，停用本组件');
    expect(tester.widget<FilledButton>(agree).onPressed, isNull,
        reason: '条款要真读到，不给一路点到底的机会');
    expect(find.textContaining('条款全文阅读完毕后'), findsOneWidget);

    await scrollToEnd(tester);
    expect(tester.widget<FilledButton>(agree).onPressed, isNotNull, reason: '读到底点亮同意');

    await closePage(tester);
  });

  testWidgets('条款页返回 = 未作出同意：返回手势关掉本页，风险提醒维持启用', (tester) async {
    // 走真实流程：管理页关开关 → 条款页 → 系统返回手势
    await pumpPage(tester, const PluginManagerPage());
    await tester.tap(find.widgetWithText(SwitchListTile, '风险提醒'));
    await tester.pumpAndSettle();
    expect(find.text(RiskTerms.title), findsOneWidget);

    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'x': 300.0,
      'y': 300.0,
      'progress': 0.6,
      'swipeEdge': 0,
    });
    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();

    expect(find.text(RiskTerms.title), findsNothing, reason: '返回手势把条款页关掉');
    expect(find.text('插件管理'), findsOneWidget, reason: '回到管理页');
    expect(PluginRegistry.I.isEnabled(PluginIds.risk), isTrue,
        reason: '返回 = 未作出同意，风险提醒维持启用');

    await closePage(tester);
  });

  testWidgets('校园码卡片在拦截与放行之间切换走全站同一条高度动画', (tester) async {
    await pumpPage(tester, const EcardPage());
    // 动画在 AnimatedSize 自己身上（子组件始终按自然高度布局，所以量卡片是量不出来的）
    final box = find.byType(AnimatedSize);
    expect(box, findsOneWidget, reason: '卡片切换挂在 AnimatedSize 上（与「我的」页可收起内容同一条过渡）');
    final blockedH = tester.getSize(box).height;

    await PluginRegistry.I.disable(PluginIds.risk);
    // 采样要跨过「控制器起步那一帧」（那一帧 elapsed 还是 0，量出来正好等于起点）
    await tester.pump(const Duration(milliseconds: 24));
    await tester.pump(const Duration(milliseconds: 24));
    await tester.pump(const Duration(milliseconds: 24)); // 累计 72ms：动画中段
    final midH = tester.getSize(box).height;
    await tester.pumpAndSettle();
    final normalH = tester.getSize(box).height;

    expect(normalH, isNot(blockedH), reason: '两张卡片高度不同，才看得出过渡');
    final lo = blockedH < normalH ? blockedH : normalH;
    final hi = blockedH < normalH ? normalH : blockedH;
    expect(midH, inExclusiveRange(lo, hi),
        reason: '切换途中高度卡在两端之间 —— 是高度过渡而不是瞬变');

    await closePage(tester);
  });
}
