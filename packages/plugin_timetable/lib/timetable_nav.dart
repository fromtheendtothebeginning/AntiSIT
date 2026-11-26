import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 底部周切换悬浮条：上一周 / 「第 N 周」/ 下一周；标题点击由宿主处理（双击回今天）。
Widget buildWeekNav({
  required int shownWeek,
  required int weekCount,
  required VoidCallback? onPrev,
  required VoidCallback? onNext,
  required VoidCallback onTitleTap,
}) {
  return Center(
    child: Container(
      decoration: BoxDecoration(
        color: SemColors.navPill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SemColors.borderStrong),
        boxShadow: [
          BoxShadow(
            color: SemColors.accent.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _navBtn(Icons.chevron_left, onPrev),
          GestureDetector(
            onTap: onTitleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '第 $shownWeek 周',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _navBtn(Icons.chevron_right, onNext),
        ],
      ),
    ),
  );
}

/// 底部日切换悬浮条：上一天 / 「周X · 第 N 周」/ 下一天，翻页交给宿主。
Widget buildDayNav({
  required int shownWeek,
  required int shownDay,
  required int weekCount,
  required void Function(int week, int day) onGoDay,
  required VoidCallback onTitleTap,
}) {
  final idx = (shownWeek - 1) * 7 + shownDay;
  return Center(
    child: Container(
      decoration: BoxDecoration(
        color: SemColors.navPill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SemColors.borderStrong),
        boxShadow: [
          BoxShadow(
            color: SemColors.accent.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _navBtn(
            Icons.chevron_left,
            idx > 0 ? () => onGoDay(idx ~/ 7, idx % 7 - 1) : null,
          ),
          GestureDetector(
            onTap: onTitleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '周${'一二三四五六日'[shownDay]} · 第 $shownWeek 周',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _navBtn(
            Icons.chevron_right,
            idx < weekCount * 7 - 1
                ? () =>
                    onGoDay(idx ~/ 7 + (idx % 7 == 6 ? 1 : 0), (idx + 1) % 7)
                : null,
          ),
        ],
      ),
    ),
  );
}

Widget _navBtn(IconData icon, VoidCallback? onTap) => SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 20,
          color: onTap == null ? SemColors.textMuted : SemColors.textSecondary,
        ),
      ),
    );

/// 课表页顶栏右侧操作：周 / 日切换、上课提醒开关、更多菜单。
List<Widget> buildTimetableActions({
  required bool dayView,
  required VoidCallback onToggleView,
  required ReminderCapability? reminder,
  required VoidCallback onToggleReminder,
  required bool loggedIn,
  required ValueChanged<String> onMenuSelected,
}) {
  return [
    IconButton(
      onPressed: onToggleView,
      icon: Icon(
        dayView
            ? Icons.calendar_view_week_rounded
            : Icons.calendar_view_day_rounded,
      ),
      tooltip: dayView ? '周视图' : '日视图',
    ),
    // 上课提醒由插件提供：能力取不到时整颗按钮都不出现
    if (reminder case final r?)
      glassTopBarAction(
        ListenableBuilder(
          listenable: r.listenable,
          builder: (_, __) => IconButton(
            onPressed: onToggleReminder,
            icon: Icon(
              r.enabled
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined,
            ),
            tooltip: r.enabled
                ? '上课提醒已开启（课前 ${r.leadMinutes} 分钟）'
                : '开启上课提醒（课前 ${r.leadMinutes} 分钟）',
          ),
        ),
      ),
    glassTopBarAction(
      PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: onMenuSelected,
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: 'addCourse',
            child: ListTile(
              leading: Icon(Icons.add),
              title: Text('添加课程'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'addEvent',
            child: ListTile(
              leading: Icon(Icons.schedule_rounded),
              title: Text('添加日程'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'import',
            child: ListTile(
              leading: Icon(Icons.cloud_download_outlined),
              title: Text('教务导入课表'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'exams',
            child: ListTile(
              leading: Icon(Icons.event_note_outlined),
              title: Text('导入考试安排'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'ical',
            child: ListTile(
              leading: Icon(Icons.ios_share_rounded),
              title: Text('导出 / 导入日历'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'settings',
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('课程表设置'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'switch',
            child: ListTile(
              leading: Icon(Icons.calendar_month_outlined),
              title: Text('切换学期'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          if (loggedIn)
            const PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('刷新本周'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
        ],
      ),
    ),
  ];
}
