import 'package:campus_core/campus_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 待评的一条：一位教师 × 一个教学班。
class EvalTarget {
  const EvalTarget({
    required this.jxbId,
    required this.kchId,
    required this.jghId,
    required this.sfcjlrjs,
    required this.tjzt,
    required this.course,
    required this.teacher,
    required this.className,
    this.college = '',
    this.title = '',
    this.time = '',
    this.place = '',
    this.xsdm = '01',
    this.xnm = '',
    this.xqm = '',
  });

  /// 教学班 ID（提交与取表单都要）。
  final String jxbId;

  /// 课程号 ID。
  final String kchId;

  /// 教师 ID：**必须用当次列表返回的这个**（每次查询都变）。
  final String jghId;

  /// 「是否参加录入教师评分」：原样回传。
  final String sfcjlrjs;

  /// -1 未评 / 0 已保存 / 1 已提交。
  final String tjzt;

  final String course;
  final String teacher;
  final String className;
  final String college;
  final String title;
  final String time;
  final String place;

  /// 学时类型：01 理论 / 02 实验 / 04 设计（决定用哪套指标模板）。
  final String xsdm;
  final String xnm;
  final String xqm;

  bool get submitted => tjzt == '1';
  bool get saved => tjzt == '0';
  bool get pending => tjzt == '-1';

  /// 状态胶囊：未评 / 已保存 / 已提交。
  String get statusLabel => submitted ? '已提交' : (saved ? '已保存' : '未评');

  /// 同一教学班可能有多位老师：用教学班 + 教师 ID 做稳定键。
  String get id => jxbId + '|' + jghId;

  String get subtitle => [
        if (className.trim().isNotEmpty) className,
        if (college.trim().isNotEmpty) college,
        if (title.trim().isNotEmpty) title,
      ].join(' · ');

  static EvalTarget? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => (raw[k] ?? '').toString().trim();
    final jxbId = s('jxb_id');
    final kchId = s('kch_id');
    final jghId = s('jgh_id');
    if (jxbId.isEmpty || kchId.isEmpty || jghId.isEmpty) return null;
    final course = s('kcmc');
    final teacher = s('jzgmc');
    if (course.isEmpty && teacher.isEmpty) return null;
    return EvalTarget(
      jxbId: jxbId,
      kchId: kchId,
      jghId: jghId,
      sfcjlrjs: s('sfcjlrjs'),
      tjzt: s('tjzt').isEmpty ? '-1' : s('tjzt'),
      course: course,
      teacher: teacher,
      className: s('jxbmc'),
      college: s('jgmc'),
      title: s('zcmc'),
      time: s('sksj'),
      place: s('jxdd'),
      xsdm: s('xsdm').isEmpty ? '01' : s('xsdm'),
      xnm: s('xnm'),
      xqm: s('xqm'),
    );
  }
}

/// 评价情况汇总。
class EvalSummary {
  const EvalSummary({this.pending = 0, this.saved = 0, this.submitted = 0});

  final int pending;
  final int saved;
  final int submitted;

  int get total => pending + saved + submitted;
  bool get allDone => pending == 0 && total > 0;
}

/// 一条二级指标（一道题）。
class EvalItem {
  const EvalItem({
    required this.id,
    required this.text,
    required this.required,
    required this.min,
    required this.max,
    required this.gradeCodeId,
    required this.templateCodeId,
    this.weight = 1,
    this.savedValue,
  });

  /// 指标 ID（`data-pjzbxm_id`）。
  final String id;

  /// 题干。
  final String text;
  final bool required;

  /// 分值范围（本项目实测都是 0–100）。
  final double min;
  final double max;

  /// 评分等级代码 ID（原样回传）。
  final String gradeCodeId;

  /// 真实模板名称表 ID（原样回传）。
  final String templateCodeId;

  /// 二级权重（用于算总分预览）。
  final double weight;

  /// 页面回填的已保存分数（没保存过就是 null）：
  /// 打开一条「已保存」的评教时界面先显示上次打的分，而不是重新从满分开始。
  final double? savedValue;

  /// 界面上显示的序号由列表位置决定，这里只给题干。
  String get title => text.trim().isEmpty ? '未命名指标' : text.trim();

  /// 把任意分数吸附进合法范围（整数步长）。
  double snap(double raw) {
    if (!raw.isFinite) return min;
    var v = raw.clamp(min, max);
    if ((max - min) >= 1) v = v.roundToDouble();
    return v.clamp(min, max);
  }
}

/// 一个一级指标（分组）。
class EvalGroup {
  const EvalGroup({
    required this.id,
    required this.title,
    required this.weight,
    required this.items,
  });

  final String id;
  final String title;
  final double weight;
  final List<EvalItem> items;
}

/// 一套评价模板（理论类 / 实践类）。
class EvalModel {
  const EvalModel({
    required this.id,
    required this.name,
    required this.pjdxdm,
    required this.fxzgf,
    required this.savedId,
    required this.groups,
  });

  final String id;
  final String name;
  final String pjdxdm;
  final String fxzgf;

  /// 已保存过的那次评价批次 ID；首次为空串。
  final String savedId;

  final List<EvalGroup> groups;

  Iterable<EvalItem> get items => groups.expand((g) => g.items);
}

/// 一节课的评教表单。
class EvalForm {
  const EvalForm({
    required this.jxbId,
    required this.kchId,
    required this.jghId,
    required this.xsdm,
    required this.ztpjbl,
    required this.jszdpjbl,
    required this.xykzpjbl,
    required this.models,
    this.commentMax = 500,
  });

  final String jxbId;
  final String kchId;

  /// **表单里的** jgh_id（与列表里那个 256 位串不同，提交要用这个）。
  final String jghId;

  final String xsdm;
  final String ztpjbl;
  final String jszdpjbl;
  final String xykzpjbl;
  final List<EvalModel> models;
  final int commentMax;

  Iterable<EvalItem> get items => models.expand((m) => m.items);
  int get count => items.length;
  int get requiredCount => items.where((i) => i.required).length;

  /// 页面回填的已保存分数（没保存过的题不在里面）。
  Map<String, double> get savedScores => {
        for (final item in items)
          if (item.savedValue != null) item.id: item.snap(item.savedValue!),
      };

  /// 打开表单时的初始分数：**逐题**优先用已保存分，没有的题给兜底分（默认满分档）。
  Map<String, double> initialScores({double fallback = 95}) {
    final saved = savedScores;
    final base = presetScores(this, fallback);
    for (final e in saved.entries) {
      base[e.key] = e.value;
    }
    return base;
  }

  /// 加权总分（复算学校前端 calculatePmbPjzf 的公式）。
  double total(Map<String, double> scores) {
    var sum = 0.0;
    for (final m in models) {
      for (final g in m.groups) {
        for (final item in g.items) {
          final v = scores[item.id];
          if (v == null) continue;
          sum += g.weight * item.weight * v;
        }
      }
    }
    return sum;
  }

  /// 解析 [xspj_cxXspjDisplay.html] 的页面结构。
  static EvalForm? tryParse(String html) {
    final doc = html_parser.parse(html);
    final body = doc.querySelector('div.xspj-body');
    if (body == null) return null;
    String attr(dom.Element e, String name) => (e.attributes[name] ?? '').trim();

    final panels = doc.querySelectorAll('div.panel-pjdx');
    final models = <EvalModel>[];
    for (final panel in panels) {
      final modelId = attr(panel, 'data-pjmbmcb_id');
      if (modelId.isEmpty) continue;
      final groups = <EvalGroup>[];
      for (final table in panel.querySelectorAll('table.table-xspj')) {
        final groupId = attr(table, 'data-pjzbxm_id');
        final weight = _num(attr(table, 'data-qzz')) ?? 1;
        final items = <EvalItem>[];
        for (final tr in table.querySelectorAll('tr.tr-xspj')) {
          final input = tr.querySelector('input.input-pjf');
          final id = attr(tr, 'data-pjzbxm_id');
          if (id.isEmpty) continue;
          items.add(EvalItem(
            id: id,
            text: _questionText(tr),
            required: attr(tr, 'data-sfbt') == '1',
            min: _num(input == null ? null : attr(input, 'data-zxfz')) ?? 0,
            max: _num(input == null ? null : attr(input, 'data-zdfz')) ?? 100,
            gradeCodeId: attr(tr, 'data-pfdjdmb_id'),
            templateCodeId: attr(tr, 'data-zsmbmcb_id'),
            weight: _num(input == null ? null : attr(input, 'data-ejqz')) ??
                _num(attr(tr, 'data-qzz')) ??
                1,
            savedValue: _num(input == null ? null : attr(input, 'value')),
          ));
        }
        if (items.isEmpty) continue;
        groups.add(EvalGroup(
          id: groupId,
          title: _groupTitle(table),
          weight: weight,
          items: items,
        ));
      }
      if (groups.isEmpty) continue;
      models.add(EvalModel(
        id: modelId,
        name: attr(panel, 'data-pjmbmc'),
        pjdxdm: attr(panel, 'data-pjdxdm'),
        fxzgf: attr(panel, 'data-fxzgf'),
        savedId: attr(panel, 'data-xspfb_id'),
        groups: groups,
      ));
    }
    if (models.isEmpty) return null;

    final commentEl = doc.querySelector('#xspjpyzskz');
    final rawMax = commentEl == null ? null : commentEl.attributes['value'];
    final commentMax = (_num(rawMax) ?? 500).toInt();
    return EvalForm(
      jxbId: attr(body, 'data-jxb_id'),
      kchId: attr(body, 'data-kch_id'),
      jghId: attr(body, 'data-jgh_id'),
      xsdm: attr(body, 'data-xsdm'),
      ztpjbl: attr(body, 'data-ztpjbl'),
      jszdpjbl: attr(body, 'data-jszdpjbl'),
      xykzpjbl: attr(body, 'data-xykzpjbl'),
      models: models,
      commentMax: commentMax <= 0 ? 500 : commentMax,
    );
  }

  /// 题干：`tr` 里第一个 `td` 的文本，去掉必填星号与「（100分）」尾巴。
  static String _questionText(dom.Element tr) {
    final td = tr.querySelector('td');
    var t = (td == null ? '' : td.text).replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceFirst(RegExp(r'^\*\s*'), '');
    // 页面把题号写在题干里（「1、「1.」「(1)」），界面上另有编号，去掉免得出现「1. 1、…」
    t = t.replaceFirst(RegExp(r'^\d+\s*[、.．)）]\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*[（(]\s*\d+\s*分\s*[）)]\s*$'), '');
    return t;
  }

  /// 一级指标名：表格前面那个 `blockquote p`。
  static String _groupTitle(dom.Element table) {
    var node = table.previousElementSibling;
    var guard = 0;
    while (node != null && guard++ < 4) {
      final p = node.querySelector('p');
      if (p != null) {
        final t = p.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isNotEmpty) return t;
      }
      final own = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (own.isNotEmpty) return own;
      node = node.previousElementSibling;
    }
    return '';
  }

  static double? _num(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.trim());
  }
}

/// 把统一分数摊到所有指标上（按各自范围吸附）。
Map<String, double> presetScores(EvalForm form, double score) => {
      for (final item in form.items) item.id: item.snap(score),
    };

/// 学号打码（与服务器模式 status 的口径一致），设置页展示用。
String maskEvalStudentId(String sid) => maskStudentId(sid);