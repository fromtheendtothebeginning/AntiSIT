import 'direct/course_select.dart';
import 'demo_fixtures.dart';

/// 演示模式假数据：按请求路径路由，响应结构与 campus-api.md 保持一致。
class DemoData {
  DemoData._();

  static double cardBalance = 56.70;
  static double eleBalance = 23.45;
  static const semesterStart = demoSemesterStart; // 周一

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
        return {'ok': true, 'data': demoScore};
      case '/api/campus-open/grades':
        return {'ok': true, 'data': demoGrades(query: query)};
      case '/api/campus-open/academic':
        return {'ok': true, 'data': demoAcademic()};
      case '/api/campus-open/activities':
        return {'ok': true, 'data': {'student_id': '25110001', 'activities': demoActivities()}};
      case '/api/campus-open/activities/signed':
        return {'ok': true, 'activities': demoSignedActivities()};
      case '/api/campus-open/activities/sign':
        return {'ok': true, 'data': {'msg': '签到成功（演示）'}};
      case '/api/campus-open/score/credits':
        return {'ok': true, 'records': demoCredits()};
      case '/api/campus-open/timetable/week':
        return demoWeek((body?['zs'] ?? 1) as int);
      case '/api/campus-open/timetable/exams':
        return {'ok': true, 'exams': demoExams};
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
        // 演示数据按请求的天数裁剪，否则 7/30/90 三个刻度看起来完全一样
        final days = (int.tryParse(query?['days'] ?? '') ?? 90).clamp(1, 365);
        final since = DateTime.now().subtract(Duration(days: days));
        final records = demoEleHistory().where((r) {
          final t = DateTime.tryParse('${r['time']}'.replaceFirst(' ', 'T'));
          return t != null && t.isAfter(since);
        }).toList();
        return {'ok': true, 'records': records};
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
      if (method == 'POST' && path.endsWith('/signup')) {
        return {
          'ok': true,
          'data': {'instance_id': 'demo-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}'},
        };
      }
      final aid = path.split('/')[4];
      final all = demoActivities();
      final a = all.firstWhere((e) => e['id'] == aid, orElse: () => all.first);
      return {
        'ok': true,
        'data': {...a, 'signed': aid == 'a002'}, // a002 演示「已报名」态（学校详情接口的 bm 透传）
      };
    }
    throw StateError('demo 未实现的接口: $path');
  }

  // ── 抢课（演示）──

  /// 选课轮次（演示）。
  static List<CourseScope> courseScopes() => const [
        CourseScope(
          id: 'demo-scope-1',
          name: '第二轮选课',
          term: '2026-2027-1',
          params: {'xkkz_id': 'demo-xkkz-1', 'xkkz_xh': '1'},
        ),
        CourseScope(
          id: 'demo-scope-2',
          name: '补选 / 退选',
          term: '2026-2027-1',
          params: {'xkkz_id': 'demo-xkkz-2', 'xkkz_xh': '1'},
        ),
      ];

  /// 演示用可选课程：名称 / 教师 / 时间 / 地点 / 学分 / 容量。
  static const List<Map<String, Object>> _demoOffers = [
    {
      'id': 'o-python',
      'name': 'Python 数据分析',
      'teacher': '李明',
      'time': '周三 第 5-6 节',
      'location': '实验楼 402',
      'credit': '2.0',
      'capacity': 60,
      'selected': 41,
    },
    {
      'id': 'o-ai',
      'name': '人工智能导论',
      'teacher': '王芳',
      'time': '周四 第 3-4 节',
      'location': '二教 E201',
      'credit': '2.0',
      'capacity': 50,
      'selected': 50,
    },
    {
      'id': 'o-web',
      'name': 'Web 前端开发',
      'teacher': '张伟',
      'time': '周二 第 7-8 节',
      'location': '实验楼 506',
      'credit': '1.5',
      'capacity': 45,
      'selected': 12,
    },
    {
      'id': 'o-robot',
      'name': '机器人创新实践',
      'teacher': '陈强',
      'time': '周五 第 5-6 节',
      'location': '工程训练中心',
      'credit': '2.0',
      'capacity': 30,
      'selected': 27,
    },
    {
      'id': 'o-music',
      'name': '音乐鉴赏',
      'teacher': '刘敏',
      'time': '周一 第 9-10 节',
      'location': '艺术楼 201',
      'credit': '1.0',
      'capacity': 80,
      'selected': 63,
    },
  ];

  static int _offerCap(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

  /// 可选课程列表（演示）：按轮次 / 关键词过滤，支持分页。
  static List<CourseOffer> courseOffers(
    CourseScope scope, {
    String keyword = '',
    int start = 0,
    int pageSize = 50,
  }) {
    final kw = keyword.trim().toLowerCase();
    final all = [
      for (final o in _demoOffers)
        CourseOffer(
          id: '${o['id']}',
          name: '${o['name']}',
          teacher: '${o['teacher']}',
          time: '${o['time']}',
          location: '${o['location']}',
          credit: '${o['credit']}',
          capacity: _offerCap(o['capacity']),
          selected: _offerCap(o['selected']),
          scopeId: scope.id,
          raw: {'kch_id': '${o['id']}', 'kcmc': '${o['name']}'},
        ),
    ].where((o) {
      if (kw.isEmpty) return true;
      return o.name.toLowerCase().contains(kw) ||
          o.teacher.toLowerCase().contains(kw) ||
          o.location.toLowerCase().contains(kw);
    }).toList();
    if (start >= all.length) return const [];
    final end = (start + pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  /// 某门课的教学班（演示）：每门给两个班，方便看展开效果。
  static List<CourseSection> courseSections(CourseOffer offer) {
    final cap = offer.capacity ?? 50;
    final sel = offer.selected ?? 0;
    return [
      CourseSection(
        id: '${offer.id}-s1',
        courseId: offer.id,
        name: '${offer.name} 01 班',
        teacher: offer.teacher,
        time: offer.time,
        location: offer.location,
        capacity: cap,
        selected: sel,
        raw: {'jxb_id': '${offer.id}-s1', 'do_jxb_id': '${offer.id}-s1'},
      ),
      CourseSection(
        id: '${offer.id}-s2',
        courseId: offer.id,
        name: '${offer.name} 02 班',
        teacher: offer.teacher.isEmpty ? '待定' : '${offer.teacher}等',
        time: '${offer.time}（另一时段）',
        location: '${offer.location}（分班）',
        capacity: cap,
        selected: (sel - 6).clamp(0, cap),
        raw: {'jxb_id': '${offer.id}-s2', 'do_jxb_id': '${offer.id}-s2'},
      ),
    ];
  }

  /// 演示模式下「已选课程」（先放一门，方便看列表不是空的）。
  static final Map<String, SelectedCourse> _demoSelected = {
    'o-music|o-music-s1': const SelectedCourse(
      id: 'sel-o-music',
      name: '音乐鉴赏',
      teacher: '刘敏',
      courseId: 'o-music',
      sectionId: 'o-music-s1',
    ),
  };

  /// 提交选课（演示）：满员 / 已选走对应状态，其余一律成功并记进「已选」。
  static CourseSelectResult selectCourse(
      CourseOffer offer, CourseSection section) {
    final key = '${offer.id}|${section.id}';
    if (_demoSelected.containsKey(key)) {
      return const CourseSelectResult(
          CourseSelectStatus.alreadySelected, '这门课已经选过了（演示）');
    }
    if (section.isFull) {
      return const CourseSelectResult(CourseSelectStatus.noCapacity, '教学班名额已满（演示）');
    }
    _demoSelected[key] = SelectedCourse(
      id: 'sel-${section.id}',
      name: offer.name,
      teacher: section.teacher,
      courseId: offer.id,
      sectionId: section.id,
    );
    return CourseSelectResult(
        CourseSelectStatus.success, '选课成功：${offer.name}（演示）');
  }

  /// 已选课程列表（演示）。
  static List<SelectedCourse> selectedCourses(CourseScope scope) =>
      _demoSelected.values.toList();
}
