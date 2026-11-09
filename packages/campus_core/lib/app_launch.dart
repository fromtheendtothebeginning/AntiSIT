import 'dart:async';

/// 桌面快捷方式 / 小组件点进 App 时的入口动作（`ecard` / `timetable`）。
///
/// 原生把动作经 `antisit/home_widget` 通道送进来，插件转发到这里；
/// 主界面订阅 [actions] 切页，冷启动先到的动作先存在 [takePending]。
class AppLaunch {
  AppLaunch._();
  static final AppLaunch I = AppLaunch._();

  final _controller = StreamController<String>.broadcast();
  String? _pending;

  Stream<String> get actions => _controller.stream;

  /// 还没被主界面消费的动作（App 启动时动作比主界面先就绪）。
  String? takePending() {
    final action = _pending;
    _pending = null;
    return action;
  }

  void post(String action) {
    if (action.isEmpty) return;
    _pending = action;
    _controller.add(action);
  }
}
