/// 正方教务 9.0 选课的数据模型与响应解析（纯解析，不碰网络与登录态）。
library;

import 'dart:convert';

import '../json_num.dart';

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

  /// 是否已满（有容量与已选人数且已达上限）。
  bool get isFull =>
      capacity != null && selected != null && capacity! > 0 && selected! >= capacity!;

  /// 剩余名额；容量未知返回 null。
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

  /// 是否已满（有容量与已选人数且已达上限）。
  bool get isFull =>
      capacity != null && selected != null && capacity! > 0 && selected! >= capacity!;

  /// 剩余名额；容量未知返回 null。
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

/// 选课结果：状态 + 学校原文。
class CourseSelectResult {
  const CourseSelectResult(this.status, [this.message = '']);

  final CourseSelectStatus status;
  final String message;

  /// 是否算成功（含「已选过」）。
  bool get ok =>
      status == CourseSelectStatus.success || status == CourseSelectStatus.alreadySelected;
}

/// 正方选课控制参数：xkkz_id 与 xkkz_xh 是两个独立值，不能互相推导。
class ZfSelectionControl {
  const ZfSelectionControl({this.id = '', this.xh = ''});

  final String id;
  final String xh;

  bool get isEmpty => id.isEmpty && xh.isEmpty;

  /// 两组控制值是否冲突（两边都有值且不同）。
  bool conflictsWith(ZfSelectionControl other) =>
      (id.isNotEmpty && other.id.isNotEmpty && id != other.id) ||
      (xh.isNotEmpty && other.xh.isNotEmpty && xh != other.xh);

  /// 补齐自身空缺的控制值；冲突时保持原值。
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

  /// 从隐藏域取值（兼容 firstXxx 兜底字段）。
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

/// 解析选课提交响应（成功多为纯文本 `1`，失败可能是 JSON 或 HTML 错误页）。
///
/// 名额满时学校回 `"已报人数,jxb_id,剩余,"` 的 msg，按此识别。
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
