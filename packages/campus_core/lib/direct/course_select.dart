/// 正方教务 9.0「学生选课」（zzxk）的页面参数解析与请求参数构造。
///
/// 协议移植自 zhengfang-apk（GPL-3.0，https://github.com/znjhahaha/zhengfang-apk）。
library;

import 'course_select_parser.dart';

export 'course_select_parser.dart';

/// 选课模块的 gnmkdm（正方 9.0 默认值）。
const String zfCourseGnmkdm = 'N253512';

/// 以下路径都相对教务根 `/jwglxt`。
const String zfCourseIndexPath = '/xsxk/zzxkyzb_cxZzxkYzbIndex.html';
const String zfCourseDisplayPath = '/xsxk/zzxkyzb_cxZzxkYzbDisplay.html';
const String zfCourseListPath = '/xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html';
const String zfSelectedCoursesPath = '/xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html';
const String zfSelectCoursePath = '/xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html';
const String zfCourseSectionsPath = '/xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html';

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

/// 解析首页的选课类别（新版写在 `queryCourse(...)` 调用里，旧版退回首页隐藏域）。
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
