import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_terms.dart';

/// 「风险提醒」条款页（条 → 款 → 项，正文见 [RiskTerms]）。
/// [confirmMode] 下底部常驻「不同意 / 已阅读并同意」，正文读到底前同意按钮不可用（一屏看完则直接可点）。
/// 返回 = 未作出同意（pop null），调用方据此维持组件启用。
class RiskNoticePage extends StatefulWidget {
  const RiskNoticePage({super.key, this.confirmMode = false});

  /// true = 停用前的确认态（底部有同意 / 不同意，返回 true 表示已作出同意）。
  final bool confirmMode;

  @override
  State<RiskNoticePage> createState() => _RiskNoticePageState();
}

class _RiskNoticePageState extends State<RiskNoticePage> {
  final _scroll = ScrollController();

  /// 正文是否已读到底（确认态下才用）。
  bool _readToEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.confirmMode) {
      // 一屏就看完（滚不动）则直接算读完，不能把人卡在灰按钮上；须 setState 才会重建按钮。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final max = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
        if (max <= 8 && !_readToEnd) setState(() => _readToEnd = true);
      });
    } else {
      _readToEnd = true;
    }
  }

  void _onScroll() {
    if (_readToEnd || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 24) setState(() => _readToEnd = true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整页监听 AppState：悬浮玻璃顶栏开关改完要连 Scaffold 一起重建。
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 先算顶栏留白：body 里的 MediaQuery 已扣掉状态栏。
        final topInset = glassTopInset(context);
        // 确认态底部有操作条：悬浮玻璃底栏，内容从它底下穿过去（同评教表单页）。
        final hasBar = widget.confirmMode;
        final barHeight = _actionBarHeight;
        final bottomInset = hasBar ? glassBottomInset(context, barHeight: barHeight) : 0.0;
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          extendBody: hasBar && glassBottomBarEnabled,
          appBar: glassAppBar(context, title: const Text(RiskTerms.title)),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(16, 8 + topInset, 16, 24 + bottomInset),
            children: [
              if (widget.confirmMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SemColors.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '用户拟停用本组件。依第三条第（四）项，停用后受拦截行为即行恢复；'
                    '请于阅读本条款全文后作出决定。',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: SemColors.danger,
                    ),
                  ),
                ),
              const RiskNotice(),
            ],
          ),
          ),
          bottomNavigationBar: hasBar
              ? glassBottomBar(
                  context,
                  height: barHeight,
                  child: _actionBar(),
                )
              : null,
        );
      },
    );
  }

  /// 操作条内容高度（不含 [glassBottomBar] 自己的胶囊内边距）。
  /// 未读完时上面多一行提示，条要跟着长高，否则按钮会被竖向挤扁。
  /// 数值留了几像素余量：按钮本身有最小高度，卡太紧会报 RenderFlex overflow。
  double get _actionBarHeight => _readToEnd ? 40 : 62;

  /// 操作条内容（安全区、玻璃胶囊与内边距由 [glassBottomBar] 提供）。
  Widget _actionBar() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_readToEnd) ...[
            Text(
              '条款全文阅读完毕后，「已阅读并同意，停用本组件」按钮方为可用。',
              style: TextStyle(fontSize: 10.5, color: SemColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
          ],
          SizedBox(
            height: 36,
            child: Row(
              // stretch：按钮撑满这 36px，否则 minimumSize.zero 会让它们缩成文字高度（约 20px）。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SemColors.textSecondary,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('不同意', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: SemColors.danger,
                      disabledBackgroundColor: SemColors.stripe,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _readToEnd
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text(
                      '已阅读并同意，停用本组件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

/// 条款正文（一条一张卡）；拦截引导、设置入口与确认页共用，改文案只改 [RiskTerms]。
class RiskNotice extends StatelessWidget {
  const RiskNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in RiskTerms.clauses) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.no}　${c.title}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  c.body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    color: SemColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
