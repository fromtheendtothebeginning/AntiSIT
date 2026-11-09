import 'package:campus_core/campus_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面卡片能力的实现：走原生通道 `antisit/home_widget`
/// （见 `android/.../HomeWidget.kt`）。
///
/// App 侧只同步「最近一次的数据」，卡片渲染与点击跳转都在原生。
class HomeWidgetCapabilityImpl implements HomeWidgetCapability {
  const HomeWidgetCapabilityImpl();

  static const channel = MethodChannel('antisit/home_widget');

  @override
  Future<void> syncTimetable({
    required String day,
    required String date,
    required List<HomeWidgetCourse> courses,
    HomeWidgetCourse? next,
  }) async {
    try {
      await channel.invokeMethod('syncTimetable', {
        'day': day,
        'date': date,
        'courses': [for (final c in courses) c.toJson()],
        'next': next?.toJson(),
      });
    } on PlatformException catch (e) {
      // 桌面端 / 没声明小组件时直接跳过，不影响课表本身
      assert(() {
        debugPrint('[桌面卡片] 同步课程失败：$e');
        return true;
      }());
    } on MissingPluginException {
      // 非 Android：没有这个通道
    }
  }

  @override
  Future<void> syncEcard({String? balance}) async {
    try {
      await channel.invokeMethod('syncEcard', {'balance': balance});
    } on PlatformException catch (_) {
      // 同上，静默跳过
    } on MissingPluginException {
      // 非 Android
    }
  }

  @override
  Future<String?> takeLaunchAction() async {
    try {
      return await channel.invokeMethod<String>('takeLaunchAction');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
