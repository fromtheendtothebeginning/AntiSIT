import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'common.dart';
import '../json_num.dart';

/// 电费历史折线图（复刻网站「历史用量」：虚线网格 + 主色折线 + 充值点标记）。
class BalanceChart extends StatelessWidget {
  const BalanceChart({super.key, required this.records, this.height = 170});

  /// [{balance, recharge, time}]，时间升序。
  final List<Map<String, dynamic>> records;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (records.length < 2) {
      return SizedBox(
        height: 120,
        child: Center(child: Text('数据不足，需至少两天的记录', style: TextStyle(fontSize: 12, color: SemColors.textMuted))),
      );
    }
    return SizedBox(height: height, child: CustomPaint(size: Size.infinite, painter: _ChartPainter(records)));
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.records);

  final List<Map<String, dynamic>> records;

  static const _padL = 40.0, _padR = 10.0, _padT = 12.0, _padB = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _padL - _padR;
    final plotH = size.height - _padT - _padB;
    if (plotW <= 0 || plotH <= 0) return;

    final values = records
        .map((r) => asDouble(r['balance']) ?? 0.0)
        .toList();
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (hi - lo < 1) hi = lo + 1;
    final pad = (hi - lo) * 0.08;
    lo = math.max(0, lo - pad);
    hi += pad;

    double x(int i) => _padL + plotW * i / (records.length - 1);
    double y(double v) => _padT + plotH * (1 - (v - lo) / (hi - lo));

    final gridPaint = Paint()
      ..color = SemColors.border
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 横向虚线网格 + Y 轴刻度（4 条）
    final labelStyle = TextStyle(fontSize: 9, color: SemColors.textMuted);
    for (var g = 0; g < 4; g++) {
      final t = g / 3;
      final vy = _padT + plotH * t;
      final v = hi - (hi - lo) * t;
      final dash = 3.0;
      var dx = _padL;
      while (dx < _padL + plotW) {
        canvas.drawLine(Offset(dx, vy), Offset(math.min(dx + dash, _padL + plotW), vy), gridPaint);
        dx += dash * 2;
      }
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(0), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_padL - tp.width - 4, vy - tp.height / 2));
    }

    // 折线
    final linePaint = Paint()
      ..color = SemColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < records.length; i++) {
      final p = Offset(x(i), y(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // 充值点（绿色实心）+ 普通点略过（太密）
    final dotPaint = Paint()..color = SemColors.success;
    for (var i = 0; i < records.length; i++) {
      final recharge = asNum(records[i]['recharge']) ?? 0;
      if (recharge > 0) {
        canvas.drawCircle(Offset(x(i), y(values[i])), 3.5, dotPaint);
      }
    }

    // X 轴首/中/尾日期标签
    String label(int i) {
      final t = '${records[i]['time']}';
      return t.length >= 10 ? t.substring(5, 10) : t;
    }

    for (final i in _xLabelIndexes()) {
      final tp = TextPainter(
        text: TextSpan(text: label(i), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = x(i) - tp.width / 2;
      dx = dx.clamp(_padL - 8, size.width - tp.width).toDouble();
      tp.paint(canvas, Offset(dx, size.height - _padB + 4));
    }
  }

  List<int> _xLabelIndexes() {
    final n = records.length;
    return [0, (n - 1) ~/ 2, n - 1];
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => oldDelegate.records != records;
}
