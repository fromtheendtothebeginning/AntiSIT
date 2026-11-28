import 'package:flutter/material.dart';

import 'glass_tabs.dart';
import 'theme_palette.dart';

/// 玻璃风格的选择器：日期与时间。
///
/// 为什么不用 `showDatePicker` / `showTimePicker`：那两个是 Material 原生弹层，
/// 白底直角、蓝色强调，和 App 里的玻璃卡片完全是两套观感；也不能按 App 的
/// 「不做实时模糊」约束改。这里用底部玻璃卡片 + 自绘网格 / 滚轮，配色全跟主题。

const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 底部玻璃卡片外壳（两个选择器共用）。
Widget _sheetShell({
  required BuildContext context,
  required String title,
  required Widget body,
  required VoidCallback onCancel,
  required VoidCallback onConfirm,
  String confirmText = '确定',
}) {
  return SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        color: SemColors.menuBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: SemColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 4),
              FilledButton(onPressed: onConfirm, child: Text(confirmText)),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.62,
            ),
            child: SingleChildScrollView(child: body),
          ),
        ],
      ),
    ),
  );
}

/// 玻璃日期选择器：年月切换 + 当月日历格；超出范围的日期置灰不可点。
Future<DateTime?> showGlassDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String? title,
}) async {
  final today = DateUtils.dateOnly(DateTime.now());
  final lo = firstDate == null ? null : DateUtils.dateOnly(firstDate);
  final hi = lastDate == null ? null : DateUtils.dateOnly(lastDate);
  var selected = DateUtils.dateOnly(initialDate ?? today);
  var month = DateTime(selected.year, selected.month);
  var result = selected;

  bool allowed(DateTime d) {
    if (lo != null && d.isBefore(lo)) return false;
    if (hi != null && d.isAfter(hi)) return false;
    return true;
  }

  bool monthFullyDisabled(DateTime m) {
    final days = DateUtils.getDaysInMonth(m.year, m.month);
    final first = DateTime(m.year, m.month, 1);
    final last = DateTime(m.year, m.month, days);
    if (lo != null && last.isBefore(lo)) return true;
    if (hi != null && first.isAfter(hi)) return true;
    return false;
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final days = DateUtils.getDaysInMonth(month.year, month.month);
        final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
        final prevOk = !monthFullyDisabled(
          DateTime(month.year, month.month - 1),
        );
        final nextOk = !monthFullyDisabled(
          DateTime(month.year, month.month + 1),
        );
        return _sheetShell(
          context: ctx,
          title: title ?? '选择日期',
          onCancel: () => Navigator.pop(ctx, false),
          onConfirm: () => Navigator.pop(ctx, true),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: prevOk
                        ? () => setS(() {
                            month = DateTime(month.year, month.month - 1);
                          })
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${month.year} 年 ${month.month} 月',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: nextOk
                        ? () => setS(() {
                            month = DateTime(month.year, month.month + 1);
                          })
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final w in _weekLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: TextStyle(
                            fontSize: 12,
                            color: SemColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.15,
                ),
                itemCount: firstWeekday + days,
                itemBuilder: (_, i) {
                  if (i < firstWeekday) return const SizedBox.shrink();
                  final day = i - firstWeekday + 1;
                  final date = DateTime(month.year, month.month, day);
                  final picked = DateUtils.isSameDay(date, selected);
                  final isToday = DateUtils.isSameDay(date, today);
                  final enabled = allowed(date);
                  return Padding(
                    padding: const EdgeInsets.all(2),
                    child: Material(
                      color: picked
                          ? SemColors.accent
                          : (isToday
                                ? SemColors.accentSoft
                                : Colors.transparent),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: enabled
                            ? () => setS(() {
                                selected = date;
                                result = date;
                              })
                            : null,
                        child: Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: picked
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: !enabled
                                  ? SemColors.textMuted
                                  : (picked
                                        ? Colors.white
                                        : SemColors.textPrimary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok == true ? result : null;
}

/// 玻璃时间选择器：小时 / 分钟两列滚轮，中间一条选中带。
Future<TimeOfDay?> showGlassTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
  String? title,
}) async {
  final start = initialTime ?? const TimeOfDay(hour: 8, minute: 0);
  var hour = start.hour.clamp(0, 23);
  var minute = start.minute.clamp(0, 59);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => _sheetShell(
        context: ctx,
        title: title ?? '选择时间',
        onCancel: () => Navigator.pop(ctx, false),
        onConfirm: () => Navigator.pop(ctx, true),
        body: SizedBox(
          height: 190,
          child: Row(
            children: [
              Expanded(
                child: _Wheel(
                  count: 24,
                  selected: hour,
                  label: (i) => i.toString().padLeft(2, '0'),
                  onChanged: (v) => setS(() => hour = v),
                ),
              ),
              const Text(':', style: TextStyle(fontSize: 20)),
              Expanded(
                child: _Wheel(
                  count: 60,
                  selected: minute,
                  label: (i) => i.toString().padLeft(2, '0'),
                  onChanged: (v) => setS(() => minute = v),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true ? TimeOfDay(hour: hour, minute: minute) : null;
}

/// 一列数字滚轮：固定项高，选中项高亮。
class _Wheel extends StatefulWidget {
  const _Wheel({
    required this.count,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final int count;
  final int selected;
  final String Function(int) label;
  final ValueChanged<int> onChanged;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  static const _itemExtent = 40.0;
  late final FixedExtentScrollController _ctrl = FixedExtentScrollController(
    initialItem: widget.selected,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: _ctrl,
      itemExtent: _itemExtent,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: widget.onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.count,
        builder: (context, i) {
          final on = i == widget.selected;
          return Center(
            child: Text(
              widget.label(i),
              style: TextStyle(
                fontSize: on ? 20 : 15,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                color: on ? SemColors.accent : SemColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 与 [GlassTabs] 同宽的分段选择：给「重复类型」这类少量选项用。
Widget glassSegmented(
  List<String> labels, {
  required int index,
  required ValueChanged<int> onChanged,
  double height = 30,
  double fontSize = 12,
}) => GlassTabs(
  labels: labels,
  index: index,
  onChanged: onChanged,
  height: height,
  fontSize: fontSize,
);

/// 玻璃风格的小选项面板：给「星期」「第几号」这类少量固定选项用。
/// 返回选中的下标；取消返回 null。
Future<int?> showGlassChoiceSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  int? selected,
}) async {
  final ok = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: SemColors.menuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: SemColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: i == selected
                              ? SemColors.accentSoft
                              : SemColors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(ctx, i),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      options[i],
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: i == selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: i == selected
                                            ? SemColors.accent
                                            : SemColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (i == selected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: SemColors.accent,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return ok;
}

/// 玻璃风格的主按钮（保存 / 应用这类一次性的确认动作）。
Widget glassPrimaryButton({
  required String label,
  required VoidCallback onPressed,
  IconData? icon,
}) {
  // 用普通 FilledButton（不是 FilledButton.icon）：后者返回的是内部子类，
  // 测试里的 find.byType(FilledButton) 按精确类型匹配会找不到它。
  return SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: SemColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Text(label),
        ],
      ),
    ),
  );
}
