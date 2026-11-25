import 'dart:async';

/// 桌面快捷方式 / 小组件点进 App 时的入口动作（`ecard` / `timetable`）。
class AppLaunch {
  AppLaunch._();
  static final AppLaunch I = AppLaunch._();

  final _controller = StreamController<String>.broadcast();
  String? _pending;

  /// 主界面订阅的动作流。
  Stream<String> get actions => _controller.stream;

  /// 取走还没被主界面消费的动作（冷启动时动作比主界面先就绪）。
  String? takePending() {
    final action = _pending;
    _pending = null;
    return action;
  }

  /// 投递一个入口动作：空串忽略，同时记为待消费。
  void post(String action) {
    if (action.isEmpty) return;
    _pending = action;
    _controller.add(action);
  }
}
