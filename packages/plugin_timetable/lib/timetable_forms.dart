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
                existing == null ? '添加日程' : '编辑日程',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                labelText: '名称 *',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: placeC,
              decoration: const InputDecoration(labelText: '地点', isDense: true),
            ),
            const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
                  // 切到每月时把锚点日记到 repeatStart 上（每月几号由它定）
                  if (repeat == TtEvent.repeatMonthly && repeatStart != null) {
                    day = repeatStart!.weekday - 1;
                  }
                }),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (repeating)
                  Expanded(
                    child: repeat == TtEvent.repeatMonthly
                        ? OutlinedButton(
                            onPressed: () => _pickRepeatStart(
                              ctx,
                              tt,
                              current: repeatStart,
                              onPicked: (d) => setS(() {
                                repeatStart = d;
                                day = d.weekday - 1;
                              }),
                            ),
                            child: Text(
                              repeatStart == null
                                  ? '每月几号 *'
                                  : '每月 ${repeatStart!.day} 号',
                            ),
                          )
                        : DropdownButtonFormField<int>(
                            initialValue: day,
                            decoration: const InputDecoration(
                              labelText: '星期',
                              isDense: true,
                            ),
                            items: [
                              for (var i = 0; i < 7; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text('周${'一二三四五六日'[i]}'),
                                ),
                            ],
                            onChanged: (v) => setS(() => day = v!),
                          ),
                  )
                else
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) {
                          setS(() {
                            date = picked;
                            day = picked.weekday - 1;
                          });
                        }
                      },
                      child: Text(
                        date == null ? '选择日期 *' : TimetableStore.iso(date!),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: start,
                      );
                      if (t != null) setS(() => start = t);
                    },
                    child: Text('开始 ${start.format(ctx)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: end,
                      );
                      if (t != null) setS(() => end = t);
                    },
                    child: Text('结束 ${end.format(ctx)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (repeating) ...[
              // 循环起止：开始默认学期起点，结束留空 = 不限（排到学期末）
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickRepeatStart(
                        ctx,
                        tt,
                        current: repeatStart,
                        onPicked: (d) => setS(() {
                          // 「从哪天开始循环」和「每周几」是两件事：改开始日期
                          // 不该顺手改掉用户选的星期（原来这里会覆盖）。
                          repeatStart = d;
                        }),
                      ),
                      child: Text(
                        repeatStart == null
                            ? '开始 不限'
                            : '开始 ${TimetableStore.iso(repeatStart!)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: repeatEnd ?? repeatStart ?? now,
                                firstDate: DateTime(now.year - 1),
                                lastDate: DateTime(now.year + 2),
                              );
                              if (picked != null) {
                                setS(() => repeatEnd = picked);
                              }
                            },
                            child: Text(
                              repeatEnd == null
                                  ? '结束 不限'
                                  : '结束 ${TimetableStore.iso(repeatEnd!)}',
                            ),
                          ),
                        ),
                        if (repeatEnd != null)
                          IconButton(
                            tooltip: '清空结束日期（不限）',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setS(() => repeatEnd = null),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: noteC,
              decoration: const InputDecoration(labelText: '备注', isDense: true),
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
                  if (name.isEmpty || (!repeating && date == null)) {
                    setS(() => error = name.isEmpty ? '请填写日程名称' : '单次日程需要选择日期');
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
                  String hhmm(TimeOfDay t) =>
                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
                    final i = tt.events.indexWhere((x) => x.id == existing.id);
                    if (i >= 0) tt.events[i] = ev;
                  } else {
                    tt.events.add(ev);
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

/// 重复类型 → 「每周 / 每两周 / 每月」那一排的段位。
int _repeatTabIndex(String repeat) => switch (repeat) {
  TtEvent.repeatBiweekly => 1,
  TtEvent.repeatMonthly => 2,
  _ => 0,
};

/// 选「循环开始」日期：默认学期起点，也可清空；每月重复靠它定「几号」。
Future<void> _pickRepeatStart(
  BuildContext ctx,
  SemesterTt tt, {
  required DateTime? current,
  required ValueChanged<DateTime> onPicked,
}) async {
  final now = DateTime.now();
  final base = current ?? DateTime.tryParse(tt.startDate) ?? now;
  final picked = await showDatePicker(
    context: ctx,
    initialDate: base,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 2),
    helpText: '循环从这一天开始',
  );
  if (picked != null) onPicked(picked);
}

/// 'HH:mm' → [TimeOfDay]；格式不对返回 null。
TimeOfDay? _toTOD(String? s) {
  final m = hm(s ?? '');
  if (m < 0) return null;
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}
