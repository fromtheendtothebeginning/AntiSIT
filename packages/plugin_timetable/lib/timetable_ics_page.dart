import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:campus_core/campus_core.dart';

/// 「导出 / 导入日历」页：把课表（与日程）导出成 iCalendar（`.ics`，RFC 5545），
/// 也可以把别的日历文件导进来当日程。格式与取舍见 [TimetableIcs]。
///
/// 导出：先选范围（今天 / 本周 / 本月 / 全学期），再**勾选**要导出哪些课程与日程
/// （两边各有全选开关），实时显示会导出多少条，最后交给系统分享（存文件 / 发给别人 /
/// 丢给日历 App），分享不可用时退回复制全文。
///
/// 导入：选一个 `.ics`，解析后按「学期范围内 + 不与已有日程重复」过滤，
/// 先给出预览（导入几条 / 跳过几条 / 有几条复杂重复规则只取了首次），确认后写入日程。
class TimetableIcsPage extends StatefulWidget {
  const TimetableIcsPage({super.key, required this.xnm, required this.xqm});

  final String xnm;
  final String xqm;

  /// 分享实现：默认写临时文件 + 系统分享面板；测试里换掉，避免碰平台通道。
  @visibleForTesting
  static Future<void> Function(String text, String fileName)? shareOverride;

  /// 过滤 + 转成课表的日程（[TtEvent]）：学期范围外丢掉，与已有日程重复的丢掉。
  /// 纯函数，便于单测（选文件那一步要走平台通道，测不了）。
  @visibleForTesting
  static ({List<TtEvent> items, String summary}) planImport(
      List<IcsEvent> parsed, SemesterTt tt) {
    final start = DateTime.tryParse(tt.startDate);
    final end = start?.add(Duration(days: tt.weekCount.clamp(1, 40) * 7));
    final keys = {
      for (final e in tt.events) '${e.date}|${e.name}|${e.start}|${e.end}',
    };
    final items = <TtEvent>[];
    var outside = 0, dup = 0, simplified = 0;
    for (final e in parsed) {
      if (e.simplified) simplified++;
      final d = e.date;
      if (d != null && start != null && end != null && (d.isBefore(start) || !d.isBefore(end))) {
        outside++;
        continue;
      }
      final date = d == null ? '' : TimetableStore.iso(d);
      final start2 = _hhmm(e.startMin);
      final end2 = _hhmm(e.endMin);
      final name = e.summary.trim().isEmpty ? '（未命名日程）' : e.summary.trim();
      final key = '$date|$name|$start2|$end2';
      if (keys.contains(key)) {
        dup++;
        continue;
      }
      keys.add(key);
      items.add(TtEvent(
        id: TimetableStore.genId(),
        name: name,
        place: e.location,
        date: date,
        day: e.weekday,
        start: start2,
        end: end2,
        note: [
          if (e.allDay) '全天',
          if (e.description.isNotEmpty) e.description,
        ].join('\n'),
      ));
    }
    final extras = [
      if (outside > 0) '$outside 条不在本学期范围内',
      if (dup > 0) '$dup 条与已有日程重复',
      if (simplified > 0) '$simplified 条重复规则较复杂，只取了首次',
    ];
    return (
      items: items,
      summary: [
        '文件里共 ${parsed.length} 条事件。',
        if (items.isNotEmpty) '将导入 ${items.length} 条到「日程」（不导入课程）。'
      else
        '没有可导入的日程。',
        if (extras.isNotEmpty) '跳过：${extras.join('；')}。',
        '导入的日程按每周重复或具体日期显示在课表上，可在课表里再编辑 / 删除。',
      ].join('\n'),
    );
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  State<TimetableIcsPage> createState() => _TimetableIcsPageState();
}

class _TimetableIcsPageState extends State<TimetableIcsPage> {
  SemesterTt get tt => TimetableStore.instance.semester(widget.xnm, widget.xqm);

  /// 手动课程 + 教务课程（与课表页同一套）。
  List<TtCourse> get _courses => [...TimetableStore.deriveImported(tt), ...tt.courses];

  IcsScope _scope = IcsScope.week;
  final Set<String> _offCourses = {}; // 取消勾选的课程 id
  final Set<String> _offEvents = {};
  bool _busy = false;

  bool get _hasStart => DateTime.tryParse(tt.startDate)?.year != null &&
      DateTime.tryParse(tt.startDate)!.year > 1970;

  List<TtCourse> get _pickedCourses =>
      [for (final c in _courses) if (!_offCourses.contains(c.id)) c];
  List<TtEvent> get _pickedEvents =>
      [for (final e in tt.events) if (!_offEvents.contains(e.id)) e];

  List<TtOccurrence> get _preview => _hasStart
      ? TimetableIcs.occurrences(
          tt: tt,
          courses: _pickedCourses,
          events: _pickedEvents,
          scope: _scope,
          slotStarts: TimetableStore.slotStarts,
          slotEnds: TimetableStore.slotEnds,
        )
      : const [];

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating));
  }

  // ==================== 导出 ====================

  String _buildIcs() => TimetableIcs.build(
        tt: tt,
        courses: _pickedCourses,
        events: _pickedEvents,
        scope: _scope,
        slotStarts: TimetableStore.slotStarts,
        slotEnds: TimetableStore.slotEnds,
        calendarName: [
          'AntiSIT 课表',
          if (tt.name.isNotEmpty) tt.name,
          _scope.label,
        ].join(' · '),
      );

  String get _fileName =>
      'antisit-timetable-${TimetableStore.iso(DateTime.now())}-${_scope.name}.ics';

  Future<void> _export() async {
    final items = _preview;
    if (items.isEmpty) {
      _toast('这个范围里没有可导出的内容，换一个范围或勾上课程 / 日程');
      return;
    }
    setState(() => _busy = true);
    final text = _buildIcs();
    try {
      final share = TimetableIcsPage.shareOverride ?? _shareFile;
      await share(text, _fileName);
      _toast('已生成 ${items.length} 条日程（$_fileName）');
    } catch (e) {
      // 分享面板不可用（桌面端 / 缺应用）：退回复制全文，别让用户白点一下
      if (await _copyToClipboard(text)) {
        _toast('分享不可用（$e）：日历内容已复制，粘进文本编辑器另存为 .ics 即可');
      } else {
        _toast('导出失败：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 写临时文件再交给系统分享：Android / iOS 上是「存到文件 / 发给别人 / 导入日历」。
  static Future<void> _shareFile(String text, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(utf8.encode(text)); // .ics 用 UTF-8
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/calendar')],
      subject: 'AntiSIT 课表',
    ));
  }

  Future<bool> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _copy(String text) async {
    if (await _copyToClipboard(text)) {
      _toast('已复制日历内容（${text.split('\n').length} 行），可粘进文本编辑器另存为 .ics');
    } else {
      _toast('复制失败，试试「导出并分享」');
    }
  }

  // ==================== 导入 ====================

  Future<void> _import() async {
    if (!_hasStart) {
      _toast('请先在「课程表设置 → 学期设置」里填学期起点，导入才知道该收哪段时间');
      return;
    }
    XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: '日历文件', extensions: ['ics', 'ical']),
      ]);
    } catch (e) {
      _toast('打开文件选择器失败：$e');
      return;
    }
    if (picked == null) return;

    List<IcsEvent> parsed;
    try {
      parsed = TimetableIcs.parse(utf8.decode(await picked.readAsBytes(), allowMalformed: true));
    } catch (e) {
      _toast('这个文件读不出来：$e');
      return;
    }
    if (!mounted) return;
    if (parsed.isEmpty) {
      _toast('这个文件里没有可导入的事件（只认 VEVENT）');
      return;
    }

    final plan = TimetableIcsPage.planImport(parsed, tt);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入日历'),
        content: Text(plan.summary, style: const TextStyle(fontSize: 13, height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: plan.items.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    tt.events.addAll(plan.items);
    await TimetableStore.instance.save();
    if (!mounted) return;
    setState(() {});
    _toast('已导入 ${plan.items.length} 条日程');
  }

  // ==================== 界面 ====================

  @override
  Widget build(BuildContext context) {
    final items = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('导出 / 导入日历')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导出为日历文件（.ics）',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Text(
                  'iCalendar（RFC 5545）是系统日历与各课表 App 通用的格式，导出的文件'
                  '可以直接导入手机日历。单双周、周次、调休会展开成一次次具体的课，'
                  '到哪个客户端都一样；一周里同一门课的每次课是一条独立日程。',
                  style: TextStyle(fontSize: 12, height: 1.7, color: SemColors.textSecondary),
                ),
                if (!_hasStart) ...[
                  const SizedBox(height: 8),
                  Text('尚未设置学期起点：到「课程表设置 → 学期设置」填好第 1 周周一再来。',
                      style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.6)),
                ],
                const SizedBox(height: 12),
                SegmentedButton<IcsScope>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    for (final s in IcsScope.values)
                      ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (v) => setState(() => _scope = v.first),
                ),
                const SizedBox(height: 10),
                Text(
                  '范围：${_scope.label} · 将导出 ${items.length} 条（'
                  '${items.where((i) => !i.isEvent).length} 节课 / '
                  '${items.where((i) => i.isEvent).length} 条日程）',
                  style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy || items.isEmpty ? null : _export,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('导出并分享'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: items.isEmpty ? null : () => _copy(_buildIcs()),
                      child: const Text('复制内容'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _pickCard(
            title: '课程（${_pickedCourses.length}/${_courses.length}）',
            empty: '这个学期还没有课程',
            entries: [
              for (final c in _courses)
                (
                  id: c.id,
                  title: c.name,
                  subtitle: _courseSubtitle(c),
                  checked: !_offCourses.contains(c.id),
                ),
            ],
            off: _offCourses,
          ),
          const SizedBox(height: 10),
          _pickCard(
            title: '日程（${_pickedEvents.length}/${tt.events.length}）',
            empty: '还没有日程（考试、临时事项）。不要日程就把上面全取消勾选。',
            entries: [
              for (final e in tt.events)
                (
                  id: e.id,
                  title: e.name,
                  subtitle: _eventSubtitle(e),
                  checked: !_offEvents.contains(e.id),
                ),
            ],
            off: _offEvents,
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('从日历文件导入',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Text(
                  '选一个 .ics（iCalendar）文件，把里面的日程导进课表：只收本学期范围内的'
                  '事件，与已有日程重复的会自动跳过；导入的是日程（考试 / 临时事项），'
                  '不会改动课程。按月的重复规则只取首次发生。',
                  style: TextStyle(fontSize: 12, height: 1.7, color: SemColors.textSecondary),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('选择 .ics 文件'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一组可勾选条目（课程 / 日程），标题行带全选 / 全不选。
  Widget _pickCard({
    required String title,
    required String empty,
    required List<({String id, String title, String subtitle, bool checked})> entries,
    required Set<String> off,
  }) {
    final allOn = entries.isEmpty || entries.every((e) => e.checked);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              if (entries.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() {
                    off.clear();
                    if (allOn) off.addAll(entries.map((e) => e.id));
                  }),
                  child: Text(allOn ? '全不选' : '全选',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(empty,
                  style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.6)),
            )
          else
            for (final e in entries)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: e.checked,
                title: Text(e.title, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(e.subtitle, style: const TextStyle(fontSize: 11.5)),
                onChanged: (v) => setState(() => v == true ? off.remove(e.id) : off.add(e.id)),
              ),
        ],
      ),
    );
  }

  String _courseSubtitle(TtCourse c) {
    final type = switch (c.weekType) {
      'odd' => '单周',
      'even' => '双周',
      _ => '每周',
    };
    return [
      '周${'一二三四五六日'[c.day.clamp(0, 6)]} '
          '第 ${c.slotStart + 1}-${c.slotEnd + 1} 节 '
          '$type 第 ${c.weekStart}-${c.weekEnd} 周',
      if (c.place.isNotEmpty) c.place,
      if (c.teachers.isNotEmpty) c.teachers,
    ].join(' · ');
  }

  String _eventSubtitle(TtEvent e) {
    final when = e.date.isEmpty
        ? '每周周${'一二三四五六日'[e.day.clamp(0, 6)]}'
        : '${e.date} 周${'一二三四五六日'[e.day.clamp(0, 6)]}';
    return [
      when,
      if (e.start.isNotEmpty) '${e.start}-${e.end}',
      if (e.place.isNotEmpty) e.place,
      if (e.kind == 'exam') '考试',
    ].join(' · ');
  }
}
