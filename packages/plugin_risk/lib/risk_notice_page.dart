import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_terms.dart';

/// 「风险提醒」条款页——**法律条文形式**（条 → 款 → 项，先定义后使用），
/// 正文见 [RiskTerms]：
///
/// * **正文分条**（每条一张卡：条号 + 标题 + 款 / 项），全文可滚动；
/// * **关闭前确认**（[confirmMode]）：底部常驻「不同意」与「已阅读并同意，停用本组件」
///   两个并列按钮，同意按钮在条款全文读完之前不可用——不给「一路点到底」的机会；
///   内容一屏放得下（滚不动）时直接算读完，不把人锁在灰按钮上；
/// * **返回 = 未作出同意**：系统返回手势 / 返回键 / 左上角返回都只是关掉本页（返回 null），
///   调用方按第五条第（二）款处理，本组件维持启用。
///
/// 正文与拦截引导共用 [RiskTerms] 一份文案，不会两处走偏。
class RiskNoticePage extends StatefulWidget {
  const RiskNoticePage({super.key, this.confirmMode = false});

  /// true = 停用前的确认态（底部有同意 / 不同意，返回 true 表示用户已作出同意的意思表示）。
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
      // 一屏就看完（滚不动）→ 直接算读完：不能让「读完才能点」把人卡死。
      // 注意要 setState——只改字段的话按钮不会重建，会一直灰着。
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
    return Scaffold(
      appBar: AppBar(title: const Text(RiskTerms.title)),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                style: TextStyle(fontSize: 12.5, height: 1.6, color: SemColors.danger),
              ),
            ),
          const RiskNotice(),
        ],
      ),
      bottomNavigationBar: widget.confirmMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_readToEnd) ...[
                      Text('条款全文阅读完毕后，「已阅读并同意，停用本组件」按钮方为可用。',
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: SemColors.textSecondary),
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('不同意'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: SemColors.danger,
                                disabledBackgroundColor: SemColors.stripe),
                            onPressed:
                                _readToEnd ? () => Navigator.pop(context, true) : null,
                            child: const Text('已阅读并同意，停用本组件'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// 条款正文（一条一张卡：条号 + 标题 + 款 / 项）。拦截引导、设置入口与确认页
/// 都渲染它——改文案只改 [RiskTerms] 一处。
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
                Text('${c.no}　${c.title}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(c.body,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.7, color: SemColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
