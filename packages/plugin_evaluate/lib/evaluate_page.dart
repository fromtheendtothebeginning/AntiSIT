import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_model.dart';
import 'evaluate_panel.dart';
import 'evaluate_script.dart';

/// 学生评教助手：内嵌教务评教页（正方 `xspjgl` 评价详情页），页面加载完成后注入脚本，
/// 把页面上的每个评分项映射到面板里的一条滑块。
///
/// 两档用法：
/// * **一键同分** —— 面板顶部一条滑块，一个分数打到这一页所有评分项；
/// * **逐项调分** —— 每项一条滑块，只改那一项。
///
/// 只改页面上的分值控件，**提交仍在网页里自己点**：评教一旦提交不可撤，App 不代提交。
class EvaluatePage extends StatefulWidget {
  const EvaluatePage({super.key});

  @override
  State<EvaluatePage> createState() => _EvaluatePageState();
}

class _EvaluatePageState extends State<EvaluatePage> {
  WebViewHost? _host;

  /// 内核没启用 / 平台不支持时的说明（此时没有网页可看）。
  String? _unsupported;

  /// 面板状态：识别到的评分项 + 是否在等页面回执。面板是弹出的模态页，靠它保持同步。
  final ValueNotifier<EvaluatePanelState> _panel =
      ValueNotifier<EvaluatePanelState>(const EvaluatePanelState(items: []));

  String get _jwxtBase => AppState.I.school.jwxtBase;

  @override
  void initState() {
    super.initState();
    final cap = PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview);
    if (cap == null) {
      _unsupported = '评教助手要跑在 WebView 内核上：到「我的 → 插件管理」里把「WebView 内核」打开';
      return;
    }
    if (!cap.available) {
      _unsupported = '当前平台不支持内嵌网页：评教助手只在 Android / iOS 上可用';
      return;
    }
    _host = cap.host(
      url: evalUrlFor(_jwxtBase),
      channel: kEvaluateChannel,
      onMessage: _onMessage,
      onPageReady: _onPageReady,
    );
    if (_host == null) {
      _unsupported = '当前平台不支持内嵌网页：评教助手只在 Android / iOS 上可用';
    }
  }

  @override
  void dispose() {
    _host?.dispose();
    _panel.dispose();
    super.dispose();
  }

  /// 每次主文档加载完成：重新注入脚本再扫一遍。换页（点进某一门课 / 登录回来）之后
  /// 旧的脚本随上下文一起没了，不重注入就永远扫不到东西。
  void _onPageReady(WebViewHost host) {
    unawaited(() async {
      await host.run(evaluateInjectorJs(channel: kEvaluateChannel));
      await host.run(kEvaluateScanCall);
    }());
  }

  void _onMessage(WebViewHost host, String message) {
    final scan = parseEvalMessage(message);
    if (scan != null) {
      _panel.value = EvaluatePanelState(
        items: scan.items,
        hint: scan.hint,
        login: scan.login,
      );
      return;
    }
    // 改分回执：页面可能把分数就近取档（单选组只有 10/8/6 这种），以回执为准刷新
    final applied = parseEvalApplied(message);
    if (applied.isEmpty) return;
    final items = [
      for (final item in _panel.value.items)
        applied.containsKey(item.index) ? item.copyWith(value: applied[item.index]) : item,
    ];
    _panel.value = _panel.value.copyWith(items: items, busy: false);
  }

  Future<void> _applyAll(double value) async {
    final host = _host;
    if (host == null || _panel.value.items.isEmpty) return;
    _panel.value = _panel.value.copyWith(busy: true);
    await host.run(evaluateApplyAllCall(value));
    if (mounted) _panel.value = _panel.value.copyWith(busy: false);
  }

  Future<void> _applyOne(EvalItem item, double value) async {
    final host = _host;
    if (host == null) return;
    _panel.value = _panel.value.copyWith(busy: true);
    await host.run(evaluateApplyOneCall(item.index, value));
    if (mounted) _panel.value = _panel.value.copyWith(busy: false);
  }

  Future<void> _rescan() async {
    final host = _host;
    if (host == null) return;
    _panel.value = _panel.value.copyWith(busy: true);
    await host.run(evaluateInjectorJs(channel: kEvaluateChannel));
    await host.run(kEvaluateScanCall);
    if (mounted) _panel.value = _panel.value.copyWith(busy: false);
  }

  /// 面板判断出当前是登录页：直接把网页导到教务登录页（cookie 由 WebView 自己存着，
  /// 登完再「回到评教页」即可）。
  Future<void> _goLogin() async {
    await _host?.load(evalLoginUrlFor(_jwxtBase));
  }

  Future<void> _backToEvaluate() async {
    final host = _host;
    if (host == null) return;
    _panel.value = const EvaluatePanelState(items: []);
    await host.load(evalUrlFor(_jwxtBase));
  }

  void _openPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: SemColors.menuBg,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.62,
        child: ValueListenableBuilder<EvaluatePanelState>(
          valueListenable: _panel,
          builder: (_, state, __) => EvaluatePanel(
            state: state,
            onApplyAll: _applyAll,
            onApplyOne: _applyOne,
            onRescan: _rescan,
            onLogin: _goLogin,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final unsupported = _unsupported;
    return Scaffold(
      appBar: AppBar(
        title: const Text('学生评教'),
        actions: [
          if (host != null)
            IconButton(
              onPressed: _backToEvaluate,
              icon: const Icon(Icons.replay_rounded),
              tooltip: '回到评教页',
            ),
          if (host != null)
            IconButton(
              onPressed: () => host.reload(),
              icon: const Icon(Icons.refresh),
              tooltip: '刷新网页',
            ),
        ],
      ),
      body: unsupported != null ? _notice(unsupported) : _webBody(host!),
      floatingActionButton: host == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openPanel,
              icon: const Icon(Icons.tune),
              label: const Text('评分助手'),
            ),
    );
  }

  Widget _webBody(WebViewHost host) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: host.error,
            builder: (_, error, __) =>
                error == null ? const SizedBox.shrink() : _errorBar(error),
          ),
          ValueListenableBuilder<double>(
            valueListenable: host.progress,
            builder: (_, progress, __) => progress > 0 && progress < 1
                ? LinearProgressIndicator(value: progress, minHeight: 2)
                : const SizedBox.shrink(),
          ),
          Expanded(child: host.view),
        ],
      );

  Widget _errorBar(String error) => Material(
        color: SemColors.dangerSoft,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text('网页加载失败：$error',
              style: TextStyle(fontSize: 12, height: 1.5, color: SemColors.danger)),
        ),
      );

  Widget _notice(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 40, color: SemColors.textMuted),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.7, color: SemColors.textSecondary)),
            ],
          ),
        ),
      );
}
