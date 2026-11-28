import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_background.dart';

/// 上课时间：11 节的上下课时刻都能改（默认见 [TimetableStore.defaultSlotStarts]）。
/// 保存后课表轴、导出日历与上课提醒都用新表；「恢复默认」回到默认作息。
Future<void> showSlotTimesSheet(
  BuildContext context, {
  VoidCallback? onSaved,
}) async {
  final starts = List<String>.from(TimetableStore.slotStarts);
  final ends = List<String>.from(TimetableStore.slotEnds);
  var error = '';

  int minutesOf(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 +
        (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  TimeOfDay parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(p[0]) ?? 0,
      minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0,
    );
  }

  String fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> pickTime(
    StateSetter setS,
    int index, {
    required bool start,
  }) async {
    final picked = await showGlassTimePicker(context,
      initialTime: parse(start ? starts[index] : ends[index]),
      title: '第 ${index + 1} 节${start ? '上课' : '下课'}时间',
    );
    if (picked == null) return;
    setS(() {
      if (start) {
        starts[index] = fmt(picked);
      } else {
        ends[index] = fmt(picked);
      }
      error = '';
    });
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        // 11 节 + 标题 + 按钮在矮屏 / 大字体下可能超过一屏：整体可滚动，保存键才点得到
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
          ),
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (ctx, setS) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '上课时间',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    '点时间就能改；课表轴、导出日历与上课提醒都用这份作息。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SemColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: starts.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                '第${i + 1}节',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            _timeChip(
                              starts[i],
                              () => pickTime(setS, i, start: true),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(
                                '–',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SemColors.textMuted,
                                ),
                              ),
                            ),
                            _timeChip(
                              ends[i],
                              () => pickTime(setS, i, start: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        error,
                        style: TextStyle(fontSize: 12, color: SemColors.danger),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () async {
                          await TimetableStore.setSlotTimes();
                          if (ctx.mounted) Navigator.pop(ctx);
                          onSaved?.call();
                        },
                        child: const Text('恢复默认'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          for (var i = 0; i < starts.length; i++) {
                            if (minutesOf(ends[i]) <= minutesOf(starts[i])) {
                              setS(() => error = '第 ${i + 1} 节的下课时间要晚于上课时间');
                              return;
                            }
                          }
                          await TimetableStore.setSlotTimes(
                            starts: starts,
                            ends: ends,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          onSaved?.call();
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 一枚可点的时间胶囊（上课时间面板用）。
Widget _timeChip(String text, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: SemColors.inputFill,
          border: Border.all(color: SemColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13.5)),
      ),
    );

/// 课表背景设置（选图 / 淡显程度 / 恢复默认）。
/// 保存后背景立即在课表页生效（[TtBackground] 变更通知带动重建）。
Future<void> showBackgroundSettingsSheet(
  BuildContext context, {
  VoidCallback? onSaved,
}) async {
  final picker = ImagePicker();
  // 提示画在弹层里：SnackBar 挂在页面 Scaffold 上，会被底部弹层盖住。
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: TtBackground.I,
        builder: (ctx, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '课表背景',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              StatefulBuilder(
                builder: (ctx, setS) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('选择图片'),
                      subtitle: Text(
                        TtBackground.I.path == null ? '从相册选一张图垫在课表底下' : '点按更换',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () async {
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (picked == null) return;
                        final saved = await TtBackground.I.copyIntoAppDir(
                          picked.path,
                        );
                        if (saved == null) {
                          if (ctx.mounted) setS(() => error = '图片保存失败，请换一张再试');
                          return;
                        }
                        if (ctx.mounted) setS(() => error = null);
                        await TtBackground.I.set(saved);
                      },
                    ),
                    if (error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
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
                ),
              ),
              Row(
                children: [
                  const Text('淡显程度', style: TextStyle(fontSize: 13.5)),
                  Expanded(
                    child: Slider(
                      value: TtBackground.I.opacity,
                      min: TtBackground.minOpacity,
                      max: TtBackground.maxOpacity,
                      onChanged: TtBackground.I.path == null
                          ? null
                          : (v) => TtBackground.I.setOpacity(v),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(TtBackground.I.opacity * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restart_alt),
                title: const Text('恢复默认'),
                enabled: TtBackground.I.path != null,
                onTap: () async {
                  await TtBackground.I.set(null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  onSaved?.call();
}
