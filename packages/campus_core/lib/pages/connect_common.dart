import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// 连接设置的分区标题：玻璃风图标章 + 标题。
class ConnectSectionTitle extends StatelessWidget {
  const ConnectSectionTitle({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: SemColors.accentSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: SemColors.accent),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const Spacer(),
      ],
    );
  }
}

/// 可收起卡片：标题行整行可点，内容高度用顶部锚定的 AnimatedSize 过渡。
class ConnectCollapsibleCard extends StatelessWidget {
  const ConnectCollapsibleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.content,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final bool open;
  final VoidCallback onToggle;
  final Widget content;

  /// 标题行右侧的按钮。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Row(
                children: [
                  Expanded(child: ConnectSectionTitle(icon: icon, title: title)),
                  ...actions,
                  const SizedBox(width: 4),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: SemColors.textMuted,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open
                  ? content
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      );
}
