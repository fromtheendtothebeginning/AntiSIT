import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme_palette.dart';

// 输入控件与分段滑块拆到同目录文件，这里 re-export 保持 glass_widgets.dart 的出口不变。
export 'glass_inputs.dart';
export 'glass_tabs.dart';

/// 卡片圆角：玻璃卡与宫格卡片共用。
const cardRadius = 16.0;

/// 网站同款状态胶囊徽章：全圆、同色 1px 描边、同色浅底。
class Capsule extends StatelessWidget {
  const Capsule(this.text, {super.key, this.color, this.soft});

  final String text;
  final Color? color;
  final Color? soft;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SemColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: soft ?? c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// 筛选标签行：一行小胶囊，点选切换（再点已选中的取消）；[labels] 为空时不占位。
class TagFilterRow extends StatelessWidget {
  const TagFilterRow({
    super.key,
    required this.labels,
    required this.onSelected,
    this.selected = '',
    this.title,
  });

  final List<String> labels;

  /// 当前选中值（'' = 未筛选）。
  final String selected;
  final ValueChanged<String> onSelected;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(title!,
                style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
          ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in labels)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelected(l == selected ? '' : l),
                child: Capsule(l,
                    color: l == selected ? SemColors.accent : SemColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }
}

/// 液态玻璃卡片（复刻 anticlass .panel）：半透明玻璃面 + 顶部高光 + 玻璃描边 + 柔和外投影。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.radius,
    this.bottomGap = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? radius;

  /// 卡片底部的留白（列表里当卡片间距用）；网格里传 0 才能让高度精确等于网格单元。
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? cardRadius;
    final base = SemColors.card;
    // 顶边白色高光渐变（CSS: 白 10% → 透明 50%），合成进同一渐变。
    final top = Color.alphaBlend(Colors.white.withValues(alpha: 0.10), base);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: DecoratedBox(
        // 阴影画在 Material/Ink 之外：InkFeature 会被 Material 画布裁剪，透出方形阴影角。
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, base],
            stops: const [0, 0.5],
          ),
          border: Border.all(color: SemColors.border),
          boxShadow: [
            BoxShadow(
                color: SemColors.shadow, offset: const Offset(0, 8), blurRadius: 24),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(r),
            onTap: onTap,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 提供商品牌 logo：按当前主题着色的单色 SVG；[asset] 为空时回退成字母徽章。
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.asset,
    required this.initial,
    this.size = 20,
  });

  final String asset;
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (asset.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SemColors.neutralSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: SemColors.border),
        ),
        child: Text(
          _badgeText(initial),
          style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.2,
              color: SemColors.textSecondary),
        ),
      );
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(SemColors.textPrimary, BlendMode.srcIn),
    );
  }

  /// 徽章文字：取名称里前两位拉丁字母 / 数字（GLM→GL），否则用首字。
  static String _badgeText(String label) {
    final alnum = RegExp(r'[A-Za-z0-9]').allMatches(label).map((m) => m.group(0)!).join();
    if (alnum.isNotEmpty) {
      final n = alnum.length >= 2 ? 2 : 1;
      return alnum.substring(0, n).toUpperCase();
    }
    final t = label.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }
}

/// 页面底部的备注区（细字、次要色）。
class PageNotes extends StatelessWidget {
  const PageNotes({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(line,
                  style: TextStyle(
                      fontSize: 11, color: SemColors.textMuted, height: 1.6)),
            ),
        ],
      ),
    );
  }
}

/// 30px/600 大数字统计（网站 .cs-stat）。
class BigStat extends StatelessWidget {
  const BigStat({super.key, required this.label, required this.value, this.suffix, this.color});

  final String label;
  final String value;
  final String? suffix;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w600, height: 1.1,
                    color: color ?? SemColors.textPrimary)),
            if (suffix != null) ...[
              const SizedBox(width: 4),
              Text(suffix!,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: SemColors.textSecondary)),
            ],
          ],
        ),
      ],
    );
  }
}
