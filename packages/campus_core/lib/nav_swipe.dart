import 'package:flutter/widgets.dart';

/// 主导航壳（底栏那一层）暴露给**内页**的横滑桥。
///
/// 内页自带左右滑的子页（如「拓展」页的 我的 / 市场）时，滑到自身边界后手指
/// 继续拖，外层主界面的横滑手势已在竞技场里输给了内页（收不到任何回调），
/// 现象是「滑到头就卡住」。这层桥把越界的拖动**镜像**给主界面：主页面、底栏
/// 滑块照常跟手连续滑，松手按主界面同一套规则落格（拖过半换页、快甩借一格），
/// 内页的子页就这样接进主界面的滑动链：
/// `… 工具 ⇄ 拓展·我的 ⇄ 拓展·市场 ⇄ 我的 …`。
abstract class NavSwipeHost {
  /// 内页拖动中的越界量（页为单位：正 = 主界面**下一格**方向、负 = 上一格方向；
  /// 界内拖动传 0——拖回界内越界量归零，主界面位置也跟着弹回锚点）。
  /// 每帧调；主界面第一次收到时记下锚点（起拖时的主界面格）。
  void navDragOver(double over);

  /// 松手：主界面就近落格（快甩且方向与越界一致时借一格）。
  /// 本次拖动没到过界外就是空操作。
  void navDragEnd(double velocityDx);

  /// 手势被抢 / 取消：位置交还底栏自己的弹簧（弹回锚点格）。
  void navDragCancel();
}

/// 把 [NavSwipeHost] 挂到树上：主导航壳在 build 里包一层，内页用 [NavSwipeScope.of] 取。
/// 树上没有它（内页独立运行 / 单测）时 of 返回 null，内页的越界拖动就地吞掉。
class NavSwipeScope extends InheritedWidget {
  const NavSwipeScope({super.key, required this.host, required super.child});

  final NavSwipeHost? host;

  static NavSwipeHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavSwipeScope>()?.host;

  @override
  bool updateShouldNotify(NavSwipeScope oldWidget) => host != oldWidget.host;
}
