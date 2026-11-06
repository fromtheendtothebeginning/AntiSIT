/// 正方教务 9.0「学生选课」（zzxk）协议解析与请求参数构造。
///
/// 协议移植自开源项目 zhengfang-apk（GPL-3.0，
/// https://github.com/znjhahaha/zhengfang-apk）的 ZfAcademicAdapter / ZfSelectionControl，
/// 只保留 SIT 用得到的通用正方 9.0 部分。这里只做纯字符串/JSON 解析与参数拼装，
/// 不碰网络与登录态（那是 [JwxtClient] 的事），便于单测。
library;

import 'dart:convert';

import '../json_num.dart';

/// 选课模块的 gnmkdm（正方 9.0 默认值）。
const String zfCourseGnmkdm = 'N253512';

/// 以下路径都相对教务根 `/jwglxt`。
const String zfCourseIndexPath = '/xsxk/zzxkyzb_cxZzxkYzbIndex.html';
const String zfCourseDisplayPath = '/xsxk/zzxkyzb_cxZzxkYzbDisplay.html';
const String zfCourseListPath = '/xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html';
const String zfSelectedCoursesPath = '/xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html';
const String zfSelectCoursePath = '/xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html';
const String zfCourseSectionsPath = '/xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html';

/// 一个选课轮次/类别（主修、通识、体育…）。
class CourseScope {
  const CourseScope({
    required this.id,
    required this.name,
    this.term = '',
    required this.params,
  });

  final String id;
  final String name;
  final String term;

  /// 该轮次的全部控制参数（xkxnm/xkxqm/xkkz_id/xkkz_xh/kklxdm/njdm_id/zyh_id…）。
  final Map<String, String> params;
}

/// 可选课程（培养方案里的课程，展开后才有教学班）。
class CourseOffer {
  const CourseOffer({
    required this.id,
    required this.name,
    required this.teacher,
    required this.time,
    required this.location,
    required this.credit,
    required this.capacity,
    required this.selected,
    required this.scopeId,
    required this.raw,
  });

  final String id; // kch_id / kch
  final String name; // kcmc
  final String teacher;
  final String time;
  final String location;
  final String credit;
  final int? capacity; // jxbrl
  final int? selected; // yxzrs
  final String scopeId;
  final Map<String, String> raw;

  bool get isFull =>
      capacity != null && selected != null && capacity! > 0 && selected! >= capacity!;

  int? get remaining {
    if (capacity == null || selected == null) return null;
    final left = capacity! - selected!;
    return left < 0 ? 0 : left;
  }
}

/// 教学班（同一门课的不同老师/时间）。
class CourseSection {
  const CourseSection({
    required this.id,
    required this.courseId,
    required this.name,
    required this.teacher,
    required this.time,
    required this.location,
    required this.capacity,
    required this.selected,
    required this.raw,
  });

  final String id; // jxb_id
  final String courseId;
  final String name;
  final String teacher;
  final String time;
  final String location;
  final int? capacity;
  final int? selected;
  final Map<String, String> raw;

  /// 选课提交用的请求令牌（do_jxb_id，可能和 jxb_id 不同）。
  String get selectionId {
    final v = (raw['do_jxb_id'] ?? '').trim();
    return v.isEmpty ? id : v;
  }

  bool get isFull =>
      capacity != null && selected != null && capacity! > 0 && selected! >= capacity!;

  int? get remaining {
    if (capacity == null || selected == null) return null;
    final left = capacity! - selected!;
    return left < 0 ? 0 : left;
  }
}

/// 已选课程。
class SelectedCourse {
  const SelectedCourse({
    required this.id,
    required this.name,
    required this.teacher,
    required this.courseId,
    required this.sectionId,
  });

  final String id;
  final String name;
  final String teacher;
  final String courseId;
  final String sectionId;
}

/// 选课请求的业务结果。
enum CourseSelectStatus {
  success,
  noCapacity,
  alreadySelected,
  conflict,
  creditLimit,
  roundClosed,
  sessionExpired,
  needCaptcha,
  networkRetryable,
  unknown,
}

class CourseSelectResult {
  const CourseSelectResult(this.status, [this.message = '']);

  final CourseSelectStatus status;
  final String message;

  bool get ok =>
      status == CourseSelectStatus.success || status == CourseSelectStatus.alreadySelected;
}

// ==================== 控制字段 ====================

/// 正方选课控制参数：xkkz_id 与 xkkz_xh 是两个独立值，不能互相推导。
class ZfSelectionControl {
  const ZfSelectionControl({this.id = '', this.xh = ''});

  final String id;
  final String xh;

  bool get isEmpty => id.isEmpty && xh.isEmpty;

  bool conflictsWith(ZfSelectionControl other) =>
      (id.isNotEmpty && other.id.isNotEmpty && id != other.id) ||
      (xh.isNotEmpty && other.xh.isNotEmpty && xh != other.xh);

  ZfSelectionControl fillFrom(ZfSelectionControl other) {
    if (conflictsWith(other)) return this;
    return ZfSelectionControl(
      id: id.isNotEmpty ? id : other.id,
      xh: xh.isNotEmpty ? xh : other.xh,
    );
  }

  /// 页面返回了新的控制值：冲突时保留原值，否则补齐空缺。
  ZfSelectionControl withReturned(ZfSelectionControl other) =>
      conflictsWith(other) ? this : fillFrom(other);

  static ZfSelectionControl fromMap(Map<String, String>? values) {
    String value(String key) => (values?[key] ?? '').trim();
    final current = ZfSelectionControl(id: value('xkkz_id'), xh: value('xkkz_xh'));
    final first = ZfSelectionControl(id: value('firstXkkzId'), xh: value('firstXkkzXh'));
    return current.fillFrom(first);
  }
}

/// 页面 `queryCourse(...)` 里的一个选课类别。
class ZfCourseCategory {
  const ZfCourseCategory({
    required this.category,
    required this.control,
    required this.grade,
    required this.major,
    this.name = '',
  });

  final String category; // kklxdm
  final ZfSelectionControl control;
  final String grade; // njdm_id
  final String major; // zyh_id
  final String name; // kklxmc

  /// 合并首页隐藏域与类别展示页返回的隐藏域，得到该轮次的完整请求参数。
  Map<String, String> merge(Map<String, String> index,
      [Map<String, String> display = const {}]) {
    final out = Map<String, String>.from(index);
    for (final key in const ['firstXkkzId', 'firstXkkzXh', 'xkkz_id', 'xkkz_xh']) {
      out.remove(key);
    }
    out.addAll(display);
    final control = this.control.withReturned(ZfSelectionControl.fromMap(display));
    if (control.id.isNotEmpty) out['xkkz_id'] = control.id;
    if (control.xh.isNotEmpty) out['xkkz_xh'] = control.xh;
    out['kklxdm'] = category;
    out['njdm_id'] = grade;
    out['zyh_id'] = major;
    if (name.isNotEmpty) out['kklxmc'] = name;
    return out;
  }
}

// ==================== HTML / JSON 解析 ====================

/// 最小 HTML 实体解码（正方页面常见 `&nbsp;`）。
String decodeZfEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'");

/// 登录页判定：302 由 HttpSession 判，这里兜住「200 + 登录页 HTML」。
bool isZfLoginPage(String html) =>
    html.contains('login_slogin') ||
    html.contains('login_getPublicKey') ||
    RegExp(r'<h5[^>]*>\s*用户登录\s*</h5>').hasMatch(html);

/// 取页面里 `<input type="hidden" name="x" value="y">` 的隐藏域。
Map<String, String> parseZfHiddenFields(String html) {
  final out = <String, String>{};
  final tagRe = RegExp(r'<input\b[^>]*>', caseSensitive: false);
  final typeRe = RegExp(r'''\btype\s*=\s*["']([^"']*)["']''', caseSensitive: false);
  final nameRe = RegExp(r'''\bname\s*=\s*["']([^"']*)["']''', caseSensitive: false);
  final valueRe = RegExp(r'''\bvalue\s*=\s*["']([^"']*)["']''', caseSensitive: false);
  for (final m in tagRe.allMatches(html)) {
    final tag = m.group(0)!;
    final type = (typeRe.firstMatch(tag)?.group(1) ?? '').trim().toLowerCase();
    if (type.isNotEmpty && type != 'hidden') continue;
    final name = (nameRe.firstMatch(tag)?.group(1) ?? '').trim();
    if (name.isEmpty) continue;
    out[name] = decodeZfEntities(valueRe.firstMatch(tag)?.group(1) ?? '');
  }
  return out;
}

/// 解析首页的选课类别。
///
/// 新版正方把类别写在 `queryCourse('kklxdm','xkkz_id','njdm_id','zyh_id','xkkz_xh')`
/// 调用里；没有该调用时退回首页隐藏域里的 firstXxx / 默认字段。
List<ZfCourseCategory> parseZfCourseCategories(
    String html, Map<String, String> hidden) {
  final first = ZfSelectionControl.fromMap({
    'xkkz_id': hidden['firstXkkzId'] ?? '',
    'xkkz_xh': hidden['firstXkkzXh'] ?? '',
  });
  final firstControl = first.isEmpty ? ZfSelectionControl.fromMap(hidden) : first;
  final xhOnly = firstControl.id.isEmpty && firstControl.xh.isNotEmpty;

  final callRe = RegExp(
    r"""queryCourse\s*\(\s*(?:this\s*,\s*)?((?:['"][^'"]*['"]\s*,\s*){3,4}['"][^'"]*['"])\s*\)""",
  );
  final argRe = RegExp(r"""['"]([^'"]*)['"]""");
  final out = <ZfCourseCategory>[];
  final seen = <String>{};
  for (final call in callRe.allMatches(html)) {
    final args = argRe
        .allMatches(call.group(1) ?? '')
        .map((m) => m.group(1) ?? '')
        .toList();
    if (args.length < 4) continue;
    final category = args[0].trim();
    final id = args[1].trim();
    final control = xhOnly
        ? ZfSelectionControl(xh: id)
        : ZfSelectionControl(
            id: id,
            xh: args.length >= 5
                ? args[4].trim()
                : (id == firstControl.id ? firstControl.xh : ''),
          );
    final item = ZfCourseCategory(
      category: category,
      control: control,
      grade: args[2].trim(),
      major: args[3].trim(),
    );
    final key = '${item.category}|${item.control.id}|${item.control.xh}|'
        '${item.grade}|${item.major}';
    if (seen.add(key)) out.add(item);
  }
  if (out.isNotEmpty) return out;

  if (firstControl.isEmpty) return const [];
  String value(String primary, String fallback) {
    final v = (hidden[primary] ?? '').trim();
    return v.isNotEmpty ? v : (hidden[fallback] ?? '').trim();
  }

  return [
    ZfCourseCategory(
      category: value('firstKklxdm', 'kklxdm'),
      control: firstControl,
      grade: value('firstNjdmId', 'njdm_id'),
      major: value('firstZyhId', 'zyh_id'),
      name: value('firstKklxmc', 'kklxmc'),
    ),
  ];
}

/// 选课轮次的展示页参数（获取该类别最新的 xkkz 控制值）。
Map<String, String> buildZfDisplayParams(
    Map<String, String> index, ZfCourseCategory category) {
  final merged = category.merge(index);
  merged['xszxzt'] = '1';
  merged['kspage'] = '0';
  merged['jspage'] = '0';
  final out = <String, String>{};
  for (final key in const [
    'kklxdm', 'xszxzt', 'njdm_id', 'zyh_id', 'kspage', 'jspage',
  ]) {
    final v = merged[key];
    if (v != null) out[key] = v;
  }
  _addControl(out, merged, both: false);
  return out;
}

// ==================== 请求参数 ====================

const List<String> _commonFields = [
  'rwlx', 'xklc', 'xkly', 'bklx_id', 'sfkkjyxdxnxq', 'kzkcgs', 'xqh_id', 'jg_id',
  'njdm_id', 'zyh_id', 'zyfx_id', 'bh_id', 'xbm', 'xslbdm', 'mzm', 'xz', 'ccdm',
  'xsbj', 'gnjkxdnj', 'sfkknj', 'sfkkzy', 'kzybkxy', 'sfznkx', 'zdkxms', 'sfkxq',
  'sfkcfx', 'kkbk', 'kkbkdj', 'bklbkcj', 'xkxnm', 'xkxqm', 'kklxdm', 'bbhzxjxb',
  'zxgbxkkg', 'rlkz',
];

const List<String> _courseFields = [
  ..._commonFields,
  'njdm_id_1', 'zyh_id_1', 'njdm_id_xs', 'zyh_id_xs', 'bjgkczxbbjwcx',
  'bhbcyxkjxb', 'sfkgbcx', 'sfrxtgkcxd', 'tykczgxdcs', 'xkzgbj', 'jxbzb', 'zh',
  'kspage', 'jspage',
];

const List<String> _sectionFields = [
  ..._commonFields,
  'kch_id', 'bhbcyxkjxb', 'jxbzcxskg', 'xkxskcgskg', 'cxbj', 'fxbj',
  'cxcykclxxskg', 'rlzlkz', 'txbsfrl', 'cdrlkz',
];

const List<String> _selectionFields = [
  'jxb_ids', 'kch_id', 'kcmc', 'rwlx', 'rlkz', 'cdrlkz', 'rlzlkz', 'sxbj', 'xxkbj',
  'qz', 'cxbj', 'njdm_id', 'zyh_id', 'kklxdm', 'xklc', 'xkxnm', 'xkxqm',
  'jcxx_id', 'xkly', 'sfkxq',
];

const List<String> _selectedFields = [
  'xkxnm', 'xkxqm', 'xqh_id', 'jg_id', 'njdm_id', 'zyh_id', 'zyfx_id', 'bh_id',
  'xz', 'ccdm', 'xkly',
];

Map<String, String> _pick(Map<String, String> source, List<String> keys) {
  final out = <String, String>{};
  for (final key in keys) {
    final v = source[key];
    if (v != null) out[key] = v;
  }
  return out;
}

void _addControl(Map<String, String> out, Map<String, String> source,
    {required bool both}) {
  final control = ZfSelectionControl.fromMap(source);
  if (control.id.isNotEmpty) out['xkkz_id'] = control.id;
  if (control.xh.isNotEmpty && (both || control.id.isEmpty)) {
    out['xkkz_xh'] = control.xh;
  }
}

void _addJgId(Map<String, String> out, Map<String, String> source) {
  final jg1 = (source['jg_id_1'] ?? '').trim();
  if (jg1.isNotEmpty) out['jg_id'] = jg1;
}

/// 课程列表请求参数（对应正方 zzxkYzb.js 的 requestMap）。
Map<String, String> buildZfCourseListParams(
  Map<String, String> source, {
  String keyword = '',
  int start = 0,
  int pageSize = 50,
}) {
  final out = _pick(source, _courseFields);
  _addControl(out, source, both: true);
  _addJgId(out, source);
  for (final e in source.entries) {
    if (e.key.startsWith('filter_list[')) out[e.key] = e.value;
  }
  if (keyword.isNotEmpty) out['filter_list[0]'] = keyword;
  if (source['jxbzbkg'] == '1') {
    out['jxbzb'] = source['jxbzb'] ?? '';
  } else {
    out.remove('jxbzb');
  }
  if (source['jxbzhkg'] == '1') {
    out['zh'] = source['zh'] ?? '';
  } else {
    out.remove('zh');
  }
  out['kspage'] = '${start + 1}';
  out['jspage'] = '${start + pageSize}';
  return out;
}

/// 教学班列表请求参数。
Map<String, String> buildZfSectionParams(CourseOffer course) {
  final out = _pick(course.raw, _sectionFields);
  _addControl(out, course.raw, both: false);
  _addJgId(out, course.raw);
  out['kch_id'] = course.id;
  return out;
}

/// 选课提交参数。
Map<String, String> buildZfSelectParams(
    CourseOffer course, CourseSection section) {
  final merged = <String, String>{...course.raw, ...section.raw};
  final out = _pick(merged, _selectionFields);
  _addControl(out, course.raw, both: false);
  out['jxb_ids'] = section.selectionId;
  out['kch_id'] = course.id;
  final name = course.name.isNotEmpty ? course.name : (course.raw['kcmc'] ?? '');
  if (name.isNotEmpty) out['kcmc'] = name;
  final category = (course.raw['kklxdm'] ?? '').trim();
  if (category.isNotEmpty) out['kklxdm'] = category;
  return out;
}

/// 已选课程列表请求参数。
Map<String, String> buildZfSelectedParams(Map<String, String> scopeParams) {
  final out = _pick(scopeParams, _selectedFields);
  _addJgId(out, scopeParams);
  return out;
}

// ==================== 响应解析 ====================

Object? _decodeJson(Object? json) {
  if (json is String) {
    try {
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }
  return json;
}

List<dynamic> _rowsOf(Object? json, List<String> preferred) {
  final decoded = _decodeJson(json);
  if (decoded is List) return decoded;
  if (decoded is Map) {
    final containers = <Map>[
      decoded,
      if (decoded['data'] is Map) decoded['data'] as Map,
      if (decoded['result'] is Map) decoded['result'] as Map,
    ];
    for (final container in containers) {
      for (final key in [...preferred, 'data', 'aaData', 'rows', 'list']) {
        final v = container[key];
        if (v is List) return v;
      }
    }
  }
  return const [];
}

Map<String, String> _stringMapOf(Map raw) {
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (v == null) return;
    final s = '$v'.trim();
    if (s.isNotEmpty && s != 'null') out['$k'] = s;
  });
  return out;
}

String _first(Map<String, String> raw, List<String> keys) {
  for (final key in keys) {
    final v = (raw[key] ?? '').trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// 解析课程列表 JSON（`tmpList` / `courses` / `items` / `data` 等包法都兼容）。
List<CourseOffer> parseZfCourseOffers(
  Object? json, {
  required String scopeId,
  Map<String, String> scopeParams = const {},
}) {
  final out = <CourseOffer>[];
  for (final raw in _rowsOf(json, const ['tmpList', 'courses', 'items'])) {
    if (raw is! Map) continue;
    final fields = _stringMapOf(raw);
    final id = _first(fields, const ['kch_id', 'kch', 'kcid', 'jx0404id']);
    final name = _first(fields, const ['kcmc', 'kc_mc', 'fzmc', 'ktmc']);
    if (id.isEmpty && name.isEmpty) continue;
    out.add(CourseOffer(
      id: id,
      name: name,
      teacher: _first(fields, const ['jsxm', 'skls', 'xm', 'jsxx']),
      time: _first(fields, const ['sksj', 'sksjmc']),
      location: _first(fields, const ['jxdd', 'skdd', 'skddyw']),
      credit: _first(fields, const ['xf']),
      capacity: asInt(_first(fields, const ['jxbrl', 'capacity', 'xkrs'])),
      selected: asInt(_first(fields, const ['yxzrs', 'yxrs', 'selected'])),
      scopeId: scopeId,
      raw: {...scopeParams, ...fields},
    ));
  }
  return out;
}

/// 解析教学班列表 JSON。
List<CourseSection> parseZfCourseSections(Object? json, CourseOffer course) {
  final out = <CourseSection>[];
  for (final raw in _rowsOf(json, const ['tmpList', 'data', 'courses', 'jxbList'])) {
    if (raw is! Map) continue;
    final fields = _stringMapOf(raw);
    final id = _first(fields, const ['jxb_id', 'do_jxb_id']);
    if (id.isEmpty) continue;
    out.add(CourseSection(
      id: id,
      courseId: course.id,
      name: _first(fields, const ['jxbmc', 'ktmc', 'fzmc']),
      teacher: _first(fields, const ['jsxm', 'skls', 'xm', 'jsxx']),
      time: _first(fields, const ['sksj', 'sksjmc']),
      location: _first(fields, const ['jxdd', 'skdd']),
      capacity: asInt(_first(fields, const ['jxbrl', 'capacity'])),
      selected: asInt(_first(fields, const ['yxzrs', 'yxrs', 'selected'])),
      raw: fields,
    ));
  }
  return out;
}

/// 解析已选课程列表 JSON。
List<SelectedCourse> parseZfSelectedCourses(Object? json) {
  final out = <SelectedCourse>[];
  for (final raw in _rowsOf(json, const ['tmpList', 'courses', 'items', 'data'])) {
    if (raw is! Map) continue;
    final fields = _stringMapOf(raw);
    final id = _first(fields, const ['do_jxb_id', 'jxb_id', 'jx0404id', 'jx0501id', 'kch']);
    final name = _first(fields, const ['kcmc', 'kc_mc']);
    if (id.isEmpty && name.isEmpty) continue;
    out.add(SelectedCourse(
      id: id,
      name: name,
      teacher: _first(fields, const ['jsxm', 'skls', 'xm']),
      courseId: _first(fields, const ['kch_id', 'kcid', 'jx02id', 'kch']),
      sectionId: _first(fields, const ['jxb_id', 'jx0404id', 'jx0501id']),
    ));
  }
  return out;
}

String _htmlToText(String html) {
  final text = decodeZfEntities(html.replaceAll(RegExp(r'<[^>]+>'), ' '));
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _messageOf(Object? json, String fallback) {
  if (json is Map) {
    for (final key in const ['message', 'msg', 'msgContent', 'error']) {
      final v = '${json[key] ?? ''}'.trim();
      if (v.isNotEmpty && v != 'null') return v;
    }
  }
  final text = _htmlToText(fallback);
  return text.length > 180 ? text.substring(0, 180) : text;
}

CourseSelectStatus _classify(String message) {
  if (RegExp(r'请先登录|登录超时|会话失效|登录已失效|notLogin', caseSensitive: false)
      .hasMatch(message)) {
    return CourseSelectStatus.sessionExpired;
  }
  if (message.contains('验证码') ||
      message.toLowerCase().contains('verifycode')) {
    return CourseSelectStatus.needCaptcha;
  }
  if (message.contains('冲突')) return CourseSelectStatus.conflict;
  if (RegExp(r'学分上限|超过学分|超出学分|学分限制').hasMatch(message)) {
    return CourseSelectStatus.creditLimit;
  }
  if (RegExp(r'未开始|未开放|已结束|选课时间已过|不在选课时间|当前不属于选课阶段|只可退课')
      .hasMatch(message)) {
    return CourseSelectStatus.roundClosed;
  }
  if (RegExp(r'已选该|已经选|重复选课|已选此').hasMatch(message)) {
    return CourseSelectStatus.alreadySelected;
  }
  if (RegExp(r'已满|无余量|名额不足|容量不足|人数已满').hasMatch(message)) {
    return CourseSelectStatus.noCapacity;
  }
  if (message.contains('成功')) return CourseSelectStatus.success;
  return CourseSelectStatus.unknown;
}

/// 解析选课提交响应。
///
/// 正方成功时通常直接回 `1`；失败时可能是 JSON（`flag`/`msg`）或 HTML 错误页。
/// 名额满时前端按 `"已报人数,jxb_id,剩余,"` 的 `msg` 识别，这里同样处理。
CourseSelectResult parseZfSelectResponse(String body, int statusCode) {
  final trimmed = body.trim();
  if (isZfLoginPage(trimmed)) {
    return const CourseSelectResult(CourseSelectStatus.sessionExpired);
  }
  if (statusCode == 401 || statusCode == 403) {
    return const CourseSelectResult(CourseSelectStatus.sessionExpired);
  }
  if (statusCode == 429) {
    return const CourseSelectResult(CourseSelectStatus.networkRetryable);
  }
  if (statusCode >= 500) {
    return CourseSelectResult(
        CourseSelectStatus.unknown, '教务系统返回 HTTP $statusCode，请到已选课程确认结果');
  }
  if (trimmed == '1' || trimmed == '"1"') {
    return const CourseSelectResult(CourseSelectStatus.success, '选课成功');
  }

  final json = _decodeJson(trimmed);
  if (json is Map) {
    final flag = '${json['flag'] ?? ''}'.trim();
    final code = '${json['code'] ?? ''}'.trim();
    final success = json['success'];
    if (flag == '1' || success == true || code == '0' || code == '200') {
      return const CourseSelectResult(CourseSelectStatus.success, '选课成功');
    }
    final msg = _messageOf(json, body);
    if ((flag == '-1' || flag == '0') &&
        RegExp(r'^\d+,[0-9A-Za-z]+,\d*,?$').hasMatch(msg)) {
      return CourseSelectResult(CourseSelectStatus.noCapacity, msg);
    }
    final conflictId = '${json['yxjx0404id'] ?? ''}'.trim();
    if (conflictId.isNotEmpty && conflictId != 'null') {
      return CourseSelectResult(CourseSelectStatus.conflict, msg);
    }
    return CourseSelectResult(_classify(msg), msg);
  }

  final msg = _messageOf(null, body);
  if (msg.isEmpty) {
    return const CourseSelectResult(
        CourseSelectStatus.unknown, '教务没有返回明确结果，请到已选课程确认');
  }
  return CourseSelectResult(_classify(msg), msg);
}
