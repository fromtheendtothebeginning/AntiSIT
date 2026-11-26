import 'package:flutter/material.dart';

/// 卡片「位置 + 尺寸」位移动画壳：目标变了从当前位置继续走（差项起步），时长不短于 0.2 秒。
/// 曲线一律 easeInOutCubic：位移摊满整个时长，中途改目标不跳回起点。
class SlotMotion extends StatefulWidget {
  const SlotMotion({
    super.key,
    required this.target,
    required this.duration,
    required this.child,
    this.snap = false,
  });

  /// 这一帧排版算出来的目标矩形。
  final Rect target;

  /// true = 直接贴住目标不做动画（跟着手指走的本体用）。
  final bool snap;

  /// 一次完整变化的时长（调用方给：换位 300ms / 换尺寸 520ms）。
  final Duration duration;

  final Widget child;

  /// 允许的最短动画时长（不小于 0.2 秒）。
  static const Duration minDuration = Duration(milliseconds: 200);

  @override
  State<SlotMotion> createState() => _SlotMotionState();
}

class _SlotMotionState extends State<SlotMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _effective(widget.duration));

  /// 本次变化的起点 / 终点；必须在 initState 里赋值，`late` 惰性初始化会拿到新目标、动画永远不播。
  late Rect _from;
  late Rect _to;

  @override
  void initState() {
    super.initState();
    _from = widget.target;
    _to = widget.target;
  }

  /// 上一段的瞬时速度（px/s）：下一次选曲线时用作动量。
  Offset _velocity = Offset.zero;

  /// 时长夹到不小于 [SlotMotion.minDuration]。
  Duration _effective(Duration d) =>
      d < SlotMotion.minDuration ? SlotMotion.minDuration : d;

  @override
  void didUpdateWidget(covariant SlotMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target == _to) return;
    if (widget.snap) {
      _controller.stop();
      _from = widget.target;
      _to = widget.target;
      _velocity = Offset.zero;
      _controller.value = 1;
      return;
    }
    // 差项：从「此刻屏幕上在哪」接着走，不回到上一段起点。
    final current = _rectAt(_controller.value);
    final dt = _effective(widget.duration).inMicroseconds / 1000000;
    final slope = _slope(_curveFor(_velocity, current.center, widget.target.center),
        _controller.value);
    _velocity = (current.center - _from.center) * (slope / dt);
    _from = current;
    _to = widget.target;
    if ((_to.center - _from.center).distance < 0.5 &&
        (_to.size.width - _from.size.width).abs() < 0.5 &&
        (_to.size.height - _from.size.height).abs() < 0.5) {
      _controller.value = 1;
      return;
    }
    _controller.duration = _effective(widget.duration);
    _controller.forward(from: 0);
  }

  /// 动画曲线：一律 easeInOutCubic；easeOut 在长时长里前段过快，看着像跳。
  Curve _curveFor(Offset velocity, Offset from, Offset to) => Curves.easeInOutCubic;

  /// 曲线在 t 处的斜率（差分近似），只用来推算瞬时速度。
  double _slope(Curve curve, double t) {
    const h = 0.02;
    final a = (t - h).clamp(0.0, 1.0);
    final b = (t + h).clamp(0.0, 1.0);
    if (b <= a) return 0;
    return (curve.transform(b) - curve.transform(a)) / (b - a);
  }

  /// 当前动画值对应的矩形。
  Rect _rectAt(double t) {
    if (t <= 0) return _from;
    if (t >= 1) return _to;
    final curve = _curveFor(_velocity, _from.center, _to.center);
    return Rect.lerp(_from, _to, curve.transform(t)) ?? _to;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // child 不参与每帧重建：只有外面那层 Positioned 在动。
      child: widget.child,
      builder: (context, child) {
        final rect = widget.snap || _controller.value >= 1
            ? _to
            : _rectAt(_controller.value);
        return Positioned.fromRect(rect: rect, child: child!);
      },
    );
  }
}
