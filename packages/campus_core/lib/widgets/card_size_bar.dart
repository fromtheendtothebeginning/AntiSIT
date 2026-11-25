import 'package:flutter/material.dart';

import 'flexible_grid_size.dart';
import 'theme_palette.dart';

/// ColorOS 风格的卡片尺寸切换条：选中卡片后，一排档位的缩略预览按钮。
class CardSizeBar extends StatelessWidget {
  const CardSizeBar({super.key, required this.size, required this.onChanged});

  /// 当前选中卡片的尺寸；null = 还没选中卡片（整排按钮置灰）。
  final GridCardSize? size;

  /// 点了某一档尺寸（调用方负责写到选中卡片上）。
  final ValueChanged<GridCardSize> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = size != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 点条本身的空白不冒泡成页面级的「退出整理」。
      onTap: () {},
      child: Container(
        key: const ValueKey<String>('card-size-bar'),
        padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
        decoration: BoxDecoration(
          color: SemColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SemColors.accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: SemColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                enabled ? '卡片大小 · ${size!.label}' : '点选一张卡片调整大小',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: enabled
                      ? SemColors.textSecondary
                      : SemColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // flex: 0 = 按内容自然宽度排，档位多到装不下时自己在条内横向滚动。
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < GridCardSize.presets.length; i++) ...[
                      _SizeOption(
                        preset: GridCardSize.presets[i],
                        selected: size == GridCardSize.presets[i],
                        enabled: enabled,
                        onTap: () => onChanged(GridCardSize.presets[i]),
                      ),
                      if (i != GridCardSize.presets.length - 1)
                        const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 尺寸条上的单个档位：按行 × 列比例的小预览 + Tooltip。
class _SizeOption extends StatelessWidget {
  const _SizeOption({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final GridCardSize preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? SemColors.accent : SemColors.textMuted;
    final box = preset.previewBox;
    final w = box.w;
    final h = box.h;
    final label = '${preset.label} ${preset.specLabel}';
    return Semantics(
      button: true,
      selected: selected,
      label: '卡片大小 $label',
      child: Tooltip(
        message: label,
        child: GestureDetector(
          key: ValueKey<String>('card-size-option:${preset.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: selected
                  ? SemColors.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? SemColors.accent : SemColors.border,
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: selected
                        ? SemColors.accent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: fg, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
