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
                _dropdown<int>(
                    '星期',
                    day,
                    [
                      for (var i = 0; i < 7; i++) (i, '周${'一二三四五六日'[i]}'),
                    ],
                    (v) => setS(() => day = v)),
                _dropdown<int>(
                    '开始',
                    slotStart,
                    [
                      for (var i = 0; i < 11; i++) (i, '第${i + 1}节'),
                    ],
                    (v) => setS(() => slotStart = v)),
                _dropdown<int>(
                    '结束',
                    slotEnd,
                    [
                      for (var i = 0; i < 11; i++) (i, '第${i + 1}节'),
                    ],
                    (v) => setS(() => slotEnd = v)),
                _dropdown<String>(
                    '周次',
                    weekType,
                    const [
                      ('all', '每周'),
                      ('odd', '单周'),
                      ('even', '双周'),
                    ],
                    (v) => setS(() => weekType = v)),
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
                    final i = tt.courses.indexWhere(
                      (c) => c.id == existing.id,
                    );
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
) =>
    DropdownButton<T>(
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

/// 日程表单：单次（选日期）或每周重复，保存后写入本地日程。
/// 返回是否保存成功，由宿主刷新界面。
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
  var weekly = existing != null && existing.date.isEmpty;
  var day = existing?.day ?? 0;
  TimeOfDay start =
      _toTOD(existing?.start) ?? const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay end =
      _toTOD(existing?.end) ?? const TimeOfDay(hour: 20, minute: 0);
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
              decoration: const InputDecoration(
                labelText: '地点',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            GlassTabs(
              labels: const ['单次（选日期）', '每周重复'],
              index: weekly ? 1 : 0,
              onChanged: (i) => setS(() => weekly = i == 1),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (weekly)
                  Expanded(
                    child: DropdownButtonFormField<int>(
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
                        if (picked != null) setS(() => date = picked);
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
            TextField(
              controller: noteC,
              decoration: const InputDecoration(
                labelText: '备注',
                isDense: true,
              ),
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
                  if (name.isEmpty || (!weekly && date == null)) {
                    setS(
                      () => error = name.isEmpty ? '请填写日程名称' : '单次日程需要选择日期',
                    );
                    return;
                  }
                  final ev = TtEvent(
                    id: existing?.id ?? TimetableStore.genId(),
                    name: name,
                    place: placeC.text.trim(),
                    date: weekly ? '' : TimetableStore.iso(date!),
                    day: weekly ? day : (date!.weekday - 1),
                    start:
                        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                    end:
                        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                    note: noteC.text.trim(),
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

/// 'HH:mm' → [TimeOfDay]；格式不对返回 null。
TimeOfDay? _toTOD(String? s) {
  final m = hm(s ?? '');
  if (m < 0) return null;
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}
