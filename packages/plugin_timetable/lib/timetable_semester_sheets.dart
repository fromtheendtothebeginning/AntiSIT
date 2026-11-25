import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:campus_core/campus_core.dart';

/// 学期周数上限：学期设置的滑块与课表网格的周数都用它。
const int kMaxSemesterWeeks = 40;

/// 学期设置（起点 / 周数）：课表页与「课程表设置」二级页共用同一个弹窗。
/// [onSaved] 保存后回调，宿主页面拿它刷新自己的摘要。
Future<void> showSemesterSettingsSheet(
  BuildContext context,
  String xnm,
  String xqm, {
  VoidCallback? onSaved,
}) async {
  final tt = TimetableStore.instance.semester(xnm, xqm);
  var startDate = tt.startDate;
  var weekCount = tt.weekCount;
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
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '学期设置',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('学期起点（第 1 周周一）'),
                subtitle: Text(startDate.isEmpty ? '未设置' : startDate),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final init = DateTime.tryParse(startDate) ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: init,
                    firstDate: DateTime(init.year - 1),
                    lastDate: DateTime(init.year + 1),
                  );
                  if (picked != null) {
                    setS(() => startDate = TimetableStore.iso(picked));
                  }
                },
              ),
              Row(
                children: [
                  const Text('学期周数'),
                  Expanded(
                    child: Slider(
                      value: weekCount.toDouble(),
                      min: 1,
                      max: kMaxSemesterWeeks.toDouble(),
                      divisions: kMaxSemesterWeeks - 1,
                      label: '$weekCount',
                      onChanged: (v) => setS(() => weekCount = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('$weekCount 周', textAlign: TextAlign.end),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    tt.startDate = startDate;
                    tt.weekCount = weekCount.clamp(1, kMaxSemesterWeeks);
                    TimetableStore.instance.save();
                    Navigator.pop(ctx);
                    onSaved?.call();
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 调休设置（放假 / 调课规则，可从校历图片识别）；与学期设置一样两处共用。
Future<void> showAdjustSettingsSheet(
  BuildContext context,
  String xnm,
  String xqm, {
  VoidCallback? onSaved,
}) async {
  final tt = TimetableStore.instance.semester(xnm, xqm);
  final ai = PluginRegistry.I.capability<AiCapability>(PluginIds.ai);
  DateTime? date;
  DateTime? endDate;
  var type = 'off';
  var day = 0;
  // AI 从校历图片识别调休的临时状态（只在本次弹窗内有效）
  var aiBusy = false;
  String? aiMsg;
  var aiOk = false;
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
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) {
            String desc(TtAdjust a) =>
                a.type == 'off' ? '放假（当天无课）' : '按周${'一二三四五六日'[a.day]}的课表上课';

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '调休设置',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (tt.startDate.isEmpty)
                  Text(
                    '请先在「学期设置」里设定学期起点，调休规则才能对应到周次。',
                    style: TextStyle(fontSize: 12, color: SemColors.warning),
                  ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (tt.adjustments.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            '暂无调休规则',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: SemColors.textMuted,
                            ),
                          ),
                        ),
                      for (final a in tt.adjustments)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            desc(a),
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            a.date,
                            style: TextStyle(
                              fontSize: 12,
                              color: SemColors.textMuted,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: SemColors.textMuted,
                            ),
                            onPressed: () {
                              tt.adjustments.removeWhere(
                                (x) => x.date == a.date,
                              );
                              TimetableStore.instance.save();
                              onSaved?.call();
                              setS(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                // 从校历图片识别调休（需先在「我的 → AI 设置」配识图模型）
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: (aiBusy || tt.startDate.isEmpty)
                          ? null
                          : () async {
                              final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                              );
                              if (picked == null) return;
                              final bytes = await picked.readAsBytes();
                              setS(() {
                                aiBusy = true;
                                aiMsg = null;
                                aiOk = false;
                              });
                              try {
                                final rules = await ai!.parseHolidayImage(
                                  bytes,
                                  startDate: tt.startDate,
                                  weekCount: tt.weekCount,
                                  mime: picked.mimeType ?? 'image/png',
                                );
                                if (rules.isEmpty) {
                                  setS(() {
                                    aiMsg = '没能从图片里识别出调休安排，换个更清晰的校历截图试试';
                                    aiOk = false;
                                  });
                                  return;
                                }
                                final entries = [
                                  for (final r in rules)
                                    TtAdjust(
                                      date: r.date,
                                      type: r.type,
                                      day: r.day ?? 0,
                                    ),
                                ];
                                tt.adjustments =
                                    TimetableStore.mergeAdjustments(
                                  tt.adjustments,
                                  entries,
                                );
                                TimetableStore.instance.save();
                                onSaved?.call();
                                setS(() {
                                  aiMsg = '已识别 ${rules.length} 条并写入规则';
                                  aiOk = true;
                                });
                              } catch (e) {
                                setS(() {
                                  aiMsg = e is ApiError ? e.message : '$e';
                                  aiOk = false;
                                });
                              } finally {
                                setS(() => aiBusy = false);
                              }
                            },
                      icon: aiBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_search_outlined, size: 18),
                      label: Text(aiBusy ? '识别中…' : '从校历图片识别'),
                    ),
                    const SizedBox(width: 8),
                    if (!(ai?.available ?? false))
                      Flexible(
                        child: Text(
                          '未配置 AI：到「我的 → AI 设置」填识图模型后可用',
                          style: TextStyle(
                            fontSize: 11,
                            color: SemColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
                if (aiMsg != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          aiOk ? SemColors.successSoft : SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      aiMsg!,
                      style: TextStyle(
                        fontSize: 12,
                        color: aiOk ? SemColors.success : SemColors.danger,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
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
                        date == null ? '选择日期' : TimetableStore.iso(date!),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: endDate ?? date ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) setS(() => endDate = picked);
                      },
                      child: Text(
                        endDate == null
                            ? '结束日期（可选）'
                            : '~ ${TimetableStore.iso(endDate!)}',
                      ),
                    ),
                    GlassTabs(
                      labels: const ['放假', '调课'],
                      index: type == 'follow' ? 1 : 0,
                      onChanged: (i) =>
                          setS(() => type = i == 1 ? 'follow' : 'off'),
                    ),
                    if (type == 'follow')
                      DropdownButton<int>(
                        value: day,
                        items: [
                          for (var i = 0; i < 7; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text('周${'一二三四五六日'[i]}'),
                            ),
                        ],
                        onChanged: (v) => setS(() => day = v!),
                      ),
                    FilledButton(
                      onPressed: date == null
                          ? null
                          : () {
                              final entries = TimetableStore.expandDateRange(
                                TimetableStore.iso(date!),
                                endDate == null
                                    ? null
                                    : TimetableStore.iso(endDate!),
                              ).map(
                                (d) => TtAdjust(
                                  date: TimetableStore.iso(d),
                                  type: type,
                                  day: day,
                                ),
                              );
                              tt.adjustments = TimetableStore.mergeAdjustments(
                                tt.adjustments,
                                entries.toList(),
                              );
                              TimetableStore.instance.save();
                              onSaved?.call();
                              setS(() {
                                date = null;
                                endDate = null;
                              });
                            },
                      child: const Text('添加规则'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '规则在渲染时生效：同一天只会命中一条；「调课」当天的课在原星期列照常显示。',
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
