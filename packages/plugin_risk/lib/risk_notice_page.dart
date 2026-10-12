import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 风险提醒与免责声明。
///
/// 两种用法：
/// * **读一遍**（默认）：从拦截引导里的「风险说明与条款」，或「我的 → 设置 → 风险提醒」进来；
/// * **关闭前确认**（[confirmMode]）：插件管理页停用「风险提醒」之前的最后一步，
///   底部给「取消 / 我已阅读并同意，关闭风险提醒」，同意才真的关掉。
///
/// 条款正文写在 [RiskNotice] 里，与拦截引导共用同一份——文案只有一处，不会两处走偏。
class RiskNoticePage extends StatelessWidget {
  const RiskNoticePage({super.key, this.confirmMode = false});

  /// true = 关闭前的确认态（有同意按钮，返回 true 表示用户已同意）。
  final bool confirmMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('风险提醒与免责声明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (confirmMode)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SemColors.dangerSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '你要关闭「风险提醒」。关掉之后，付款码与电费充值会立刻恢复可用，'
                '风险回到你手上——请先读完下面的条款。',
                style: TextStyle(fontSize: 12.5, height: 1.6, color: SemColors.danger),
              ),
            ),
          const RiskNotice(),
        ],
      ),
      bottomNavigationBar: confirmMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: SemColors.danger),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('我已阅读并同意，关闭风险提醒'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// 条款正文（AppCard 列表）。拦截引导与设置入口都渲染它，改文案只改这一处。
class RiskNotice extends StatelessWidget {
  const RiskNotice({super.key});

  /// (小标题, 正文)。正文里的换行原样保留。
  static const List<(String, String)> sections = [
    (
      '「风险提醒」是什么',
      '它是本机的一道拦截，默认开启、不联网、不上传任何数据：开启期间，校园码付款码与'
          '宿舍电费充值不会放行，只给出说明与关闭入口。它不改变你的账号、卡片或任何数据。',
    ),
    (
      '为什么要拦',
      '本 App 的这两项功能走的不是学校官方客户端的通道——付款码来自第三方接口，'
          '充值走校园卡公网直连。这类通道可能出现：\n\n'
          '· 触发学校 / 一卡通系统的风控：账号被限制、卡片被冻结、线上服务被暂停；\n'
          '· 扣款与到账不一致（接口变更、网络超时、重复提交等）；\n'
          '· 操作记录被学校或第三方留存。\n\n'
          '风控一旦触发，通常需要本人去一卡通中心或学校信息部门申诉处理，App 这边帮不上忙。',
    ),
    (
      '关闭即表示你已阅读并同意',
      '关闭「风险提醒」后，上述两项功能立即恢复可用。由此产生的一切后果'
          '（包括但不限于账号被风控、扣款或到账异常、余额与记录丢失）由你自行承担；'
          '本 App 及其开发者不承担任何责任，也不具备为你恢复账号或追回款项的能力。',
    ),
    (
      '几点建议',
      '· 优先使用学校官方渠道（一卡通 App / 自助机 / 后勤窗口）；\n'
          '· 只在确有必要时使用，充值从小额开始，确认到账后再继续；\n'
          '· 一旦出现异常立即停止使用，并联系学校一卡通 / 后勤部门。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, body) in sections) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.7, color: SemColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '你可以随时在「我的 → 设置 → 风险提醒」查看本声明；'
            '重新开启「风险提醒」即可恢复拦截。',
            style: TextStyle(fontSize: 11, height: 1.6, color: SemColors.textMuted),
          ),
        ),
      ],
    );
  }
}
