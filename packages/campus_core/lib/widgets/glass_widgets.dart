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
      child: CustomPaint(
        // 投影只画在卡片**外面**。卡片面是半透明的（白 55%），把投影直接画在卡面
        // 底下会从卡面里透上来：卡底压出一条暗带、下一张卡的顶部又吃到上一张卡的
        // 投影再来一条——多卡堆叠时就是「多处奇怪的阴影」。
        // 所以投影层不能垫在卡面下面，而是用「卡片形状取反」的区域裁掉卡内部分。
        painter: _OutsideShadowPainter(
          color: SemColors.shadow,
          radius: r,
          offset: const Offset(0, 8),
          blurRadius: 24,
        ),
        child: DecoratedBox(
          // 卡面（渐变 + 描边）；不再带 boxShadow。
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, base],
              stops: const [0, 0.5],
            ),
            border: Border.all(color: SemColors.border),
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
      ),
    );
  }
}

/// 卡片外投影：只画在圆角矩形**外面**，卡内一点不落。
///
/// 正常做法是给卡片自己的 `BoxDecoration.boxShadow` —— 但本 App 的卡面是半透明的
/// （浅色下白 55%），投影垫在卡面底下会透上来，卡内出现一条随位置变化的暗带；
/// 多张卡上下堆叠时，上一张卡的投影还会透进下一张卡的顶部，看起来就是
/// 「卡片之间和卡片里各有一条灰带」。这里用「大矩形减去卡片圆角矩形」的环状区域
/// 裁一刀，把投影严格限制在卡片外面。
class _OutsideShadowPainter extends CustomPainter {
  const _OutsideShadowPainter({
    required this.color,
    required this.radius,
    required this.offset,
    required this.blurRadius,
  });

  final Color color;
  final double radius;
  final Offset offset;
  final double blurRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || color.a == 0) return;
    final card = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    // 投影最大可视范围：blur 的高斯尾巴约等于 blurRadius，再加偏移量。
    final reach = blurRadius + offset.distance + 2;
    final outer = (Offset.zero & size).inflate(reach);
    final ring = Path.combine(
      PathOperation.difference,
      Path()..addRect(outer),
      Path()..addRRect(card),
    );
    if (ring.getBounds().isEmpty) return;
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawRRect(
      card.shift(offset),
      Paint()
        ..color = color
        // Flutter 的 BoxShadow 内部就是 blurRadius/2 的 σ，保持一致。
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutsideShadowPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.offset != offset ||
      old.blurRadius != blurRadius;
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
