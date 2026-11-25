import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';
import 'ext_icon.dart';

/// 拓展卡片：按尺寸档位画图标、名称、简介、来源与状态角标。
class ExtensionCard extends StatelessWidget {
  const ExtensionCard({
    super.key,
    required this.item,
    required this.size,
    required this.editing,
    required this.hideUrls,
    required this.appVersion,
    required this.updatable,
    required this.onOpen,
    required this.onMore,
  });

  final ExtensionItem item;
  final GridCardSize size;
  final bool editing;

  /// 隐藏全部网址的总开关：只影响远程拓展那一行来源。
  final bool hideUrls;

  /// 本机 App 版本，用于判「需升级 App」。
  final String appVersion;

  /// 市场里这条有没有新版（由页面查目录得出）。
  final bool updatable;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final e = item;
    final version = e.version.isEmpty ? '' : 'v${e.version}';
    // 眼睛开关只隐藏网址：本地 / 市场来源与版本不是 URL，照旧显示
    final showSource = !hideUrls || e.bundled;
    final showFooter = showSource || version.isNotEmpty;
    // 排版按尺寸档位的「取向」分（后续加档位只需补一种排法）
    final kind = size.kind;
    final tile = kind == GridCardKind.iconOnly;
    final bar = kind == GridCardKind.row;
    final narrow = kind == GridCardKind.stack;
    final tall = size == GridCardSize.tall;

    Widget footer({double fontSize = 10.5}) {
      if (!showFooter) return const SizedBox.shrink();
      return Row(
        children: [
          if (showSource) ...[
            if (!e.bundled) ...[
              Icon(
                Icons.public,
                size: fontSize + 1.5,
                color: SemColors.textMuted,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                _sourceLabel(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  color: SemColors.textMuted,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (version.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              version,
              style: TextStyle(fontSize: fontSize, color: SemColors.textMuted),
            ),
          ],
        ],
      );
    }

    if (tile) {
      // 1x1 小方格：只显示图标（居中，略放大），名称靠选中后的尺寸条或放大后再看
      return AppCard(
        bottomGap: 0,
        radius: 14,
        padding: EdgeInsets.zero,
        onTap: editing ? null : onOpen,
        child: Center(
          child: _iconWithStatus(e, size: 20, padding: 5, dot: true),
        ),
      );
    }

    if (bar) {
      // 1x3 横条：图标在左、名称与简介在右；「更多」靠右上，给右下角缩放弧线让位
      return AppCard(
        bottomGap: 0,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        onTap: editing ? null : onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconWithStatus(e, size: 18, padding: 6, dot: true),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: SemColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            _moreButton(e, size: 22, iconSize: 14),
          ],
        ),
      );
    }

    if (narrow) {
      // 2x1 竖条：卡面只有 55dp 宽，三点按钮做成右上角浮层，图标与名称才不被裁
      return AppCard(
        bottomGap: 0,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(8, 8, 5, 8),
        onTap: editing ? null : onOpen,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconWithStatus(e, size: 16, padding: 5, dot: true),
                const Spacer(),
                Text(
                  e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            // 浮层去掉位，不再挤占那一行的宽度
            Positioned(
              top: -3,
              right: -3,
              child: _moreButton(e, size: 18, iconSize: 12),
            ),
          ],
        ),
      );
    }

    if (tall) {
      // 2x2 竖卡：图标 + 更多在顶部一行，名称 / 简介往下排
      return AppCard(
        bottomGap: 0,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        onTap: editing ? null : onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconWithStatus(e, size: 17, padding: 6, dot: true),
                const Spacer(),
                _moreButton(e, size: 22, iconSize: 14),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              e.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Text(
                e.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: SemColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 默认 2x3：图标 36 + 标题 + 单行简介 + 来源/版本
    final badge = _badge(e);
    return AppCard(
      bottomGap: 0,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      onTap: editing ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExtIcon(item: e),
              // 状态胶囊最多见的是「需升级 App」：窄屏上宁可整体缩一点，也别顶出卡片
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: badge == null
                      ? const SizedBox.shrink()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: badge,
                        ),
                ),
              ),
              const SizedBox(width: 4),
              _moreButton(e),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 15,
            child: Text(
              e.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                color: SemColors.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          footer(),
        ],
      ),
    );
  }

  Widget? _badge(ExtensionItem e) {
    if (e.needsNewerApp(appVersion)) {
      return Capsule('需升级 App', color: SemColors.danger);
    }
    if (updatable) return Capsule('可更新', color: SemColors.warning);
    if (e.builtin) return Capsule('内置', color: SemColors.textMuted);
    return Capsule('已安装', color: SemColors.success);
  }

  /// 卡片底部左侧：远程写域名，本地包写来源（版本单独靠右）。
  String _sourceLabel(ExtensionItem e) {
    if (!e.bundled) {
      final host = Uri.tryParse(e.url)?.host ?? '';
      return host.isEmpty ? e.url : host;
    }
    if (e.runtime == ExtensionItem.runtimeLegacy) return '旧版网页拓展（需迁移）';
    if (!e.fromMarket) return '本地 Cordis';
    return '插件市场 · Cordis';
  }

  /// 紧凑尺寸下用的小圆点状态：只标「需升级 App / 可更新」这类要处理的事。
  Color? _statusColor(ExtensionItem e) {
    if (e.needsNewerApp(appVersion)) return SemColors.danger;
    if (updatable) return SemColors.warning;
    return null;
  }

  /// 图标 + 右上角状态点（紧凑尺寸用；默认尺寸用完整胶囊）。
  Widget _iconWithStatus(
    ExtensionItem e, {
    double size = 24,
    double padding = 8,
    bool dot = false,
  }) {
    final icon = ExtIcon(item: e, size: size, padding: padding);
    final color = _statusColor(e);
    if (!dot || color == null) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: SemColors.bg, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _moreButton(
    ExtensionItem e, {
    double size = 30,
    double iconSize = 18,
  }) =>
      Tooltip(
        message: e.builtin ? '详情' : '编辑 / 删除',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMore,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // card 本身带透明度，withValues 会覆盖掉 alpha（深色下变近白）：
              // 先与页面底色合成，得到实底又不发白
              color: Color.alphaBlend(SemColors.card, SemColors.bg),
              border: Border.all(color: SemColors.border),
            ),
            child: Icon(
              Icons.more_horiz,
              size: iconSize,
              color: SemColors.textMuted,
            ),
          ),
        ),
      );
}

/// 虚线圆角边框的「添加拓展」占位卡。
class ExtensionAddCard extends StatelessWidget {
  const ExtensionAddCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: CustomPaint(
      painter: _DashedBorderPainter(
        color: SemColors.borderStrong.withValues(alpha: 0.55),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: SemColors.borderStrong),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: SemColors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '添加拓展',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SemColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 虚线圆角边框：给「添加拓展」占位卡用（不引第三方 dashed border 包）。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const double radius = 16;
  static const double dash = 6;
  static const double gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
