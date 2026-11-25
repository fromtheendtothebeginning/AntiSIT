import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_background.dart';
import 'timetable_display_sheets.dart';
import 'timetable_semester_sheets.dart';

/// 「课程表设置」二级页：学期 / 调休 / 上课时间 / 背景，后面是各插件贡献的条目。
/// 插件停用或从清单删掉，对应条目自动消失。
class TimetableSettingsPage extends StatefulWidget {
  const TimetableSettingsPage({super.key, this.semesterKey});

  /// 目标学期（`学年-学期码`，如 `2026-3`）。留空时用课表最近显示过的学期。
  final String? semesterKey;

  @override
  State<TimetableSettingsPage> createState() => _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends State<TimetableSettingsPage> {
  /// 该改哪个学期：课表页进来时用它在显示的那个；从「我的」进来用课表最近显示过的
  /// （课表页每次切换学期都会写进 [TimetableStore.active]），都没有才按今天推断。
  (String, String) get _target {
    final p = (widget.semesterKey ?? TimetableStore.instance.active).split('-');
    if (p.length == 2 && p[0].isNotEmpty && p[1].isNotEmpty) {
      return (p[0], p[1]);
    }
    return AppState.inferSemester(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    // 听 AppState（淡化显示 / 悬浮玻璃顶栏）与注册表（插件增删）,否则开关点了界面不重绘
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, PluginRegistry.I]),
      builder: (context, _) {
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已被扣掉状态栏）
        final topInset = glassTopInset(context);
        return _body(context, topInset);
      },
    );
  }

  Widget _body(BuildContext context, double topInset) {
    final (xnm, xqm) = _target;
    final key = '$xnm-$xqm';
    final tt = TimetableStore.instance.semester(xnm, xqm);
    // 这一页可能改的不是「当前学期」（课表停在别的学期时），所以把是哪个学期写在行上
    final label = TimetableStore.instance.semesterLabel(key) ?? key;
    return Scaffold(
      // 顶栏是悬浮玻璃条：内容从它底下穿过去，渐变模糊才有东西可糊
      extendBodyBehindAppBar: glassTopBarEnabled,
      appBar: glassAppBar(context, title: const Text('课程表设置')),
      body: GlassFadedBody(
        barHeight: topInset,
        child: ListView(
          // 顶部让出悬浮顶栏
          padding: EdgeInsets.fromLTRB(12, 4 + topInset, 12, 24),
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('学期设置'),
                    subtitle: Text(
                      '$label · ${tt.startDate.isEmpty ? '未设置学期起点' : '起点 ${tt.startDate} · 共 ${tt.weekCount} 周'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showSemesterSettingsSheet(
                      context,
                      xnm,
                      xqm,
                      onSaved: () => setState(() {}),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: const Text('调休设置'),
                    subtitle: Text(
                      tt.adjustments.isEmpty
                          ? '未设置放假 / 调课规则'
                          : '${tt.adjustments.length} 条调休规则',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showAdjustSettingsSheet(
                      context,
                      xnm,
                      xqm,
                      onSaved: () => setState(() {}),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('上课时间'),
                    subtitle: Text(
                      '${TimetableStore.slotTimesCustomized ? '自定义' : '默认'}作息 · '
                      '第 1 节 ${TimetableStore.slotStarts.first} 起',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showSlotTimesSheet(
                      context,
                      onSaved: () => setState(() {}),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.wallpaper_outlined),
                    title: const Text('课表背景'),
                    subtitle: Text(
                      TtBackground.I.path == null
                          ? '默认（跟随主题底色）'
                          : '自定义图片 · 淡显 ${(TtBackground.I.opacity * 100).round()}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showBackgroundSettingsSheet(
                      context,
                      onSaved: () => setState(() {}),
                    ),
                  ),
                  // 由各插件贡献（上课提醒 / 上完的课淡化显示）
                  ...PluginRegistry.I.timetableSettingsTiles(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
