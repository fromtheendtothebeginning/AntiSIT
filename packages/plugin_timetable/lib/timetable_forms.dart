import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_geometry.dart';
import 'timetable_semester_sheets.dart';

/// 课程表单：新增 / 编辑；教务课程保存后转为手动课程（并移除对应的教务片段）。
/// 返回是否保存成功，由宿主刷新界面。
Future<bool> showCourseForm(
  BuildContext context, {
  required SemesterTt tt,
  TtCourse? existing,
  bool imported = false,
}) async {
  final weekCount = tt.weekCount.clamp(1, kMaxSemesterWeeks);
  final nameC = TextEditingController(text: existing?.name ?? '');
  final placeC = TextEditingController(text: existing?.place ?? '');
  final teachersC = TextEditingController(text: existing?.teachers ?? '');
  final wsC = TextEditingController(text: '${existing?.weekStart ?? 1}');
  final weC = TextEditingController(
    text: '${existing?.weekEnd ?? tt.weekCount}',
  );
  var day = existing?.day ?? 0;
  var slotStart = existing?.slotStart ?? 0;
  var slotEnd = existing?.slotEnd ?? 1;
  var weekType = existing?.weekType ?? 'all';
  // 校验提示画在弹层里：SnackBar 挂在页面 Scaffold 上，会被底部弹层盖住。
  String? error;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                imported
                    ? '编辑教务课程（保存后转为手动）'
                    : existing == null
                    ? '添加课程'
                    : '编辑课程',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                labelText: '课程名 *',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: placeC,
                    decoration: const InputDecoration(
                      labelText: '地点',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: teachersC,
                    decoration: const InputDecoration(
                      labelText: '教师',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dropdown<int>('星期', day, [
                  for (var i = 0; i < 7; i++) (i, '周${'一二三四五六日'[i]}'),
                ], (v) => setS(() => day = v)),
                _dropdown<int>('开始', slotStart, [
                  for (var i = 0; i < 11; i++) (i, '第${i + 1}节'),
                ], (v) => setS(() => slotStart = v)),
                _dropdown<int>('结束', slotEnd, [
                  for (var i = 0; i < 11; i++) (i, '第${i + 1}节'),
                ], (v) => setS(() => slotEnd = v)),
                _dropdown<String>('周次', weekType, const [
                  ('all', '每周'),
                  ('odd', '单周'),
                  ('even', '双周'),
                ], (v) => setS(() => weekType = v)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: wsC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '开始周',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: weC,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '结束周（共 $weekCount 周）',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SemColors.dangerSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: SemColors.danger,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final name = nameC.text.trim();
                  final ws = int.tryParse(wsC.text.trim()) ?? 0;
                  final we = int.tryParse(weC.text.trim()) ?? 0;
                  if (name.isEmpty ||
                      slotStart > slotEnd ||
                      ws < 1 ||
                      we < ws ||
                      we > weekCount) {
                    setS(
                      () => error = name.isEmpty
                          ? '请填写课程名'
                          : slotStart > slotEnd
                          ? '开始节次不能晚于结束节次'
                          : '周次范围需在 1~$weekCount 周之间',
                    );
                    return;
                  }
                  final data = TtCourse(
                    id: existing?.id ?? TimetableStore.genId(),
                    name: name,
                    place: placeC.text.trim(),
                    teachers: teachersC.text.trim(),
                    day: day,
                    slotStart: slotStart,
                    slotEnd: slotEnd,
                    weekType: weekType,
                    weekStart: ws,
                    weekEnd: we,
                  );
                  if (imported && existing != null) {
                    // 转手动：追加手动课程 + 从教务原始数据移除该段
                    tt.courses.add(data);
                    TimetableStore.removeImportedSegment(tt, existing);
                  } else if (existing != null) {
                    final i = tt.courses.indexWhere((c) => c.id == existing.id);
                    if (i >= 0) tt.courses[i] = data;
                  } else {
                    tt.courses.add(data);
                  }
                  TimetableStore.instance.save();
                  Navigator.pop(ctx, true);
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return saved == true;
}

/// 表单里的小号下拉框（标签直接拼在选项文字前）。
Widget _dropdown<T>(
  String label,
  T value,
  List<(T, String)> items,
  ValueChanged<T> onChanged,
) => DropdownButton<T>(
  value: value,
  items: [
    for (final (v, l) in items)
      DropdownMenuItem(
        value: v,
        child: Text('$label $l', style: const TextStyle(fontSize: 13)),
      ),
  ],
  onChanged: (v) {
    if (v != null) onChanged(v);
  },
  underline: const SizedBox(),
  isDense: true,
);

/// 日程表单：单次（选日期）或重复（每周 / 每两周 / 每月 + 起止日期），
/// 保存后写入本地日程。返回是否保存成功，由宿主刷新界面。
Future<bool> showEventForm(
  BuildContext context, {
  required SemesterTt tt,
  TtEvent? existing,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final placeC = TextEditingController(text: existing?.place ?? '');
  final noteC = TextEditingController(text: existing?.note ?? '');
  DateTime? date = existing == null || existing.date.isEmpty
      ? null
      : DateTime.tryParse(existing.date);
  // 老数据 date 空 = 每周重复（TtEvent.fromJson 已经把 repeat 换算好了）。
  var repeat = existing?.repeat ?? TtEvent.repeatNone;
  var repeating = repeat != TtEvent.repeatNone;
  var day = existing?.day ?? 0;
  // 循环起止：开始缺省 = 学期起点；结束留空 = 不限。
  DateTime? repeatStart =
      DateTime.tryParse(existing?.repeatStart ?? '') ??
      DateTime.tryParse(tt.startDate);
  DateTime? repeatEnd = DateTime.tryParse(existing?.repeatEnd ?? '');
  TimeOfDay start =
      _toTOD(existing?.start) ?? const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay end = _toTOD(existing?.end) ?? const TimeOfDay(hour: 20, minute: 0);
  // 校验提示画在弹层里：SnackBar 挂在页面 Scaffold 上，会被底部弹层盖住。
  String? error;

  String hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: SemColors.menuBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                decoration: BoxDecoration(
                  color: SemColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      existing == null ? '添加日程' : '编辑日程',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassField(
                        label: '名称',
                        controller: nameC,
                        hintText: '例如：组会 / 实验课',
                      ),
                      const SizedBox(height: 10),
                      GlassField(
                        label: '地点',
                        controller: placeC,
                        hintText: '可留空，例如：一教 A201',
                      ),
                      const SizedBox(height: 12),
                      GlassTabs(
                        labels: const ['单次', '重复'],
                        index: repeating ? 1 : 0,
                        onChanged: (i) => setS(() {
                          repeating = i == 1;
                          if (repeating && repeat == TtEvent.repeatNone) {
                            repeat = TtEvent.repeatWeekly;
                          }
                        }),
                      ),
                      if (repeating) ...[
                        const SizedBox(height: 10),
                        GlassTabs(
                          labels: const ['每周', '每两周', '每月'],
                          index: _repeatTabIndex(repeat),
                          height: 30,
                          fontSize: 12,
                          onChanged: (i) => setS(() {
                            repeat = const [
                              TtEvent.repeatWeekly,
                              TtEvent.repeatBiweekly,
                              TtEvent.repeatMonthly,
                            ][i];
                            if (repeat == TtEvent.repeatMonthly &&
                                repeatStart != null) {
                              day = repeatStart!.weekday - 1;
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (!repeating) ...[
                        GlassPicker(
                          label: '日期',
                          value: date == null ? '' : TimetableStore.iso(date!),
                          hint: '选哪一天',
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showGlassDatePicker(
                              ctx,
                              initialDate: date ?? now,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 2),
                              title: '日程日期',
                            );
                            if (picked != null) {
                              setS(() {
                                date = picked;
                                day = picked.weekday - 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                      ] else if (repeat != TtEvent.repeatMonthly) ...[
                        GlassPicker(
                          label: '星期',
                          value: '周${'一二三四五六日'[day]}',
                          onTap: () async {
                            final picked = await showGlassChoiceSheet(
                              ctx,
                              title: '每周几',
                              selected: day,
                              options: [
                                for (var i = 0; i < 7; i++) '周${'一二三四五六日'[i]}',
                              ],
                            );
                            if (picked != null) setS(() => day = picked);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (repeating) ...[
                        GlassPicker(
                          label: repeat == TtEvent.repeatMonthly
                              ? '每月几号'
                              : '开始',
                          value: repeatStart == null
                              ? ''
                              : (repeat == TtEvent.repeatMonthly
                                    ? '每月 ${repeatStart!.day} 号'
                                    : TimetableStore.iso(repeatStart!)),
                          hint: '不限',
                          onTap: () async {
                            final picked = await _pickRepeatStartValue(
                              ctx,
                              tt,
                              repeatStart,
                            );
                            if (picked != null) {
                              setS(() {
                                repeatStart = picked;
                                if (repeat == TtEvent.repeatMonthly) {
                                  day = picked.weekday - 1;
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        GlassPicker(
                          label: '结束',
                          value: repeatEnd == null
                              ? ''
                              : TimetableStore.iso(repeatEnd!),
                          hint: '不限（排到学期末）',
                          helperText: repeatEnd == null ? null : '还想改就再点一次',
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showGlassDatePicker(
                              ctx,
                              initialDate: repeatEnd ?? repeatStart ?? now,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 2),
                              title: '循环到这一天为止',
                            );
                            if (picked != null) setS(() => repeatEnd = picked);
                          },
                        ),
                        if (repeatEnd != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setS(() => repeatEnd = null),
                              child: const Text('清空结束日期'),
                            ),
                          ),
                        const SizedBox(height: 4),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: GlassPicker(
                              label: '开始时间',
                              value: hhmm(start),
                              onTap: () async {
                                final t = await showGlassTimePicker(
                                  ctx,
                                  initialTime: start,
                                  title: '开始时间',
                                );
                                if (t != null) setS(() => start = t);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GlassPicker(
                              label: '结束时间',
                              value: hhmm(end),
                              onTap: () async {
                                final t = await showGlassTimePicker(
                                  ctx,
                                  initialTime: end,
                                  title: '结束时间',
                                );
                                if (t != null) setS(() => end = t);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GlassField(
                        label: '备注',
                        controller: noteC,
                        hintText: '可留空',
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: SemColors.dangerSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            error!,
                            style: TextStyle(
                              fontSize: 12,
                              color: SemColors.danger,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      glassPrimaryButton(
                        label: '保存',
                        onPressed: () {
                          final name = nameC.text.trim();
                          if (name.isEmpty || (!repeating && date == null)) {
                            setS(
                              () => error = name.isEmpty
                                  ? '请填写日程名称'
                                  : '单次日程需要选择日期',
                            );
                            return;
                          }
                          if (repeating &&
                              repeat == TtEvent.repeatMonthly &&
                              repeatStart == null) {
                            setS(() => error = '每月重复需要选一个开始日期（决定每月几号）');
                            return;
                          }
                          if (repeating &&
                              repeatStart != null &&
                              repeatEnd != null &&
                              repeatEnd!.isBefore(repeatStart!)) {
                            setS(() => error = '循环结束日期不能早于开始日期');
                            return;
                          }
                          final ev = TtEvent(
                            id: existing?.id ?? TimetableStore.genId(),
                            name: name,
                            place: placeC.text.trim(),
                            // 重复日程 date 留空（与老数据同一套语义），单次写当天日期。
                            date: repeating ? '' : TimetableStore.iso(date!),
                            day: repeating ? day : (date!.weekday - 1),
                            start: hhmm(start),
                            end: hhmm(end),
                            note: noteC.text.trim(),
                            repeat: repeating ? repeat : TtEvent.repeatNone,
                            repeatStart: !repeating || repeatStart == null
                                ? ''
                                : TimetableStore.iso(repeatStart!),
                            repeatEnd: !repeating || repeatEnd == null
                                ? ''
                                : TimetableStore.iso(repeatEnd!),
                            kind: existing?.kind ?? '',
                            seat: existing?.seat ?? '',
                          );
                          if (existing != null) {
                            final i = tt.events.indexWhere(
                              (x) => x.id == existing.id,
                            );
                            if (i >= 0) tt.events[i] = ev;
                          } else {
                            tt.events.add(ev);
                          }
                          TimetableStore.instance.save();
                          Navigator.pop(ctx, true);
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return saved == true;
}

/// 选「循环开始」日期（每月几号由它定）：返回选中的日期，取消返回 null。
Future<DateTime?> _pickRepeatStartValue(
  BuildContext ctx,
  SemesterTt tt,
  DateTime? current,
) async {
  final now = DateTime.now();
  final base = current ?? DateTime.tryParse(tt.startDate) ?? now;
  return showGlassDatePicker(
    ctx,
    initialDate: base,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 2),
    title: '循环从这一天开始',
  );
}

/// 重复类型 → 「每周 / 每两周 / 每月」那一排的段位。
int _repeatTabIndex(String repeat) => switch (repeat) {
  TtEvent.repeatBiweekly => 1,
  TtEvent.repeatMonthly => 2,
  _ => 0,
};


/// 'HH:mm' → [TimeOfDay]；格式不对返回 null。
TimeOfDay? _toTOD(String? s) {
  final m = hm(s ?? '');
  if (m < 0) return null;
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}
