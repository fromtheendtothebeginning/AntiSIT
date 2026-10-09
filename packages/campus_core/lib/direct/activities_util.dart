// 第二课堂活动说明的解析工具：名额 / 报名线索 / 校区 / 事后补录。
// 移植自 index 后端 campus/activities.py（报名线索规则源自 Second_Class_Notification）。

final List<RegExp> _qqRes = [
  RegExp(r'(?:QQ\s*群|qq群|群号|群\s*号)\D{0,8}(\d{5,12})', caseSensitive: false),
  RegExp(r'(\d{6,12})\s*(?:的)?\s*(?:QQ|qq)\s*群', caseSensitive: false),
  RegExp(r'(?:加|进|入)\s*群[^0-9\r\n]{0,6}(\d{6,12})'),
];

final RegExp _phoneRe = RegExp(r'1[3-9]\d{9}');

/// 联系方式的判定要具体，别用光秃秃的「群」「联系」——「社群创始人」「青年群体」会被误判。
final RegExp _contactRe = RegExp(
  r'(QQ\s*群|qq群|群\s*号|加\s*群|进\s*群|扫码|二维码|钉钉|微信群|'
  r'联\s*系\s*人|联系\s*电话|咨询\s*电话|报名\s*方式|报名\s*链\s*接|报名\s*请|'
  r'申请\s*加入|入\s*群)',
  caseSensitive: false,
);
final RegExp _contactExclude = RegExp(r'群体|社群|人群|群众|成群|超群');

final List<RegExp> _quotaRes = [
  RegExp(r'人数\s*[:：]?\s*(\d{1,4})\s*人'),
  RegExp(r'名额\s*[:：]?\s*(\d{1,4})\s*人?'),
  RegExp(r'(?:限|招收|招募|录取|报名人数)\s*[:：]?\s*(\d{1,4})\s*人'),
];
final RegExp _unlimitedRe = RegExp(r'(?:人数|名额)\s*不限');

/// 手机号：Dart 不支持 (?<!\d)/(?!\d) 回溯断言，手工校验边界。
List<String> _phonesIn(String text) {
  final out = <String>{};
  for (final m in _phoneRe.allMatches(text)) {
    final s = m.start, e = m.end;
    if (s > 0 && _isDigit(text.codeUnitAt(s - 1))) continue;
    if (e < text.length && _isDigit(text.codeUnitAt(e))) continue;
    out.add(m.group(0)!);
  }
  return out.toList();
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// 从活动说明里提取报名方式（QQ 群号、手机号、相关提示行）。
Map<String, dynamic> extractSignup(String? text) {
  final t = text ?? '';
  if (t.isEmpty) return {};
  final qq = <String>{};
  for (final r in _qqRes) {
    for (final m in r.allMatches(t)) {
      qq.add(m.group(1)!);
    }
  }
  final phone = _phonesIn(t);
  final qqList = qq.where((q) => q.length >= 5 && q.length <= 12 && !phone.contains(q)).toList()
    ..sort();
  final tips = ['扫码', '二维码', '扫码进群', '报名成功', '请勿申请', '无需报名']
      .where(t.contains)
      .toList();
  final lines = t
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final contact = lines
      .where((l) => _contactRe.hasMatch(l) && !_contactExclude.hasMatch(l))
      .toList();
  final out = <String, dynamic>{};
  if (qqList.isNotEmpty) out['qq'] = qqList;
  if (phone.isNotEmpty) out['phone'] = phone;
  if (tips.isNotEmpty) out['tips'] = tips;
  if (contact.isNotEmpty) out['contact_lines'] = contact.take(3).toList();
  return out;
}

/// 从说明里猜名额，如「人数30人」「名额：30」→「30 人」；找不到返回 null。
String? extractQuota(String? text) {
  final t = text ?? '';
  if (t.isEmpty || _unlimitedRe.hasMatch(t)) return null;
  for (final r in _quotaRes) {
    final m = r.firstMatch(t);
    if (m != null) return '${int.parse(m.group(1)!)} 人';
  }
  return null;
}

DateTime? parseDt(Object? text) {
  final s = (text ?? '').toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

/// 活动开始时间早于报名开始时间 → 活动早办完了，这个「报名」是事后补录登记。
bool isBackfill(Map a) {
  final ev = parseDt(a['hdkssj'] ?? a['_hdkssj']);
  final bm = parseDt(a['hdbmkssj'] ?? a['_hdbmkssj']);
  return ev != null && bm != null && ev.isBefore(bm);
}

/// 依据名称/说明里的「奉贤 / 徐汇」字样判断校区，未标注返回「未标注」。
String campusOf(Map a) {
  final b = '${a['hdmc'] ?? ''} ${a['_hdms'] ?? a['hdms'] ?? ''}';
  final xx = b.contains('徐汇');
  final fx = b.contains('奉贤');
  if (xx && fx) return '奉贤+徐汇';
  if (xx) return '徐汇';
  if (fx) return '奉贤';
  return '未标注';
}

/// 整理单条活动为看板视图（报名状态「即将/报名中/已结束」由前端按本机时间推导）。
Map<String, dynamic> activitySnapshot(Map a) {
  final hdms = (a['_hdms'] ?? a['hdms'] ?? '').toString();
  return {
    'id': a['id'],
    'name': (a['hdmc'] ?? '').toString(),
    'dlmc': (a['dlmc'] ?? a['_dlmc'] ?? '').toString(),
    'lbmc': (a['lbmc'] ?? a['_lbmc'] ?? '').toString(),
    'host': (a['zbfmc'] ?? '').toString(),
    'bm_start': a['hdbmkssj'],
    'bm_end': a['hdbmjzsj'],
    'start': a['hdkssj'],
    'end': a['hdjssj'],
    'campus': campusOf(a),
    'backfill': isBackfill(a),
    'quota': extractQuota(hdms),
    'signup': extractSignup(hdms),
    'hdms': hdms.length > 2000 ? hdms.substring(0, 2000) : hdms,
  };
}
