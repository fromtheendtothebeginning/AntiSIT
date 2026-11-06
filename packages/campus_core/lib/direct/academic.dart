/// 「学生学业情况查询」（正方教务，GNMKDM=N105515）页面解析。
///
/// 新版正方把这一页渲染成服务端 HTML：
///
/// - `input#xh_id`：学号；
/// - `div#alertBox`：整体统计，形如
///   「平均学分绩点：3.52 计划总课程 60 门 通过 52 门 未通过 3 门 未修 4 门
///     在读 1 门，计划外 通过 3 门 未通过 1 门」；
/// - 每个培养方案节点（主修 / 专业核心课 / 专业选修课 / 方向版块…）渲染一段标题 +
///   「要求学分：33.0 获得学分：28.0 未获得学分：5.0」+ 一个空的
///   `<span id='showKc<xfyqjd_id>'></span>` 占位；点开节点时前端再 POST
///   `xsxyqk_cxJxzxjhxfyqKcxx.html`（表单 `xfyqjd_id=<id>`）拉该节点课程 JSON 数组。
/// - `div.alert-danger`：学校侧业务错误（如未配置培养方案）。
///
/// 这里只做纯字符串解析，不碰网络与登录态（那是 [JwxtClient] 的事），便于单测。
/// 协议移植自开源实现 zfn_api（openschoolcn/zfn_api）的
/// `get_academia` / `get_academia_statistics` / `get_academia_type_statistics`，
/// 并放宽了对属性顺序、HTML 实体、字段缺失（`&nbsp;` 占位）的假设。
library;

import '../json_num.dart';

/// 学业情况首页（相对 `jwxtBase`，即 `…/jwglxt` 之后）。真实页面可能带 `echarts=1`，
/// 只影响前端图表。
const String academicIndexPath =
    '/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default';

/// 学业情况节点课程明细（同样相对 `jwxtBase`）：POST 表单 `xfyqjd_id`，返回 JSON 数组。
const String academicCoursesPath = '/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html?gnmkdm=N105515';

/// 解析学业情况首页 HTML。
///
/// 返回：
/// ```
/// {
///   'login': false,              // true = 被重定向到登录页（会话失效）
///   'error': '',                 // 非空 = 学校 alert-danger 原文
///   'sid': '25110001',
///   'statistics': {
///     'gpa': 3.52,               // num?（页面上取不到时 null）
///     'planed': {'total': 60, 'passed': 52, 'failed': 3, 'missed': 4, 'in': 1},
///     'unplaned': {'passed': 3, 'failed': 1},
///   },
///   'categories': [
///     {'name': '专业核心课', 'id': '9002',
///      'required': 33.0, 'earned': 28.0, 'missed': 5.0},   // 学分可能 null
///   ],
/// }
/// ```
///
/// 解析不出来时宁可返回空字段，也不抛异常：调用方据此给「页面可能改版」的诊断。
Map<String, dynamic> parseAcademicIndex(String html) {
  final result = <String, dynamic>{
    'login': false,
    'error': '',
    'sid': '',
    'params': <String, String>{},
    'statistics': <String, dynamic>{},
    'categories': <Map<String, dynamic>>[],
  };

  // 未登录时有的学校直接回登录页 HTML（h5「用户登录」/ 正方登录页），302 由
  // HttpSession 层判；这里兜住「200 + 登录页 HTML」这一种。
  if (_looksLikeLoginPage(html)) {
    result['login'] = true;
    return result;
  }

  result['sid'] = _parseStudentId(html);
  result['error'] = _parseAlertDanger(html);
  result['params'] = _parseFormParams(html);
  result['statistics'] = _parseStatistics(html);
  result['categories'] = _parseCategories(html);
  return result;
}

/// 解析某个培养方案节点的课程明细 JSON。
///
/// 正方返回的字段是大写缩写（KCH/KCMC/XF/XDZT/MAXCJ/JD/…），这里归一成
/// 与其它教务接口一致的短字段；[sid] 用来把「建议修读学年」换算成「大二上」这类
/// 人话标签（取学号前 2 位作入学年，与 zfn_api 的做法一致，留级/入伍会不准）。
List<Map<String, dynamic>> parseAcademicCourses(dynamic json, {String sid = ''}) {
  final items = _itemsOf(json);
  if (items.isEmpty) return const [];
  return [
    for (final raw in items)
      if (raw is Map) _courseOf(raw, sid),
  ];
}

Map<String, dynamic> _courseOf(Map raw, String sid) {
  String first(List<String> keys) {
    for (final k in keys) {
      final v = '${raw[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  final year = first(['JYXDXNM', 'jyxdxnm', 'JYXDXNMC', 'jyxdxnmc']);
  final termCode = first(['JYXDXQMC', 'jyxdxqmc']);
  final status = first(['XDZT', 'xdzt']);
  return {
    'name': first(['KCMC', 'kcmc']),
    'code': first(['KCH', 'kch']),
    'credit': first(['XF', 'xf']),
    'score': first(['MAXCJ', 'maxcj', 'CJ', 'cj']),
    'point': first(['JD', 'jd']),
    'status': status,
    'statusText': _statusText(status),
    'nature': first(['KCXZMC', 'kcxzmc']),
    'category': first(['KCLBMC', 'kclbmc']),
    'year': year,
    'termCode': termCode,
    'term': prescribeTerm(sid: sid, year: year, termCode: termCode),
  };
}

/// 修读状态码 → 人话（正方 N105515 页面 `getXdzt()` 的 i18n 映射）。
String _statusText(String code) => const {
      '1': '在修',
      '2': '未过',
      '3': '未修',
      '4': '已修',
      '21': '已修',
      '5': '校内被替代',
      '6': '校内课程替代',
      '7': '校内课程替代节点',
      '8': '校外课程替换/认定',
      '9': '学分认定',
      '10': '学业预警不审核',
    }[code] ??
    '';

/// 建议修读学期 → 「大二上」这类标签；算不出来返回空串（宁缺毋滥）。
String prescribeTerm({required String sid, required String year, required String termCode}) {
  if (sid.length < 2 || year.length < 4) return '';
  final enterYear = int.tryParse(sid.substring(0, 2));
  final planYear = int.tryParse(year.substring(year.length - 2));
  if (enterYear == null || planYear == null) return '';
  final diff = planYear - enterYear;
  if (diff < 0 || diff > 3) return '';
  final t = termCode.trim();
  final half = t.contains('一')
      ? '上'
      : t.contains('二')
          ? '下'
          : t == '1'
              ? '上'
              : t == '2'
                  ? '下'
                  : '';
  if (half.isEmpty) return '';
  return const ['大一', '大二', '大三', '大四'][diff] + half;
}

// ==================== 整体统计 ====================

/// `div#alertBox` 里的整体统计。学校排版差异大（空格、&nbsp;、标点），
/// 先压成「无空白无标点」文本再匹配；缺字段就留 null，不编造 0。
Map<String, dynamic> _parseStatistics(String html) {
  final box = _alertBox(html);
  final out = <String, dynamic>{'gpa': null, 'planed': null, 'unplaned': null};

  final source = box.isEmpty ? html : box;
  final text = _htmlToText(source);
  final flat = _squash(text);

  // GPA：优先「平均学分绩点」后的数字；其次 alertBox 里第一个小数；
  // 再次页面里 <font size="2px"> 的第 3 个数字（部分版本只在图上标注，zfn_api 同样取法）。
  final gpaRe = RegExp(r'平均学分绩点[^\d]{0,12}(\d+(?:\.\d+)?)');
  num? gpa = _numOf(gpaRe.firstMatch(flat)?.group(1));
  if (gpa == null && box.isNotEmpty) {
    gpa = _numOf(RegExp(r'(\d{1,2}\.\d{1,3})').firstMatch(flat)?.group(1));
  }
  if (gpa == null) {
    final fonts = RegExp(
      r'<font[^>]*size\s*=\s*["\x27]2px["\x27][^>]*>\s*([\d.]+)\s*</font>',
      caseSensitive: false,
    ).allMatches(html).map((m) => _numOf(m.group(1))).whereType<num>().toList();
    gpa = fonts.length >= 3 ? fonts[2] : (fonts.isEmpty ? null : fonts.first);
  }
  out['gpa'] = gpa;

  // 计划内：计划总课程（数）N 门 通过 N 门 [未通过 N 门] [未修（读）N 门] [在读/在修 N 门]
  final planed = RegExp(
    r'计划(?:总)?课程(?:数)?(\d+)门通过(\d+)门未通过(\d+)门未修(?:读)?(\d+)门在(?:读|修)(\d+)门',
  ).firstMatch(flat);
  if (planed != null) {
    out['planed'] = {
      'total': int.tryParse(planed.group(1) ?? ''),
      'passed': int.tryParse(planed.group(2) ?? ''),
      'failed': int.tryParse(planed.group(3) ?? ''),
      'missed': int.tryParse(planed.group(4) ?? ''),
      'in': int.tryParse(planed.group(5) ?? ''),
    };
  } else {
    final loose = RegExp(r'计划总课程数?(\d+)门').firstMatch(flat);
    final passed = RegExp(r'计划内?[^未]{0,8}通过(\d+)门').firstMatch(flat);
    final failed = RegExp(r'计划内?[^未]{0,8}未通过(\d+)门').firstMatch(flat);
    if (loose != null || passed != null) {
      out['planed'] = {
        'total': int.tryParse(loose?.group(1) ?? ''),
        'passed': int.tryParse(passed?.group(1) ?? ''),
        'failed': int.tryParse(failed?.group(1) ?? ''),
        'missed': null,
        'in': null,
      };
    }
  }

  // 计划外：计划外（课程）通过 N 门 [未通过 N 门]
  final unplaned = RegExp(r'计划外[^计]{0,8}?通过(\d+)门未通过(\d+)门').firstMatch(flat) ??
      RegExp(r'计划外[^计]{0,8}?通过(\d+)门').firstMatch(flat);
  if (unplaned != null) {
    out['unplaned'] = {
      'passed': int.tryParse(unplaned.group(1) ?? ''),
      'failed': unplaned.groupCount >= 2 ? int.tryParse(unplaned.group(2) ?? '') : null,
    };
  }
  return out;
}

/// `div#alertBox` 内部 HTML；取不到返回空串。
String _alertBox(String html) {
  final re = RegExp(
    r'<div[^>]*\bid\s*=\s*["\x27]alertBox["\x27][^>]*>([\s\S]*?)</div>',
    caseSensitive: false,
  );
  return re.firstMatch(html)?.group(1) ?? '';
}

/// 学号：`<input id="xh_id" value="..."/>`（属性顺序不固定）。
String _parseStudentId(String html) {
  final tag = RegExp(r'<input\b[^>]*\bid\s*=\s*["\x27]xh_id["\x27][^>]*>',
          caseSensitive: false)
      .firstMatch(html)
      ?.group(0);
  if (tag != null) {
    final v = RegExp(r'''\bvalue\s*=\s*["']([^"']*)["']''').firstMatch(tag)?.group(1);
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  final rev = RegExp(
    r'''<input\b[^>]*\bvalue\s*=\s*["']([^"']*)["'][^>]*\bid\s*=\s*["']xh_id["']''',
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
  return rev?.trim() ?? '';
}

/// `div.alert-danger` 的可见错误文案（学校业务错误），没有返回空串。
String _parseAlertDanger(String html) {
  final re = RegExp(
    r'<div[^>]*class\s*=\s*["\x27][^"\x27]*alert-danger[^"\x27]*["\x27][^>]*>([\s\S]*?)</div>',
    caseSensitive: false,
  );
  final m = re.firstMatch(html);
  if (m == null || m.group(1)!.trim().isEmpty) return '';
  return _htmlToText(m.group(1) ?? '');
}

/// 课程明细 POST 需要首页里的一批隐藏域（学号、成绩录入学年/学期、成绩控制开关…），
/// 少传会导致明细接口回空或报错——所以从首页 HTML 原样抄过来。
const List<String> _academicFormIds = [
  'xh_id',
  'cjlrxn',
  'cjlrxq',
  'bkcjlrxn',
  'bkcjlrxq',
  'xscjcxkz',
  'cjcxkzzt',
  'cjztkz',
  'cjzt',
];

Map<String, String> _parseFormParams(String html) {
  final out = <String, String>{};
  for (final id in _academicFormIds) {
    final v = _hiddenInputValue(html, id);
    if (v != null) out[id] = v;
  }
  return out;
}

/// 取 `<input ... id="x" value="y"/>` 的 value（属性顺序、单双引号都不敏感）。
String? _hiddenInputValue(String html, String id) {
  final tag = RegExp(
    '<input\\b[^>]*\\bid\\s*=\\s*["\']${RegExp.escape(id)}["\'][^>]*>',
    caseSensitive: false,
  ).firstMatch(html)?.group(0);
  if (tag != null) {
    final v = RegExp(r'''\bvalue\s*=\s*["']([^"']*)["']''').firstMatch(tag)?.group(1);
    if (v != null) return v;
  }
  final rev = RegExp(
    '<input\\b[^>]*\\bvalue\\s*=\\s*["\']([^"\']*)["\'][^>]*\\bid\\s*=\\s*["\']'
    '${RegExp.escape(id)}'
    '["\']',
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
  return rev;
}

// ==================== 培养方案节点 ====================

/// 从页面里抓「培养方案节点」。
///
/// 新版正方（SIT 这版）把节点树写在**前端 JS 模板字符串**里：每个节点是
/// `<p class='title1' id='p<ID>' yxxf='已修' yqzdxf='要求' sftg='0|1'>` 后面跟
/// 一个 JS 字符串 `"类别名&nbsp;"`，中文标签（要求学分等）只在 `/* 注释 */` 里，
/// 真正渲染靠 i18n。所以先按这种「属性方言」解析；老版/其它学校直接渲染 HTML 的
/// 页面再走下面「按 showKc 占位切段」的静态方言。
List<Map<String, dynamic>> _parseCategories(String html) {
  final templateNodes = _parseTemplateNodes(html);
  if (templateNodes.isNotEmpty) return templateNodes;
  return _parseStaticCategories(html);
}

/// SIT/新版正方：从 JS 模板里解析节点（含父子层级）。
/// 属性 [yxxf]=已获学分、[yqzdxf]=要求总学分、[sftg]=是否达标；
/// 父节点 id 在同段模板的 `fxfyqjd_id='...'` 上（根节点为空）。
List<Map<String, dynamic>> _parseTemplateNodes(String html) {
  final re = RegExp(
    r"""<p\s+class=['"]title1['"][^>]*?\bid=['"]p([0-9A-Za-z]{4,40})['"][^>]*?\byxxf=['"]([^'"]*)['"][^>]*?\byqzdxf=['"]([^'"]*)['"][^>]*?\bsftg=['"]([^'"]*)['"][^>]*>\s*"?\s*\+\s*"([^"]*?)&nbsp;""",
    dotAll: true,
  );
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final m in re.allMatches(html)) {
    final id = m.group(1)!.trim();
    if (!seen.add(id)) continue;
    final name = _cleanName(decodeHtmlEntities(m.group(5) ?? ''));
    if (name.isEmpty || name.length > 40) continue;
    if (name.contains('学分')) continue;
    final required = _numOf(m.group(3));
    final earned = _numOf(m.group(2));
    final parent = _parentOf(html, m.start);
    out.add({
      'name': name,
      'id': id,
      'required': required,
      'earned': earned,
      'missed': (required != null && earned != null && required >= earned)
          ? required - earned
          : null,
      'passed': (m.group(4) ?? '').trim() == '1',
      'parent': parent,
    });
  }
  _assignLevels(out);
  return out;
}

/// 模板里本节点的父节点 id：在 `<p ...>` 之前最近的 `fxfyqjd_id='...'`。
String _parentOf(String html, int pStart) {
  final from = (pStart - 2000).clamp(0, html.length);
  final prefix = html.substring(from, pStart);
  final m = RegExp(r"""fxfyqjd_id\s*=\s*['"]([^'"]*)['"]""").allMatches(prefix);
  var parent = '';
  for (final e in m) {
    parent = e.group(1)!.trim();
  }
  return parent;
}

/// 按 parent 链算层级（0 = 根）；父节点不在集合里的也算根，防脏数据成环。
void _assignLevels(List<Map<String, dynamic>> nodes) {
  final byId = {for (final n in nodes) '${n['id']}': n};
  for (final n in nodes) {
    var level = 0;
    var cur = '${n['parent'] ?? ''}';
    final guard = <String>{};
    while (cur.isNotEmpty && byId.containsKey(cur) && guard.add(cur)) {
      level++;
      cur = '${byId[cur]!['parent'] ?? ''}';
      if (level > 12) break;
    }
    n['level'] = level;
  }
}

/// 老版/静态方言：按 `<span id='showKc<id>'>` 占位符切段，
/// 每段里取**最近一次**出现的「要求学分 / 获得学分 / 未获得学分」三元组。
/// 用最近的而不是第一个：父子节点嵌套时，父节点的数字会先出现在子节点段里。
List<Map<String, dynamic>> _parseStaticCategories(String html) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  final spanRe = RegExp(
    r'''<span[^>]*\bid\s*=\s*["']showKc([^"']*)["'][^>]*>''',
    caseSensitive: false,
  );
  final matches = spanRe.allMatches(html).toList();
  var prevEnd = 0;
  for (final m in matches) {
    final start = prevEnd;
    prevEnd = m.end;
    final ctx = html.substring(start, m.start);
    final id = (m.group(1) ?? '').trim();
    final cat = _categoryOf(ctx, id);
    if (cat == null) continue;
    final key = id.isEmpty ? '${cat['name']}' : id;
    if (!seen.add(key)) continue;
    out.add(cat);
  }
  if (out.isNotEmpty) return out;

  // 没有 showKc 占位（页面改版 / 个别学校不展开课程）：退化成按「要求学分」切块，
  // 只给类别与学分；拿不到 id 也就没有课程明细。
  for (final m in RegExp(r'要求学分\s*[:：]?').allMatches(html)) {
    final from = (m.start - 400).clamp(0, html.length);
    final to = (m.start + 400).clamp(0, html.length);
    final cat = _categoryOf(html.substring(from, to), '');
    if (cat == null) continue;
    if (!seen.add('${cat['name']}|${cat['required']}')) continue;
    out.add(cat);
  }
  return out;
}

/// 把一段上下文解析成一个节点：名称取「要求学分」标签前最近的文本节点，
/// 学分取段内最后一次出现的数字。
Map<String, dynamic>? _categoryOf(String ctx, String id) {
  final required = _lastNum(ctx, RegExp(r'要求学分\s*[:：]?\s*(\d+(?:\.\d+)?)'));
  if (required == null) return null;
  final earned = _lastNum(ctx, RegExp(r'(?:^|[^未])获得学分\s*[:：]?\s*(\d+(?:\.\d+)?)'));
  final missed = _lastNum(ctx, RegExp(r'未获得学分\s*[:：]?\s*(\d+(?:\.\d+)?)'));
  final name = _categoryName(ctx);
  if (name.isEmpty || name.length > 24) return null;
  return {
    'name': name,
    'id': id,
    'required': required,
    'earned': earned,
    'missed': missed,
  };
}

/// 节点名称：「要求学分」之前最后一个不含量词的文本节点（如 `<a>专业核心课</a>`），
/// 拿不到再退回「按词回溯」的启发式。
String _categoryName(String ctx) {
  final idx = ctx.lastIndexOf('要求学分');
  if (idx <= 0) return '';
  final prefix = ctx.substring(0, idx);

  // 优先：最近的短文本节点（`>专业核心课<`）。
  String name = '';
  for (final m in RegExp(r'>([^<>]{1,40})<').allMatches(prefix)) {
    final t = _htmlToText(m.group(1)!);
    if (t.isEmpty || t.contains('学分') || t.contains('门')) continue;
    name = t;
  }
  if (name.isNotEmpty && name.length <= 24) return _cleanName(name);

  // 兜底：去标签后从尾部回溯，跳过数字/学分标签，最多拼 4 个词。
  final tokens = _htmlToText(prefix)
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  final kept = <String>[];
  for (final t in tokens.reversed) {
    if (RegExp(r'^[\d.：:％%]+$').hasMatch(t)) break;
    if (t.contains('学分') || t.startsWith('共') || t.startsWith('在读')) break;
    kept.insert(0, t);
    if (kept.length >= 4) break;
  }
  return _cleanName(kept.join(' '));
}

String _cleanName(String s) => s
    .replaceAll(RegExp(r'^["“”「」『』：:，,、\s\[\]【】]+'), '')
    .replaceAll(RegExp(r'["“”「」『』：:，,、\s\[\]【】]+$'), '')
    .trim();

num? _lastNum(String text, RegExp re) {
  num? out;
  for (final m in re.allMatches(text)) {
    out = _numOf(m.group(1)) ?? out;
  }
  return out;
}

// ==================== 通用 ====================

bool _looksLikeLoginPage(String html) {
  if (html.contains('login_slogin') || html.contains('login_getPublicKey')) return true;
  // 正方登录页骨架：<h5>用户登录</h5>（zfn_api 用同样的判定）
  return RegExp(r'<h5[^>]*>\s*用户登录\s*</h5>').hasMatch(html);
}

/// 去标签 + 解实体 + 压空白，得到人类可读文本。
String _htmlToText(String html) {
  final t = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
  return _squash(decodeHtmlEntities(t), keepSpace: true);
}

/// 压空白；[keepSpace] 时保留单个空格，否则连标点一起压掉（用于正则匹配统计文案）。
String _squash(String s, {bool keepSpace = false}) {
  var t = s.replaceAll(RegExp(r'\s+'), keepSpace ? ' ' : '');
  if (!keepSpace) {
    t = t.replaceAll(RegExp(r'[：:，,。；;、]'), '');
  }
  return t.trim();
}

/// 最小 HTML 实体解码（页面里常见的是 `&nbsp;`，其次是引号/尖括号）。
String decodeHtmlEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'");

num? _numOf(String? s) => s == null ? null : asNum(s);

/// 兼容 `[...]`、`{items:[...]}`、`{rows:[...]}`、`{data:[...]}` 几种包法。
List _itemsOf(dynamic json) {
  if (json is List) return json;
  if (json is Map) {
    for (final k in const ['items', 'rows', 'list', 'data']) {
      final v = json[k];
      if (v is List) return v;
    }
  }
  return const [];
}
