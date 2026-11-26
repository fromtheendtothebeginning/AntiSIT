/// 正方教务响应解析：成绩、周课表、考试安排（纯解析，不碰网络与登录态）。
library;

/// 32 位十六进制 GUID：部分课程的 kcb_id 是内部 ID（如毛概），不能当课程代码展示。
final RegExp _guidRe = RegExp(r'^[0-9A-Fa-f]{32}$');

/// 考试时间 kssj，如 2026-06-23(10:15-11:45)。
final RegExp _kssjRe = RegExp(r'^(\d{4}-\d{2}-\d{2})\((\d{1,2}:\d{2})-(\d{1,2}:\d{2})\)');

/// 从候选字段里挑第一个可读课程代码（跳过 GUID 内部 ID）。
String readableCourseCode(List<Object?> candidates) {
  for (final c in candidates) {
    final v = (c ?? '').toString().trim();
    if (v.isNotEmpty && !_guidRe.hasMatch(v)) return v;
  }
  return '';
}

/// 成绩条目 → 统一字段的成绩单行。
List<Map<String, dynamic>> parseJwxtGradeRows(Iterable<Object?> raw) {
  final grades = <Map<String, dynamic>>[];
  for (final it in raw.map((e) => e is Map ? e : const <String, dynamic>{})) {
    grades.add({
      'kcmc': it['kcmc'],
      'cj': it['cj'],
      'xf': it['xf'],
      'jd': it['jd'],
      'xfjd': it['xfjd'],
      'kclbmc': it['kclbmc'],
      'kcxzmc': it['kcxzmc'],
      'khfsmc': it['khfsmc'],
      'xqmmc': it['xqmmc'],
      'xnmmc': it['xnmmc'],
      'sfxwkc': it['sfxwkc'],
    });
  }
  return grades;
}

/// 绩点 = 成绩/10 - 5（满绩点 5.0）；总绩点 = Σ(绩点×学分)/Σ学分。
Map<String, dynamic> computeJwxtGpa(List<Map<String, dynamic>> grades) {
  var totalXfjd = 0.0;
  var totalXf = 0.0;
  for (final g in grades) {
    double jd;
    final cj = g['cj'];
    final cjF = cj == null ? null : double.tryParse(cj.toString());
    if (cjF == null) {
      jd = double.tryParse((g['jd'] ?? '0').toString()) ?? 0;
    } else {
      jd = double.parse((cjF / 10.0 - 5.0).toStringAsFixed(4));
    }
    final xfF = double.tryParse((g['xf'] ?? '').toString()) ?? 0.0;
    final xfjd = double.parse((jd * xfF).toStringAsFixed(4));
    g['jd'] = jd;
    g['xfjd'] = xfjd;
    totalXfjd += xfjd;
    totalXf += xfF;
  }
  return {
    'grades': grades,
    'gpa': totalXf == 0 ? 0 : double.parse((totalXfjd / totalXf).toStringAsFixed(4)),
    'count': grades.length,
  };
}

/// 从全量成绩条目提取学期列表（按学年/学期去重并排序）。
List<Map<String, dynamic>> parseJwxtTerms(Iterable<Object?> raw) {
  final terms = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final it in raw.whereType<Map>()) {
    final k1 = it['xnm'], k2 = it['xqm'];
    if (k1 == null || k2 == null) continue;
    final key = '$k1|$k2';
    if (seen.add(key)) {
      terms.add({
        'xnm': k1,
        'xqm': k2,
        'xnmmc': (it['xnmmc'] ?? '').toString(),
        'xqmmc': (it['xqmmc'] ?? '').toString(),
      });
    }
  }
  terms.sort((a, b) {
    final c = (a['xnmmc'] as String).compareTo(b['xnmmc'] as String);
    return c != 0 ? c : (a['xqm'] as String).compareTo(b['xqm'] as String);
  });
  return terms;
}

/// 某周课表条目 → 课程列表（节次非法或超出 11 节的条目跳过）。
List<Map<String, dynamic>> parseJwxtWeekCourses(Iterable<Object?> kbList) {
  final courses = <Map<String, dynamic>>[];
  for (final raw in kbList) {
    final it = raw is Map ? raw : const {};
    int slotStart, slotEnd, day;
    try {
      final jcs = (it['jcs'] ?? '').toString();
      if (jcs.contains('-')) {
        final parts = jcs.split('-');
        slotStart = int.parse(parts[0]) - 1;
        slotEnd = int.parse(parts[1]) - 1;
      } else {
        slotStart = slotEnd = int.parse(jcs) - 1;
      }
      day = (int.parse((it['xqj'] ?? '1').toString()) - 1).clamp(0, 6);
    } catch (_) {
      continue;
    }
    if (slotStart < 0 || slotEnd < slotStart || slotEnd >= 11) continue;
    courses.add({
      'name': (it['kcmc'] ?? '').toString().trim(),
      'place': (it['cdmc'] ?? '').toString().trim(),
      'teachers': (it['xm'] ?? '').toString().trim(),
      'code': readableCourseCode([it['kcb_id'], it['kch_id'], it['kch']]),
      'clazz': (it['jxbmc'] ?? it['jxb_id'] ?? '').toString().trim(),
      'day': day,
      'slotStart': slotStart,
      'slotEnd': slotEnd,
    });
  }
  return courses;
}

/// 该周日期安排（星期序号 + 日期）。
List<Map<String, dynamic>> parseJwxtWeekDates(List<dynamic> raw) => [
      for (final e in raw)
        if (e is Map) {'xqj': e['xqj'], 'rq': e['rq']},
    ];

/// 考试条目 → 考试安排（kssj 解析不了的条目跳过）。
List<Map<String, dynamic>> parseJwxtExams(Iterable<Object?> items) {
  final exams = <Map<String, dynamic>>[];
  for (final raw in items) {
    final it = raw is Map ? raw : const {};
    final m = _kssjRe.firstMatch((it['kssj'] ?? '').toString().trim());
    if (m == null) continue;
    String hm(String s) => '${s.split(':')[0].padLeft(2, '0')}:${s.split(':')[1]}';
    exams.add({
      'name': (it['kcmc'] ?? '').toString().trim(),
      'ksmc': (it['ksmc'] ?? '').toString().trim(),
      'date': m.group(1),
      'start': hm(m.group(2)!),
      'end': hm(m.group(3)!),
      'place': (it['cdmc'] ?? '').toString().trim(),
      'seat': (it['zwh'] ?? '').toString().trim(),
      'ksfs': (it['ksfs'] ?? '').toString().trim(),
    });
  }
  return exams;
}
