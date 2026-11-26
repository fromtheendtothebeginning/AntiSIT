import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 虚线圆角框：缩放时用它画「松手后会变成这个大小」的占位背景。
class DashedBoxPainter extends CustomPainter {
  const DashedBoxPainter({
    required this.color,
    required this.fill,
    required this.radius,
    this.glow = const Color(0x00000000),
    this.dash = 9,
    this.gap = 5,
    this.strokeWidth = 2.6,
  });

  final Color color;
  final Color fill;

  /// 外发光（同一条路径先画粗淡一层当光晕，再画实线）。
  final Color glow;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2 + 1;
    final rect = (Offset.zero & size).deflate(inset);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.drawRRect(rrect, Paint()..color = fill);

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();

    if (glow.a > 0) {
      final halo = Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (final metric in metrics) {
        _dashPath(canvas, metric, halo);
      }
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final metric in metrics) {
      _dashPath(canvas, metric, stroke);
    }
  }

  // PathMetric 属于 dart:ui，这里不显式标类型（避免额外 import），交给推断。
  void _dashPath(Canvas canvas, dynamic metric, Paint paint) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gap;
    }
  }

  @override
  bool shouldRepaint(covariant DashedBoxPainter old) =>
      old.color != color ||
      old.fill != fill ||
      old.glow != glow ||
      old.radius != radius ||
      old.dash != dash ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
}

/// ColorOS 风格的右下角「白弧」缩放角标：贴着卡片圆角的两道圆弧。
class CornerArcPainter extends CustomPainter {
  const CornerArcPainter({required this.color, required this.glow});

  final Color color;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width - 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width, size.height),
      radius: radius,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi / 2,
      false,
      Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi / 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CornerArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
}
