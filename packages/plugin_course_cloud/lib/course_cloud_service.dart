import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/widgets.dart';

/// 课程通知方式（与 [AppState.courseNotifyMode] 的字符串一一对应）。
abstract final class CourseNotifyMode {
  /// 不通知：课程通知全部关闭（日程 / 考试提醒不受影响）。
  static const none = 'none';

  /// 弹窗通知：原有「上课提醒」的系统通知。
  static const popup = 'popup';

  /// 流体云通知：课前亮起常驻倒计时，下课前收起。
  static const cloud = 'cloud';

  static String label(String mode) => switch (mode) {
        none => '不通知',
        cloud => '流体云通知',
        _ => '弹窗通知',
      };
}

/// 能力实现：课表保存后调它重排流体云（[TimetableStore] 按插件 id 取用）。
class CourseCloudSyncImpl implements CourseCloudCapability {
  const CourseCloudSyncImpl();

  @override
  Future<void> sync() => CourseCloudService.I.sync();
}

/// 「流体云课程通知」的调度中心。
///
/// 三选一里的**流体云**模式由它负责：从课程表算出未来 7 天的课程窗口，
/// 整批交给 [FluidCloudCapability] 用原生闹钟排期；其它模式把已排的窗口清掉。
/// 课程通知的**弹窗**模式仍归「上课提醒」插件，两边靠 [AppState.courseNotifyMode] 互斥。
class CourseCloudService with WidgetsBindingObserver {
  CourseCloudService._();
  static final CourseCloudService I = CourseCloudService._();

  bool _attached = false;

  /// 监听前后台：回到前台时对一次排期——过期的窗口会被清掉，正在上的课补亮。
  void attach() {
    if (_attached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    } catch (_) {
      // 测试环境没有 WidgetsBinding：跳过
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  /// 课前多少分钟亮起（与上课提醒一致）。
  static const int leadMinutes = 15;

  /// 只排未来这么多天（与上课提醒一致，控制原生闹钟数量）。
  static const int horizonDays = 7;

  /// 最多排多少个窗口。
  static const int maxWindows = 60;

  FluidCloudCapability? get _cloud =>
      PluginRegistry.I.capability<FluidCloudCapability>(PluginIds.fluidCloud);

  ReminderCapability? get _reminder =>
      PluginRegistry.I.capability<ReminderCapability>(PluginIds.reminder);

  /// 按当前模式同步：流体云模式重排窗口，其它模式清空。
  Future<void> sync() async {
    final cloud = _cloud;
    if (cloud == null) return;
    if (AppState.I.courseNotifyMode != CourseNotifyMode.cloud) {
      await cloud.clear();
      return;
    }
    await cloud.schedule(planWindows(TimetableStore.instance, DateTime.now()));
  }

  /// 切换课程通知方式：落盘 → 申请通知权限（流体云）→ 重排两边。
  Future<void> setMode(String mode) async {
    if (mode != CourseNotifyMode.none &&
        mode != CourseNotifyMode.popup &&
        mode != CourseNotifyMode.cloud) {
      return;
    }
    await AppState.I.setCourseNotifyMode(mode);
    if (mode == CourseNotifyMode.cloud) {
      await _cloud?.requestPermission();
    }
    await sync();
    // 上课提醒按新模式重排：不通知 / 流体云时它跳过课程通知，只留日程与考试
    await _reminder?.reschedule();
  }

  /// 立刻亮一条 1 分钟的窗口（设置面板里预览流体云样式用）。
  /// 返回 false = 系统没让发（通知权限 / 渠道被关），调用方给用户一句提示。
  Future<bool> preview() async {
    final cloud = _cloud;
    if (cloud == null) return false;
    final info = await cloud.info();
    if (!info.notificationsEnabled) {
      // 权限弹窗是异步的：授完权 info 可能还没刷新，仍然尝试发一次，
      // 成功了就成功，失败了调用方会给提示。
      await cloud.requestPermission();
    }
    final now = DateTime.now();
    return cloud.show(FluidCloudWindow(
      id: 'preview',
      title: '预览：高等数学',
      subtitle: '二教E101 · 演示',
      startAt: now.millisecondsSinceEpoch,
      endAt: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      leadMinutes: 0,
    ));
  }

  /// 未来 [horizonDays] 天内的课程窗口（纯函数，便于测试）。
  ///
  /// 与课表页 / 上课提醒同一套规则：按调休换算后的实际上课日、单双周、节次起止
  /// （[TimetableStore.slotStarts] / [slotEnds]，用户改过作息就用改过的）。
  /// 已经开始但还没下课的课也会收进来——切到流体云模式时能立刻亮当前这节。
  static List<FluidCloudWindow> planWindows(
    TimetableStore store,
    DateTime now, {
    int lead = leadMinutes,
    int horizon = horizonDays,
    int max = maxWindows,
  }) {
    final starts = [for (final s in TimetableStore.slotStarts) _minutes(s)];
    final ends = [for (final s in TimetableStore.slotEnds) _minutes(s)];
    if (starts.isEmpty || ends.isEmpty) return const [];
    final until = now.add(Duration(days: horizon));
    final out = <FluidCloudWindow>[];
    final seen = <String>{};

    for (final tt in store.semesters.values) {
      final start = DateTime.tryParse(tt.startDate);
      if (start == null || tt.weekCount <= 0) continue;
      final courses = TimetableStore.deriveImported(tt).followedBy(tt.courses).toList();
      for (var w = 1; w <= tt.weekCount; w++) {
        for (var di = 0; di < 7; di++) {
          final eff = _effectiveDay(tt, w, di);
          if (eff == null) continue; // 调休放假
          for (final c in courses) {
            if (c.name.trim().isEmpty || c.day != eff || !_meetsIn(c, w)) continue;
            final day = _dateOfWeekWeek(start, w, di);
            final s = c.slotStart.clamp(0, starts.length - 1);
            final e = c.slotEnd.clamp(s, ends.length - 1);
            final startAt = day.add(Duration(minutes: starts[s]));
            final endAt = day.add(Duration(minutes: ends[e]));
            if (!endAt.isAfter(now) || !startAt.isBefore(until)) continue;
            final key = '${c.name}|${c.place}|${startAt.toIso8601String()}';
            if (!seen.add(key)) continue;
            final range = '${_hhmm(starts[s])}–${_hhmm(ends[e])}';
            out.add(FluidCloudWindow(
              id: '${c.name}|${c.day}|${c.slotStart}|${startAt.millisecondsSinceEpoch}',
              title: c.name,
              subtitle: c.place.trim().isEmpty ? range : '${c.place.trim()} · $range',
              startAt: startAt.millisecondsSinceEpoch,
              endAt: endAt.millisecondsSinceEpoch,
              leadMinutes: lead,
            ));
          }
        }
      }
    }
    out.sort((a, b) => a.startAt.compareTo(b.startAt));
    return out.length > max ? out.sublist(0, max) : out;
  }

  /// 该课在第 [week] 周是否开课（周次范围 + 单双周），与上课提醒一致。
  static bool _meetsIn(TtCourse c, int week) {
    if (week < c.weekStart || week > c.weekEnd) return false;
    return switch (c.weekType) {
      'odd' => week.isOdd,
      'even' => week.isEven,
      _ => true,
    };
  }

  /// 第 [week] 周第 [dayIndex] 列实际按星期几上课；放假返回 null（与课表页同规则）。
  static int? _effectiveDay(SemesterTt tt, int week, int dayIndex) {
    if (tt.startDate.isEmpty) return dayIndex;
    final iso = TimetableStore.iso(TimetableStore.dateOfWeekDay(tt.startDate, week, dayIndex));
    for (final a in tt.adjustments) {
      if (a.date != iso) continue;
      return a.type == 'off' ? null : a.day;
    }
    return dayIndex;
  }

  static DateTime _dateOfWeekWeek(DateTime startDate, int week, int dayIndex) =>
      DateTime(startDate.year, startDate.month, startDate.day)
          .add(Duration(days: (week - 1) * 7 + dayIndex));

  static int _minutes(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}
