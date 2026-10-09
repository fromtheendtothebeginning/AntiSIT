
/// 演示模式假数据：按请求路径路由，响应结构与 campus-api.md 保持一致。
class DemoData {
  DemoData._();

  static double cardBalance = 56.70;
  static double eleBalance = 23.45;
  static const semesterStart = '2026-09-07'; // 周一

  static Future<Map<String, dynamic>> handle(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    switch (path) {
      case '/api/campus-open/status':
        return {
          'ok': true,
          'configured': true,
          'student_id_masked': '25****01',
          'has_pay_password': true,
          'has_dorm': true,
          'auto_captcha': true,
          'session': {'connected': true, 'status': 'connected', 'error': null},
          'cas_ready': true,
          'jwxt_ready': true,
        };
      case '/api/campus-open/disconnect':
        return {'ok': true};
      case '/api/campus-open/score':
        return {'ok': true, 'data': _score};
      case '/api/campus-open/grades':
        return {'ok': true, 'data': _grades(query: query)};
      case '/api/campus-open/activities':
        return {'ok': true, 'data': {'student_id': '25110001', 'activities': _activities}};
      case '/api/campus-open/timetable/week':
        return _week((body?['zs'] ?? 1) as int);
      case '/api/campus-open/timetable/exams':
        return {'ok': true, 'exams': _exams};
      case '/api/campus-open/ecard':
        return {
          'ok': true,
          'data': {
            'image': null,
            'type': 'image/png',
            'code': 'DEMO|25110001|${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
            'card_balance': cardBalance,
            'refresh': 55,
          },
        };
      case '/api/campus-open/electricity/query':
        return {
          'ok': true,
          'data': {'balance': eleBalance, 'card_balance': cardBalance, 'remain': 102.3, 'dorm': '示例楼101'},
        };
      case '/api/campus-open/electricity/history':
        return {'ok': true, 'records': _eleHistory()};
      case '/api/campus-open/electricity/recharge':
        final amount = (body?['amount'] as num?) ?? 0;
        eleBalance += amount;
        return {
          'ok': true,
          'message': '充值成功（演示）',
          'data': {'balance': eleBalance, 'card_balance': cardBalance, 'amount': amount},
        };
    }
    if (path.startsWith('/api/campus-open/activities/')) {
      final aid = path.split('/').last;
      final a = _activities.firstWhere((e) => e['id'] == aid, orElse: () => _activities.first);
      return {'ok': true, 'data': a};
    }
    throw StateError('demo 未实现的接口: $path');
  }

  /// 电费历史：余额缓慢下降 + 周期性充值，升序。
  static List<Map<String, dynamic>> _eleHistory() {
    final now = DateTime.now();
    final list = <Map<String, dynamic>>[];
    var balance = 128.0;
    for (var i = 89; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      balance -= 1.2 + (i % 5) * 0.35;
      var recharge = 0.0;
      if (i % 22 == 7) {
        recharge = 50;
        balance += 50;
      }
      String two(int n) => n.toString().padLeft(2, '0');
      list.add({
        'balance': double.parse(balance.toStringAsFixed(2)),
        'remain': balance * 4.3,
        'dorm': '示例楼101',
        'time': '${d.year}-${two(d.month)}-${two(d.day)} 22:00:0${two(i % 6)[0]}',
        'recharge': recharge,
      });
    }
    return list;
  }

  static final _score = {
    'student': {
      'xh': '25110001', 'xm': '张三', 'nj': '2026',
      'bmmc': '计算机学院', 'zymc': '计算机科学与技术', 'bjmc': '计科2501',
    },
    'total': 8.0,
    'credit': 5.5,
    'groups': [
      {'name': '德育', 'subtotal': 2.0, 'rows': [
        {'name': '讲座报告', 'value': 0.8},
        {'name': '主题教育', 'value': 0.4},
        {'name': '志愿公益', 'value': 0.8},
      ]},
      {'name': '劳育', 'subtotal': 3.0, 'rows': [
        {'name': '劳动课堂', 'value': 1.5},
        {'name': '社会实践', 'value': 1.5},
      ]},
      {'name': '美育', 'subtotal': 1.0, 'rows': []},
      {'name': '健康教育', 'subtotal': 0.5, 'rows': []},
    ],
  };

  static Map<String, dynamic> _grades({Map<String, String>? query}) {
    final xnm = query?['xnm'];
    final xqm = query?['xqm'];
    List grades;
    List terms;
    if (xnm == '2025') {
      grades = _grades25;
      terms = [_term25_3];
    } else if (xnm == '2026') {
      grades = _grades26;
      terms = [_term26_3];
    } else {
      grades = [..._grades26, ..._grades25];
      terms = [_term26_3, _term25_3];
    }
    if (xqm == '12') grades = grades.where((g) => (g['xqmmc'] as String).contains('第二')).toList();
    double sumJd = 0, sumXf = 0;
    for (final g in grades) {
      final xf = double.tryParse('${g['xf']}') ?? 0;
      sumJd += (g['jd'] as num) * xf;
      sumXf += xf;
    }
    return {
      'grades': grades,
      'gpa': sumXf == 0 ? 0 : double.parse((sumJd / sumXf).toStringAsFixed(2)),
      'count': grades.length,
      'terms': terms,
    };
  }

  static const _term26_3 = {'xnm': '2026', 'xqm': '3', 'xnmmc': '2026-2027学年', 'xqmmc': '第一学期'};
  static const _term25_3 = {'xnm': '2025', 'xqm': '3', 'xnmmc': '2025-2026学年', 'xqmmc': '第一学期'};

  static List<Map<String, dynamic>> get _grades26 => [
    _g('高等数学(上)', '92', '4.0', 4.2, '必修', '考试', '2026-2027学年', '第一学期'),
    _g('大学英语(一)', '88', '3.0', 3.8, '必修', '考试', '2026-2027学年', '第一学期'),
    _g('程序设计基础', '95', '4.0', 4.5, '必修', '考试', '2026-2027学年', '第一学期'),
    _g('思想道德与法治', '90', '2.5', 4.0, '必修', '考查', '2026-2027学年', '第一学期'),
    _g('大学体育(一)', '86', '1.0', 3.6, '必修', '考查', '2026-2027学年', '第一学期'),
    _g('军事理论', 'P', '1.0', 4.0, '必修', '考查', '2026-2027学年', '第一学期'),
  ];

  static List<Map<String, dynamic>> get _grades25 => [
    _g('高等数学(上)', '90', '4.0', 4.0, '必修', '考试', '2025-2026学年', '第一学期'),
    _g('线性代数', '85', '2.0', 3.5, '必修', '考试', '2025-2026学年', '第一学期'),
    _g('中国近现代史纲要', '92', '2.0', 4.2, '必修', '考查', '2025-2026学年', '第一学期'),
  ];

  static Map<String, dynamic> _g(String kcmc, String cj, String xf, num jd, String lb, String fs, String xn, String xq) => {
    'kcmc': kcmc, 'cj': cj, 'xf': xf, 'jd': jd, 'xfjd': jd * (double.tryParse(xf) ?? 0),
    'kclbmc': lb, 'kcxzmc': '主修', 'khfsmc': fs, 'xqmmc': '奉贤校区', 'xnmmc': xn, 'sfxwkc': '否',
  };

  static final List<Map<String, dynamic>> _activities = [
    {
      'id': 'a001', 'name': 'AI 赋能学习效率提升讲座', 'dlmc': '思想成长', 'lbmc': '讲座报告',
      'host': '校学生会', 'bm_start': '2026-09-25 10:00:00', 'bm_end': '2026-10-08 22:00:00',
      'start': '2026-10-10 14:00:00', 'end': '2026-10-10 16:00:00', 'campus': '奉贤',
      'backfill': false, 'quota': '200 人',
      'signup': {'qq': ['765432198'], 'phone': ['13800000000'], 'tips': ['扫码报名', '到场签到'], 'contact_lines': ['联系人：李同学']},
      'hdms': '本次讲座邀请企业 AI 工程师分享大模型在学习场景的实践应用，涵盖资料检索、论文阅读、代码辅助等主题。参与即可获得第二课堂思想成长模块 0.2 分，请提前 10 分钟入场签到。',
    },
    {
      'id': 'a002', 'name': '秋季校园马拉松志愿者', 'dlmc': '社会实践', 'lbmc': '志愿服务',
      'host': '校团委', 'bm_start': '2026-10-05 12:00:00', 'bm_end': '2026-10-12 18:00:00',
      'start': '2026-10-18 07:00:00', 'end': '2026-10-18 13:00:00', 'campus': '奉贤+徐汇',
      'backfill': false, 'quota': '80 人',
      'signup': {'qq': ['123456789'], 'phone': [], 'tips': ['名额有限，先到先得'], 'contact_lines': []},
      'hdms': '负责赛道补给站物资发放与观众引导，提供午餐与志愿服务证明，计社会实践 0.5 分。',
    },
    {
      'id': 'a003', 'name': '实验室开放日参观', 'dlmc': '创新创业', 'lbmc': '实践活动',
      'host': '计算机学院', 'bm_start': '2026-09-01 09:00:00', 'bm_end': '2026-09-15 17:00:00',
      'start': '2026-09-20 13:30:00', 'end': '2026-09-20 17:00:00', 'campus': '奉贤',
      'backfill': false, 'quota': '30 人',
      'signup': {'qq': [], 'phone': ['13900000000'], 'tips': [], 'contact_lines': ['联系人：王老师']},
      'hdms': '参观人工智能实验室与机器人实验室，了解本科生科研训练项目报名方式。',
    },
    {
      'id': 'a004', 'name': '校园十佳歌手大赛', 'dlmc': '文体活动', 'lbmc': '文艺活动',
      'host': '大学生艺术团', 'bm_start': '2026-08-20 10:00:00', 'bm_end': '2026-09-02 22:00:00',
      'start': '2026-09-12 18:30:00', 'end': '2026-09-12 21:30:00', 'campus': '奉贤',
      'backfill': true, 'quota': '500 人',
      'signup': {'qq': ['222333444'], 'phone': [], 'tips': ['观众凭校园码入场'], 'contact_lines': []},
      'hdms': '年度校园文艺盛会，观众到场扫码签到计文体活动 0.2 分。',
    },
    {
      'id': 'a005', 'name': '考研经验分享会', 'dlmc': '思想成长', 'lbmc': '讲座报告',
      'host': '学院学习部', 'bm_start': '2026-10-01 10:00:00', 'bm_end': '2026-10-09 20:00:00',
      'start': '2026-10-11 19:00:00', 'end': '2026-10-11 20:30:00', 'campus': '徐汇',
      'backfill': false, 'quota': '120 人',
      'signup': {'qq': ['888777666'], 'phone': [], 'tips': ['线上腾讯会议同步'], 'contact_lines': ['联系人：刘同学']},
      'hdms': '邀请 2026 届上岸学长学姐分享择校、复习规划与复试经验。',
    },
  ];

  // —— 演示课表模板：weeks 为 [起周, 止周] ——
  static const _template = [
    {'name': '高等数学(下)', 'place': '二教E101', 'teachers': '王建国', 'code': 'MA1102', 'clazz': '数学2501-01', 'day': 0, 'slotStart': 0, 'slotEnd': 1, 'weeks': [1, 17]},
    {'name': '大学英语(二)', 'place': '外教楼305', 'teachers': '李梅', 'code': 'EN1102', 'clazz': '英语2503-02', 'day': 0, 'slotStart': 2, 'slotEnd': 2, 'weeks': [1, 17]},
    {'name': '数据结构', 'place': '一教A203', 'teachers': '陈强', 'code': 'CS2101', 'clazz': '计科2501-01', 'day': 1, 'slotStart': 0, 'slotEnd': 1, 'weeks': [1, 16]},
    {'name': '数据结构实验', 'place': '实验楼506', 'teachers': '陈强', 'code': 'CS2102', 'clazz': '计科2501-02', 'day': 3, 'slotStart': 3, 'slotEnd': 4, 'weeks': [2, 16]},
    {'name': '大学物理(二)', 'place': '二教B110', 'teachers': '赵芳', 'code': 'PH1201', 'clazz': '物理2502-01', 'day': 2, 'slotStart': 2, 'slotEnd': 2, 'weeks': [1, 17]},
    {'name': '思想道德与法治', 'place': '一教C108', 'teachers': '孙丽', 'code': 'PY1101', 'clazz': '思政2501-05', 'day': 4, 'slotStart': 0, 'slotEnd': 1, 'weeks': [1, 15]},
    {'name': '大学体育(二)', 'place': '体育馆', 'teachers': '周斌', 'code': 'PE1102', 'clazz': '体育 Club-08', 'day': 4, 'slotStart': 3, 'slotEnd': 3, 'weeks': [1, 16]},
    {'name': '线性代数', 'place': '二教E201', 'teachers': '吴敏', 'code': 'MA1201', 'clazz': '数学2502-03', 'day': 2, 'slotStart': 3, 'slotEnd': 4, 'weeks': [1, 17]},
    {'name': '程序设计实践', 'place': '实验楼402', 'teachers': '郑浩', 'code': 'CS1105', 'clazz': '计科2501-01', 'day': 1, 'slotStart': 3, 'slotEnd': 4, 'weeks': [3, 14]},
  ];

  static Map<String, dynamic> _week(int zs) {
    final start = DateTime.parse(semesterStart);
    final monday = start.add(Duration(days: (zs - 1) * 7));
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final dates = List.generate(7, (i) => {'xqj': i + 1, 'rq': fmt(monday.add(Duration(days: i)))});
    final courses = _template
        .where((c) => zs >= (c['weeks'] as List)[0] && zs <= (c['weeks'] as List)[1])
        .map((c) => {
              'name': c['name'], 'place': c['place'], 'teachers': c['teachers'],
              'code': c['code'], 'clazz': c['clazz'],
              'day': c['day'], 'slotStart': c['slotStart'], 'slotEnd': c['slotEnd'],
            })
        .toList();
    return {
      'ok': true,
      'zs': zs,
      'courses': courses,
      'dates': dates,
      'xnmc': '2026-2027学年',
      'nj': '2026',
    };
  }

  static const _exams = [
    {'name': '高等数学(下)', 'ksmc': '期末考试', 'date': '2027-01-10', 'start': '08:00', 'end': '09:40', 'place': '二教E101', 'seat': '12', 'ksfs': '笔试'},
    {'name': '数据结构', 'ksmc': '期末考试', 'date': '2027-01-12', 'start': '10:00', 'end': '11:40', 'place': '一教A203', 'seat': '05', 'ksfs': '笔试'},
    {'name': '大学英语(二)', 'ksmc': '期末考试', 'date': '2027-01-14', 'start': '14:00', 'end': '15:40', 'place': '外语楼305', 'seat': '23', 'ksfs': '机考'},
  ];
}
