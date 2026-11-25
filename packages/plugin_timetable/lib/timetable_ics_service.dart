import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:campus_core/campus_core.dart';

/// 一天中的分钟 → 'HH:mm'。
String icsHhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// 解析结果 → 可导入的日程：学期范围外丢掉，与已有日程重复的丢掉，并给出跳过原因。
({List<TtEvent> items, String summary}) planIcsImport(
  List<IcsEvent> parsed,
  SemesterTt tt,
) {
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
    if (d != null &&
        start != null &&
        end != null &&
        (d.isBefore(start) || !d.isBefore(end))) {
      outside++;
      continue;
    }
    final date = d == null ? '' : TimetableStore.iso(d);
    final start2 = icsHhmm(e.startMin);
    final end2 = icsHhmm(e.endMin);
    final name = e.summary.trim().isEmpty ? '（未命名日程）' : e.summary.trim();
    final key = '$date|$name|$start2|$end2';
    if (keys.contains(key)) {
      dup++;
      continue;
    }
    keys.add(key);
    items.add(
      TtEvent(
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
      ),
    );
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
      if (items.isNotEmpty)
        '将导入 ${items.length} 条到「日程」（不导入课程）。'
      else
        '没有可导入的日程。',
      if (extras.isNotEmpty) '跳过：${extras.join('；')}。',
      '导入的日程按每周重复或具体日期显示在课表上，可在课表里再编辑 / 删除。',
    ].join('\n'),
  );
}

/// 写临时文件再交给系统分享（Android / iOS 上是存文件 / 发给别人 / 导入日历）。
Future<void> shareIcsFile(String text, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(utf8.encode(text)); // .ics 用 UTF-8
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/calendar')],
      subject: 'AntiSIT 课表',
    ),
  );
}

/// 复制文本到剪贴板；失败返回 false。
Future<bool> copyTextToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
