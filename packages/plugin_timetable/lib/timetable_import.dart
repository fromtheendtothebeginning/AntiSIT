import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_semester_sheets.dart';

/// 需要登录的功能先过这一关：未登录时给一句提示并返回 false。
bool ensureLoggedIn(BuildContext context) {
  if (AppState.I.loggedIn) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppState.I.direct ? '该功能需要先在「连接设置 → 直连模式」填写校园凭据' : '该功能需要先登录服务器账号',
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
  return false;
}

/// 拉取某周教务课表并入本地 store（未登录、已缓存且非强制、正在加载时都跳过）。
Future<void> ensureSemesterWeek(
  BuildContext context, {
  required String xnm,
  required String xqm,
  required SemesterTt tt,
  required int week,
  required int maxWeeks,
  required Set<int> loadingWeeks,
  required VoidCallback onChanged,
  bool force = false,
}) async {
  if (week < 1 || week > maxWeeks) return;
  if (!AppState.I.loggedIn) return;
  if (!force &&
      (tt.jwxtWeeks.containsKey('$week') || loadingWeeks.contains(week))) {
    return;
  }
  loadingWeeks.add(week);
  onChanged();
  try {
    final resp = await ApiClient.I.timetableWeek(xnm, xqm, week);
    storeSemesterWeek(tt, week, resp);
  } on ApiError catch (e) {
    if (!e.message.contains('没有课表') && context.mounted) {
      showErr(context, e, title: '课表加载失败');
    }
  } catch (e) {
    if (context.mounted) showErr(context, e, title: '课表加载失败');
  } finally {
    loadingWeeks.remove(week);
    onChanged();
  }
}

/// 把一周的教务响应并入本地 store：课程、学期起点（第 1 周）与年级。
void storeSemesterWeek(SemesterTt tt, int week, Map<String, dynamic> resp) {
  tt.jwxtWeeks['$week'] = ((resp['courses'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(TtCourse.fromJson)
      .toList();
  if (week == 1 && tt.startDate.isEmpty) {
    for (final d in (resp['dates'] as List?) ?? const []) {
      if ('${(d as Map)['xqj']}' == '1') {
        tt.startDate = '${d['rq']}';
        break;
      }
    }
  }
  final nj = resp['nj'];
  final manual = AppState.I.direct ? AppState.I.creds.grade.trim() : '';
  if (manual.isNotEmpty) {
    // 直连模式手填的年级优先：教务没回或回的年级不合用时以用户填的为准。
    TimetableStore.instance.nj = manual;
  } else if (nj is String && nj.isNotEmpty) {
    TimetableStore.instance.nj = nj; // 内部会 persist
  } else {
    TimetableStore.instance.save();
  }
  fixSemesterWeekCount(tt);
}

/// 学期周数按教务数据里的最大周次补齐。
void fixSemesterWeekCount(SemesterTt tt) {
  final maxWeek = tt.jwxtWeeks.keys
      .map(int.tryParse)
      .whereType<int>()
      .fold(0, (a, b) => b > a ? b : a);
  if (maxWeek > tt.weekCount) {
    tt.weekCount = maxWeek.clamp(1, kMaxSemesterWeeks);
    TimetableStore.instance.save();
  }
}

/// 教务全量导入：逐周拉取当前学期课表并覆盖本机教务数据，返回最后成功导入的周次。
Future<int> importSemesterCourses(
  BuildContext context, {
  required String xnm,
  required String xqm,
  required SemesterTt tt,
  required int maxWeeks,
  required VoidCallback onChanged,
}) async {
  if (!ensureLoggedIn(context)) return 0;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('从教务导入课表'),
      content: Text(
        '将逐周拉取当前学期（$xnm 学年${xqm == '3' ? '第一' : '第二'}学期）的全部课表，覆盖本机教务数据。\n手动课程与调休规则会保留。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('开始导入'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return 0;

  tt.jwxtWeeks.clear();
  final progress = ValueNotifier('正在连接教务…');
  final popper = ValueNotifier(false);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ValueListenableBuilder(
          valueListenable: popper,
          builder: (ctx, done, _) => AlertDialog(
            title: Text(done ? '导入完成' : '正在导入'),
            content: ValueListenableBuilder(
              valueListenable: progress,
              builder: (ctx, msg, _) => Row(
                children: [
                  if (!done)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (!done) const SizedBox(width: 12),
                  Expanded(
                    child: Text(msg, style: const TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
            actions: [
              if (done)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('好的'),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  var w = 1;
  var lastWeek = 0;
  String? error;
  while (w <= maxWeeks) {
    progress.value = '正在导入 第 $w 周…';
    try {
      final resp = await ApiClient.I.timetableWeek(xnm, xqm, w);
      storeSemesterWeek(tt, w, resp);
      lastWeek = w;
      w++;
    } on ApiError catch (e) {
      if (!e.message.contains('没有课表')) error = e.message;
      break;
    } catch (e) {
      error = e.toString();
      break;
    }
  }
  if (lastWeek > 0) {
    tt.weekCount = math.max(tt.weekCount, lastWeek).clamp(1, maxWeeks);
    await TimetableStore.instance.save();
  }
  onChanged();
  popper.value = true;
  progress.value = lastWeek > 0
      ? (error == null ? '共导入 $lastWeek 周课表' : '导入到第 $lastWeek 周后中断：$error')
      : '导入失败：$error';
  return lastWeek;
}

/// 导入考试安排为本地日程事件（重复的自动跳过）。
Future<void> importExamEvents(
  BuildContext context, {
  required String xnm,
  required String xqm,
  required SemesterTt tt,
  required VoidCallback onChanged,
}) async {
  if (!ensureLoggedIn(context)) return;
  try {
    final r = await ApiClient.I.exams(xnm, xqm);
    final exams =
        ((r['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final added = TimetableStore.addExamEvents(tt, exams);
    await TimetableStore.instance.save();
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added > 0
              ? '已导入 $added 场考试（跳过 ${exams.length - added} 场）'
              : '没有新的考试可导入',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (e) {
    if (context.mounted) showErr(context, e, title: '考试导入失败');
  }
}

/// 学期选择器：成绩学期列表 + 推断的当前学期 + 本地已有学期；可返回「新建学期」。
Future<({String xnm, String xqm, bool isNew})?> showSemesterPicker(
  BuildContext context, {
  required String xnm,
  required String xqm,
  required List<Map<String, dynamic>>? terms,
  required ValueChanged<List<Map<String, dynamic>>?> onTermsLoaded,
}) async {
  var known = terms;
  if (AppState.I.loggedIn && known == null) {
    try {
      final r = await ApiClient.I.grades();
      known = ((r['data'] as Map?)?['terms'] as List?)
          ?.cast<Map<String, dynamic>>();
      onTermsLoaded(known);
    } catch (_) {}
  }
  // 选项 = 成绩学期列表 + 推断的当前学期 + 本地已有数据的学期
  // （成绩列表里没有当前学期，否则切走后就回不来了）
  final opts = <(String xnm, String xqm, String label)>[];
  void addOpt(String xn, String xq, {String? label}) {
    if (xn.isEmpty || xq.isEmpty) return;
    if (opts.any((o) => o.$1 == xn && o.$2 == xq)) return;
    opts.add((
      xn,
      xq,
      label ??
          '$xn-${int.tryParse(xn) != null ? int.parse(xn) + 1 : '?'}学年 ${xq == '3' ? '第一' : xq == '12' ? '第二' : '短'}学期',
    ));
  }

  final inferred = AppState.inferSemester(DateTime.now());
  addOpt(inferred.$1, inferred.$2);
  for (final t in known ?? const <Map<String, dynamic>>[]) {
    addOpt(
      '${t['xnm']}',
      '${t['xqm']}',
      label: '${t['xnmmc']} ${t['xqmmc']}',
    );
  }
  for (final k in TimetableStore.instance.semesters.keys) {
    final p = k.split('-');
    if (p.length == 2) addOpt(p[0], p[1]);
  }
  opts.sort(
    (a, b) => '${b.$1}-${b.$2}'.compareTo('${a.$1}-${a.$2}'),
  ); // 新 → 旧

  if (!context.mounted) return null;
  final t = await showModalBottomSheet<Object?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '选择学期',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (opts.isEmpty)
              _genericSemesterPicker(ctx, xnm: xnm, xqm: xqm),
            for (final o in opts)
              ListTile(
                title: Text(o.$3),
                trailing: (o.$1 == xnm && o.$2 == xqm)
                    ? Icon(Icons.check, color: SemColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, {'xnm': o.$1, 'xqm': o.$2}),
              ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.add_circle_outline,
                color: SemColors.accent,
              ),
              title: Text('新建学期', style: TextStyle(color: SemColors.accent)),
              subtitle: const Text(
                '建一个空学期，手动排课或稍后从教务导入',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, const {'new': true}),
            ),
          ],
        ),
      ),
    ),
  );
  if (t is Map && t['new'] == true) {
    return (xnm: '', xqm: '', isNew: true);
  }
  String? nxnm, nxqm;
  if (t is Map<String, dynamic>) {
    nxnm = '${t['xnm']}';
    nxqm = '${t['xqm']}';
  } else if (t is List && t.length == 2) {
    nxnm = '${t[0]}';
    nxqm = '${t[1]}';
  }
  if (nxnm == null || nxqm == null) return null;
  return (xnm: nxnm, xqm: nxqm, isNew: false);
}

/// 新建学期选择器：选学年 + 学期码，返回选中的学期（未确认返回 null）。
Future<({String xnm, String xqm})?> showNewSemesterPicker(
  BuildContext context, {
  required String xnm,
  required String xqm,
}) async {
  final created = await showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              '新建学期',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _genericSemesterPicker(
            ctx,
            xnm: xnm,
            xqm: xqm,
            confirmLabel: '创建',
          ),
        ],
      ),
    ),
  );
  if (created == null || created.length != 2) return null;
  if (created[0].isEmpty || created[1].isEmpty) return null;
  return (xnm: created[0], xqm: created[1]);
}

/// 未登录（无学期列表）时的通用选择器：学年 + 学期码。
Widget _genericSemesterPicker(
  BuildContext ctx, {
  required String xnm,
  required String xqm,
  String confirmLabel = '确定',
}) {
  final now = DateTime.now().year;
  final years = [for (var y = now - 3; y <= now; y++) '$y'];
  var year = years.contains(xnm) ? xnm : years.last;
  var xq = xqm;
  return StatefulBuilder(
    builder: (ctx, setS) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: year,
                  decoration: const InputDecoration(
                    labelText: '学年（起始年）',
                    isDense: true,
                  ),
                  items: [
                    for (final y in years)
                      DropdownMenuItem(
                        value: y,
                        child: Text('$y-${int.parse(y) + 1}学年'),
                      ),
                  ],
                  onChanged: (v) => setS(() => year = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: xq,
                  decoration: const InputDecoration(
                    labelText: '学期',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: '3', child: Text('第一学期')),
                    DropdownMenuItem(value: '12', child: Text('第二学期')),
                  ],
                  onChanged: (v) => setS(() => xq = v!),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(ctx, [year, xq]),
            child: Text(confirmLabel),
          ),
        ),
      ],
    ),
  );
}
