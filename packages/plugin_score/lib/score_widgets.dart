import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 数字增长动画（网站 CountUp：0 → 终值，700ms 缓出；值变化重播）。
class ScoreCountUpText extends StatefulWidget {
  const ScoreCountUpText({super.key, required this.value, required this.style});

  final double? value;
  final TextStyle style;

  @override
  State<ScoreCountUpText> createState() => _ScoreCountUpTextState();
}

class _ScoreCountUpTextState extends State<ScoreCountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late double? _shown = widget.value;

  @override
  void initState() {
    super.initState();
    if (_shown != null) _c.forward();
  }

  @override
  void didUpdateWidget(covariant ScoreCountUpText old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _shown = widget.value;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _shown;
    if (v == null) {
      return Text('—', style: widget.style);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic).value;
        final val = v * (1 - math.pow(1 - t, 3));
        return Text(val.toStringAsFixed(1), style: widget.style);
      },
    );
  }
}
