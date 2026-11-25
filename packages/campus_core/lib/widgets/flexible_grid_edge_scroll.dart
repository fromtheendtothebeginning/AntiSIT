import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 拖动到滚动区上下边缘时的自动滚动（只在拖动中跑）。
class GridEdgeScroller {
  GridEdgeScroller({
    required TickerProvider vsync,
    required this.edge,
    required this.maxSpeed,
    required this.onScrolled,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  /// 距边缘多少像素内开始滚动。
  final double edge;

  /// 最大滚动速度（px/s）。
  final double maxSpeed;

  /// 内容真的滚动了之后回调（调用方按需重画）。
  final VoidCallback onScrolled;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _speed = 0;
  ScrollPosition? _position;

  /// 按指针位置更新滚动速度并启停 ticker。
  void update({
    required ScrollPosition? position,
    required RenderBox? viewport,
    required Offset pointer,
  }) {
    if (viewport == null || position == null || !position.hasContentDimensions) {
      stop();
      return;
    }
    final topLeft = viewport.localToGlobal(Offset.zero);
    final top = topLeft.dy;
    final bottom = top + viewport.size.height;
    final zone = math.min(edge, viewport.size.height / 3);
    final y = pointer.dy;
    var speed = 0.0;
    if (y < top + zone) {
      speed = -maxSpeed * ((top + zone - y) / zone).clamp(0.0, 1.0);
    } else if (y > bottom - zone) {
      speed = maxSpeed * ((y - (bottom - zone)) / zone).clamp(0.0, 1.0);
    }
    _speed = speed;
    _position = position;
    if (speed == 0) {
      stop();
      return;
    }
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// 停掉自动滚动。
  void stop() {
    _speed = 0;
    if (_ticker.isActive) _ticker.stop();
  }

  void dispose() => _ticker.dispose();

  void _tick(Duration elapsed) {
    final pos = _position;
    if (pos == null || _speed == 0) {
      stop();
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (dt <= 0 || !pos.hasContentDimensions || !pos.hasViewportDimension) {
      return;
    }
    final target = (pos.pixels + _speed * dt).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() < 0.5) return;
    pos.jumpTo(target);
    onScrolled();
  }
}
