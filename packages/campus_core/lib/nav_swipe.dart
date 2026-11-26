import 'package:flutter/widgets.dart';

/// 主导航壳暴露给内页的横滑桥：内页滑到自身边界后，把越界拖动镜像给主界面。
/// 主页面与底栏滑块因此跟手连续滑，松手按主界面同一套规则落格（拖过半换页、快甩借一格）。
abstract class NavSwipeHost {
  /// 内页拖动中的越界量（页为单位：正 = 下一格方向、负 = 上一格方向；界内传 0）。
  void navDragOver(double over);

  /// 松手：主界面就近落格（快甩且方向与越界一致时借一格）。
  void navDragEnd(double velocityDx);

  /// 手势被抢 / 取消：位置交还底栏弹簧，弹回锚点格。
  void navDragCancel();
}

/// 把 [NavSwipeHost] 挂到树上：主导航壳包一层，内页用 [NavSwipeScope.of] 取。
class NavSwipeScope extends InheritedWidget {
  const NavSwipeScope({super.key, required this.host, required super.child});

  final NavSwipeHost? host;

  /// 取当前挂载的桥；树上没有它（独立运行 / 单测）时返回 null。
  static NavSwipeHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavSwipeScope>()?.host;

  @override
  bool updateShouldNotify(NavSwipeScope oldWidget) => host != oldWidget.host;
}
