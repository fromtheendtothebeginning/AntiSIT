import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_background.dart';

/// 学期周数上限：学期设置的滑块与课表网格的周数都用它。
/// 放在这里是因为「学期设置」弹窗住在本文，课表页引用同一个值，免得两处各写一个 40。
const int kMaxSemesterWeeks = 40;

/// 「课程表设置」二级页：课表相关的设置都收在这一页里。
///
/// 两处入口都进这里：
/// * 课表页 → 更多 → 课程表设置（带上**当前显示的那个学期**）；
/// * 「我的 → 设置 → 课程表设置」（不带学期 → 用课表最近显示过的那个）。
/// 前两项是课表自己的（学期 / 调休），下面由各插件贡献（上课提醒 / 已上完的课淡化）——
/// 插件停用或从清单里删掉，对应的条目自动消失。
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
    if (p.length == 2 && p[0].isNotEmpty && p[1].isNotEmpty) return (p[0], p[1]);
    return AppState.inferSemester(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    // 听 AppState（淡化显示的开关）与注册表（插件增删带来的条目变化）：
    // 少了这个，开关点下去值变了但界面不重绘，看起来像卡住。
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, PluginRegistry.I]),
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final (xnm, xqm) = _target;
    final key = '$xnm-$xqm';
    final tt = TimetableStore.instance.semester(xnm, xqm);
    // 这一页可能改的不是「当前学期」（课表停在别的学期时），所以把是哪个学期写在行上
    final label = TimetableStore.instance.semesterLabel(key) ?? key;
    return Scaffold(
      appBar: AppBar(title: const Text('课程表设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
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
                  onTap: () => showSemesterSettingsSheet(context, xnm, xqm,
                      onSaved: () => setState(() {})),
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: const Text('调休设置'),
                  subtitle: Text(
                    tt.adjustments.isEmpty ? '未设置放假 / 调课规则' : '${tt.adjustments.length} 条调休规则',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAdjustSettingsSheet(context, xnm, xqm,
                      onSaved: () => setState(() {})),
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
                  onTap: () => showSlotTimesSheet(context, onSaved: () => setState(() {})),
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
                  onTap: () => showBackgroundSettingsSheet(context, onSaved: () => setState(() {})),
                ),
                // 由各插件贡献（上课提醒 / 上完的课淡化显示）
                ...PluginRegistry.I.timetableSettingsTiles(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 上课时间：11 节的上下课时刻都能改（默认见 [TimetableStore.defaultSlotStarts]）。
/// 保存后课表轴、导出日历与上课提醒都用新表；「恢复默认」回到默认作息。
Future<void> showSlotTimesSheet(BuildContext context, {VoidCallback? onSaved}) async {
  final starts = List<String>.from(TimetableStore.slotStarts);
  final ends = List<String>.from(TimetableStore.slotEnds);
  var error = '';

  int minutesOf(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  TimeOfDay parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0,
        minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  String fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> pickTime(StateSetter setS, int index, {required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: parse(start ? starts[index] : ends[index]),
      helpText: '第 ${index + 1} 节${start ? '上课' : '下课'}时间',
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
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        // 11 节 + 标题 + 按钮在矮屏 / 大字体下可能超过一屏：整体可滚动，保存键才点得到
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86),
          child: SingleChildScrollView(
            child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('上课时间',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Text('点时间就能改；课表轴、导出日历与上课提醒都用这份作息。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
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
                            child: Text('第${i + 1}节',
                                style: const TextStyle(fontSize: 13))),
                        _timeChip(starts[i], () => pickTime(setS, i, start: true)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('–',
                              style:
                                  TextStyle(fontSize: 13, color: SemColors.textMuted)),
                        ),
                        _timeChip(ends[i], () => pickTime(setS, i, start: false)),
                      ],
                    ),
                  ),
                ),
              ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(error,
                      style: TextStyle(fontSize: 12, color: SemColors.danger)),
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
                      await TimetableStore.setSlotTimes(starts: starts, ends: ends);
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

/// 课表背景设置（选图 / 淡显程度 / 恢复默认）。课表设置二级页专用，
/// 保存后背景立即在课表页生效（[TtBackground] 变更通知带动重建）。
Future<void> showBackgroundSettingsSheet(BuildContext context, {VoidCallback? onSaved}) async {
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
                child: Text('课表背景',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                          style: const TextStyle(fontSize: 12)),
                      onTap: () async {
                        final picked = await picker.pickImage(source: ImageSource.gallery);
                        if (picked == null) return;
                        final saved = await TtBackground.I.copyIntoAppDir(picked.path);
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
                        child: Text(error!,
                            style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.5)),
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
                    child: Text('${(TtBackground.I.opacity * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12)),
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

/// 学期设置（起点 / 周数）。课表页的「学期设置」与上面那个二级页共用这一个弹窗。
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
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('学期设置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
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
                  if (picked != null) setS(() => startDate = TimetableStore.iso(picked));
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
                  SizedBox(width: 40, child: Text('$weekCount 周', textAlign: TextAlign.end)),
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

/// 调休设置（放假 / 调课规则，可从校历图片识别）。
/// 与 [showSemesterSettingsSheet] 一样课表页与二级页共用。
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
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) {
            String desc(TtAdjust a) => a.type == 'off'
                ? '放假（当天无课）'
                : '按周${'一二三四五六日'[a.day]}的课表上课';

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('调休设置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                if (tt.startDate.isEmpty)
                  Text('请先在「学期设置」里设定学期起点，调休规则才能对应到周次。',
                      style: TextStyle(fontSize: 12, color: SemColors.warning)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (tt.adjustments.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('暂无调休规则', textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: SemColors.textMuted)),
                        ),
                      for (final a in tt.adjustments)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(desc(a), style: const TextStyle(fontSize: 14)),
                          subtitle: Text(a.date, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, size: 20, color: SemColors.textMuted),
                            onPressed: () {
                              tt.adjustments.removeWhere((x) => x.date == a.date);
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
                              final picked = await ImagePicker()
                                  .pickImage(source: ImageSource.gallery);
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
                                    TtAdjust(date: r.date, type: r.type, day: r.day ?? 0)
                                ];
                                tt.adjustments = TimetableStore.mergeAdjustments(
                                    tt.adjustments, entries);
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
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.image_search_outlined, size: 18),
                      label: Text(aiBusy ? '识别中…' : '从校历图片识别'),
                    ),
                    const SizedBox(width: 8),
                    if (!(ai?.available ?? false))
                      Flexible(
                        child: Text('未配置 AI：到「我的 → AI 设置」填识图模型后可用',
                            style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      ),
                  ],
                ),
                if (aiMsg != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: aiOk ? SemColors.successSoft : SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(aiMsg!,
                        style: TextStyle(
                            fontSize: 12,
                            color: aiOk ? SemColors.success : SemColors.danger,
                            height: 1.5)),
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
                          context: ctx, initialDate: date ?? now,
                          firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) setS(() => date = picked);
                      },
                      child: Text(date == null ? '选择日期' : TimetableStore.iso(date!)),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx, initialDate: endDate ?? date ?? now,
                          firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) setS(() => endDate = picked);
                      },
                      child: Text(endDate == null ? '结束日期（可选）' : '~ ${TimetableStore.iso(endDate!)}'),
                    ),
                    GlassTabs(
                      labels: const ['放假', '调课'],
                      index: type == 'follow' ? 1 : 0,
                      onChanged: (i) => setS(() => type = i == 1 ? 'follow' : 'off'),
                    ),
                    if (type == 'follow')
                      DropdownButton<int>(
                        value: day,
                        items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text('周${'一二三四五六日'[i]}'))],
                        onChanged: (v) => setS(() => day = v!),
                      ),
                    FilledButton(
                      onPressed: date == null
                          ? null
                          : () {
                              final entries = TimetableStore.expandDateRange(
                                TimetableStore.iso(date!),
                                endDate == null ? null : TimetableStore.iso(endDate!),
                              ).map((d) => TtAdjust(date: TimetableStore.iso(d), type: type, day: day));
                              tt.adjustments = TimetableStore.mergeAdjustments(
                                  tt.adjustments, entries.toList());
                              TimetableStore.instance.save();
                              onSaved?.call();
                              setS(() { date = null; endDate = null; });
                            },
                      child: const Text('添加规则'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('规则在渲染时生效：同一天只会命中一条；「调课」当天的课在原星期列照常显示。',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
              ],
            );
          },
        ),
      ),
    ),
  );
}
