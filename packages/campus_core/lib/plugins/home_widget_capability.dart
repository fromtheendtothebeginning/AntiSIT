import 'capability.dart';

/// 桌面课程卡片的一行（时间已按当前作息换算好）。
class HomeWidgetCourse {
  const HomeWidgetCourse({
    required this.name,
    required this.start,
    required this.end,
    this.place = '',
  });

  final String name;
  final String place;

  /// `HH:mm`（上课 / 下课）。
  final String start;
  final String end;

  Map<String, Object?> toJson() => {
        'name': name,
        'place': place,
        'start': start,
        'end': end,
      };
}

/// 桌面小组件能力（提供方：桌面卡片插件 `PluginIds.homeWidget`）。
///
/// App 侧只负责把「最近一次拿到的数据」同步给原生并触发刷新；
/// 卡片本身由 AppWidgetProvider 渲染，点卡片 / 长按图标的入口动作回传给 [AppLaunch]。
abstract class HomeWidgetCapability extends PluginCapability {
  /// 同步今天的课程（[next] = 最近一节还没下课的课）。
  /// [day] 是 `yyyy-MM-dd`：原生据此判断缓存是不是「今天」的，过期就显示待刷新。
  Future<void> syncTimetable({
    required String day,
    required String date,
    required List<HomeWidgetCourse> courses,
    HomeWidgetCourse? next,
  });

  /// 同步校园卡余额（`null` = 还没拿到）。
  Future<void> syncEcard({String? balance});

  /// 取出启动 / 点击卡片时带进来的入口动作（`ecard` / `timetable`），读完即清。
  Future<String?> takeLaunchAction();
}
