part of 'academic_page.dart';

/// 顶部：平均学分绩点大数字 + 学号 / 计划课程数。
Widget _gpaCard(num? gpa, String sid, Map<String, dynamic>? planed) {
  final total = asInt(planed?['total']);
  return AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BigStat(
          label: '平均学分绩点',
          value: gpa == null ? '—' : gpa.toStringAsFixed(2),
          color: SemColors.accent,
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (sid.isNotEmpty)
              Text(
                '学号 $sid',
                style: TextStyle(
                  fontSize: 12,
                  color: SemColors.textSecondary,
                ),
              ),
            if (total != null) ...[
              const SizedBox(height: 4),
              Text(
                '计划总课程 $total 门',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

/// 整体统计：计划内（总/通过/未通过/未修/在读）+ 计划外（通过/未通过）。
Widget _statsCard(
  Map<String, dynamic>? planed,
  Map<String, dynamic>? unplaned,
) {
  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (planed != null) ...[
          _sectionLine('计划内课程'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _stat('总课程', planed['total']),
              _stat('通过', planed['passed'], color: SemColors.success),
              _stat('未通过', planed['failed'], color: SemColors.danger),
              _stat('未修', planed['missed']),
              _stat('在读', planed['in']),
            ],
          ),
        ],
        if (planed != null && unplaned != null) const SizedBox(height: 16),
        if (unplaned != null) ...[
          _sectionLine('计划外课程'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _stat('通过', unplaned['passed'], color: SemColors.success),
              _stat('未通过', unplaned['failed'], color: SemColors.danger),
            ],
          ),
        ],
      ],
    ),
  );
}

/// 统计小格：值缺失时显示占位符而不是编造 0。
Widget _stat(String label, Object? value, {Color? color}) {
  final n = asInt(value);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
      const SizedBox(height: 2),
      Text(
        n == null ? '—' : '$n',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: n == null
              ? SemColors.textMuted
              : (color ?? SemColors.textPrimary),
        ),
      ),
    ],
  );
}

Widget _sectionLine(String text) => Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: SemColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: SemColors.textPrimary,
          ),
        ),
      ],
    );

/// 分区标题：根节点（主修 / 其他课程…）+ 学分要求 + 该分区的叶子类别数。
Widget _sectionHeader(Map<String, dynamic> root, int leafCount) {
  final name = _strOf(root['name']);
  final required = asNum(root['required']);
  final earned = asNum(root['earned']);
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: SemColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name.isEmpty ? '未命名' : name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: SemColors.textPrimary,
            ),
          ),
        ),
        if (required != null) _chip('要求 ${_fmtNum(required)}'),
        if (earned != null) ...[
          const SizedBox(width: 6),
          _chip('已得 ${_fmtNum(earned)}'),
        ],
        const SizedBox(width: 8),
        Text(
          '$leafCount 类',
          style: TextStyle(fontSize: 11, color: SemColors.textMuted),
        ),
      ],
    ),
  );
}

/// 叶子类别卡片：面包屑说明归属，展开是该类别的课程（每门课全宽独立卡片）。
Widget _leafCategoryCard(
  BuildContext context,
  Map<String, dynamic> cat,
  List<String> crumbs,
) {
  final name = _strOf(cat['name']);
  final required = asNum(cat['required']);
  final earned = asNum(cat['earned']);
  final courses = _listOf(cat['courses']);
  final coursesError = _strOf(cat['coursesError']);
  // 学分合并成「已获/要求」标签，缺一侧时只显示有的那侧。
  final creditLabel = (earned != null && required != null)
      ? '${_fmtNum(earned)}/${_fmtNum(required)}'
      : (earned != null
          ? '已获 ${_fmtNum(earned)}'
          : (required != null ? '要求 ${_fmtNum(required)}' : null));
  // 总课程数放标题行右侧；明细拉取失败时数量未知，不显示。
  final countLabel = coursesError.isEmpty ? '${courses.length} 门' : '';
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: SemColors.stripe,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: SemColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: SemColors.textMuted,
      collapsedIconColor: SemColors.textMuted,
      title: Row(
        children: [
          Expanded(
            child: Text(
              name.isEmpty ? '未命名类别' : name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SemColors.textPrimary,
              ),
            ),
          ),
          if (countLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                countLabel,
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (crumbs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  crumbs.join(' › '),
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                ),
              ),
            if (creditLabel != null) _chip(creditLabel),
          ],
        ),
      ),
      children: [
        if (coursesError.isNotEmpty)
          _hintRow('课程明细加载失败（$coursesError）')
        else if (courses.isEmpty)
          _hintRow('暂无课程明细')
        else
          for (final course in courses) _courseCard(context, course),
      ],
    ),
  );
}

/// 单门课程 = 独立卡片（全宽，不随层级缩进）。
Widget _courseCard(BuildContext context, Map<String, dynamic> c) {
  final name = _strOf(c['name']);
  final code = _strOf(c['code']);
  final credit = asNum(c['credit']);
  final scoreText = _strOf(c['score']);
  final scoreNum = asNum(c['score']);
  final point = asNum(c['point']);
  final nature = _strOf(c['nature']);
  final term = _strOf(c['term']);
  final statusText = _strOf(c['statusText']);
  // 标签配色：必修紫、选修淡蓝、未修红、在修黄、已修绿、建议学期橙；课程号与未识别值中性灰。
  final tagWidgets = <Widget>[
    if (nature.isNotEmpty) _tagOrChip(context, nature, _natureColor(nature)),
    if (term.isNotEmpty) _tagOrChip(context, term, Colors.orange),
    if (statusText.isNotEmpty)
      _tagOrChip(context, statusText, _statusColor(statusText)),
  ];
  final meta = [
    if (credit != null) '学分 ${_fmtNum(credit)}',
    if (point != null) '绩点 ${_fmtNum(point)}',
  ].join(' · ');
  // 成绩能解析成数字时按及格线着色；「优秀 / 合格」这类文本保持中性色。
  final scoreColor = scoreNum == null
      ? SemColors.textPrimary
      : (scoreNum < 60 ? SemColors.danger : SemColors.success);
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: SemColors.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: SemColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? '未命名课程' : name,
                style: TextStyle(fontSize: 13, color: SemColors.textPrimary),
              ),
              if (code.isNotEmpty || tagWidgets.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [if (code.isNotEmpty) _chip(code), ...tagWidgets],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              scoreText.isEmpty ? '—' : scoreText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scoreColor,
              ),
            ),
            if (meta.isNotEmpty)
              Text(
                meta,
                style: TextStyle(fontSize: 11, color: SemColors.textMuted),
              ),
          ],
        ),
      ],
    ),
  );
}

Widget _hintRow(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: SemColors.textMuted),
      ),
    );

/// 彩色标签：浅色底 + 同色系文字；深色主题下自动提亮文字，保证可读。
Widget _tagChip(BuildContext context, String text, MaterialColor color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final fg = dark ? color.shade200 : color.shade800;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: dark ? 0.22 : 0.14),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: dark ? 0.35 : 0.28)),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: fg)),
  );
}

/// 有配色就用彩色标签，未识别的取值保持中性灰。
Widget _tagOrChip(BuildContext context, String text, MaterialColor? color) =>
    color == null ? _chip(text) : _tagChip(context, text, color);

/// 课程性质：必修紫、选修淡蓝；其它性质（实践/限选…）保持中性。
MaterialColor? _natureColor(String nature) => switch (nature) {
      '必修' => Colors.purple,
      '选修' => Colors.lightBlue,
      _ => null,
    };

/// 修读状态：未修红、在修黄、已修绿；替代/认定等状态保持中性。
MaterialColor? _statusColor(String status) => switch (status) {
      '未修' => Colors.red,
      '在修' => Colors.amber,
      '已修' => Colors.green,
      _ => null,
    };

Widget _chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: SemColors.neutralSoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: SemColors.textMuted),
      ),
    );

/// 宽容取子对象：字段可能缺失 / 为 null / 不是 Map。
Map<String, dynamic>? _objOf(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

/// 宽容取对象列表：非 List 或元素不是 Map 时跳过，不让单个脏元素炸整页。
List<Map<String, dynamic>> _listOf(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];

String _strOf(Object? v) => '${v ?? ''}'.trim();

/// 学分数值：整数不带小数点（28.0 → 28），小数原样保留。
String _fmtNum(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();
