part of 'mock_campus_server.dart';

// 本地模拟服务的内置样例数据（成绩 / 课表 / 考试 / 学业情况 / 二课）。

const int _mockWeekCount = 20;
final DateTime _semesterStart = DateTime(2026, 9, 7); // 第 1 周周一

// 寝室：24 号楼 1016（接口约定 buildid = 楼号 + 1）
const int _dormBuilding = 24;
const int _dormRoom = 1016;
const String _draftDormName = '24号楼1016';

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

List<Map<String, String>> _weekDates(int zs) {
  final monday = _semesterStart.add(Duration(days: (zs - 1) * 7));
  return [
    for (var i = 0; i < 7; i++)
      {'xqj': '${i + 1}', 'rq': _fmtDate(monday.add(Duration(days: i)))},
  ];
}

const List<Map<String, Object>> _courses = [
  {'name': '高等数学(下)', 'place': '二教E101', 'teacher': '王建国', 'code': 'MA1102',
    'clazz': '数学2501-01', 'day': 0, 'slots': '1-2', 'from': 1, 'to': 17},
  {'name': '大学英语(二)', 'place': '外教楼305', 'teacher': '李梅', 'code': 'EN1102',
    'clazz': '英语2503-02', 'day': 0, 'slots': '3', 'from': 1, 'to': 17},
  {'name': '数据结构', 'place': '一教A203', 'teacher': '陈强', 'code': 'CS2101',
    'clazz': '计科2501-01', 'day': 1, 'slots': '1-2', 'from': 1, 'to': 16},
  {'name': '数据结构实验', 'place': '实验楼506', 'teacher': '陈强', 'code': 'CS2102',
    'clazz': '计科2501-02', 'day': 3, 'slots': '4-5', 'from': 2, 'to': 16},
  {'name': '大学物理(二)', 'place': '二教B110', 'teacher': '赵芳', 'code': 'PH1201',
    'clazz': '物理2502-01', 'day': 2, 'slots': '3', 'from': 1, 'to': 17},
  {'name': '思想道德与法治', 'place': '一教C108', 'teacher': '孙丽', 'code': 'PY1101',
    'clazz': '思政2501-05', 'day': 4, 'slots': '1-2', 'from': 1, 'to': 15},
  {'name': '大学体育(二)', 'place': '体育馆', 'teacher': '周斌', 'code': 'PE1102',
    'clazz': '体育 Club-08', 'day': 4, 'slots': '4', 'from': 1, 'to': 16},
  {'name': '线性代数', 'place': '二教E201', 'teacher': '吴敏', 'code': 'MA1201',
    'clazz': '数学2502-03', 'day': 2, 'slots': '4-5', 'from': 1, 'to': 17},
  {'name': '程序设计实践', 'place': '实验楼402', 'teacher': '郑浩', 'code': 'CS1105',
    'clazz': '计科2501-01', 'day': 1, 'slots': '4-5', 'from': 3, 'to': 14},
];

const List<Map<String, String>> _exams = [
  {'kcmc': '高等数学(下)', 'ksmc': '期末考试', 'kssj': '2027-01-10(08:00-09:40)',
    'cdmc': '二教E101', 'zwh': '12', 'ksfs': '笔试'},
  {'kcmc': '数据结构', 'ksmc': '期末考试', 'kssj': '2027-01-12(10:00-11:40)',
    'cdmc': '一教A203', 'zwh': '05', 'ksfs': '笔试'},
  {'kcmc': '大学英语(二)', 'ksmc': '期末考试', 'kssj': '2027-01-14(14:00-15:40)',
    'cdmc': '外语楼305', 'zwh': '23', 'ksfs': '机考'},
];

Map<String, Object?> _grade(String kcmc, String cj, String xf, String lb, String fs,
        {String xnm = '2026',
        String xqm = '3',
        String xnmmc = '2026-2027学年',
        String xqmmc = '第一学期'}) =>
    {
      'kcmc': kcmc, 'cj': cj, 'xf': xf, 'jd': '', 'xfjd': '',
      'kclbmc': lb, 'kcxzmc': '主修', 'khfsmc': fs,
      'xqmmc': xqmmc, 'xnmmc': xnmmc, 'sfxwkc': '否', 'xnm': xnm, 'xqm': xqm,
    };

/// 两个学期的成绩：xnm/xqm 传空时返回全部，客户端据此生成学期列表。
final List<Map<String, Object?>> _grades = [
  _grade('高等数学(上)', '92', '4.0', '必修', '考试'),
  _grade('大学英语(一)', '88', '3.0', '必修', '考试'),
  _grade('程序设计基础', '95', '4.0', '必修', '考试'),
  _grade('思想道德与法治', '90', '2.5', '必修', '考查'),
  _grade('线性代数', '85', '2.0', '必修', '考试',
      xnm: '2025', xqm: '3', xnmmc: '2025-2026学年'),
  _grade('中国近现代史纲要', '92', '2.0', '必修', '考查',
      xnm: '2025', xqm: '3', xnmmc: '2025-2026学年'),
];

/// 学业情况首页 HTML：复刻真实页面的隐藏域、整体统计与写在 JS 模板里的 5 层节点树，
/// 明细接口选择靠节点属性 `jdkcsx`（'1' = 教学计划；其它 = 非课程信息）。
const String _academicIndexPage = '''
<html><body>
<h5>学生学业情况查询</h5>
<input type="hidden" name="xh_id" value="25110001" id="xh_id"/>
<input type="hidden" name="cjlrxn" value="2026" id="cjlrxn"/>
<input type="hidden" name="cjlrxq" value="3" id="cjlrxq"/>
<input type="hidden" name="bkcjlrxn" value="2026" id="bkcjlrxn"/>
<input type="hidden" name="bkcjlrxq" value="3" id="bkcjlrxq"/>
<input type="hidden" name="xscjcxkz" value="0" id="xscjcxkz"/>
<input type="hidden" name="cjcxkzzt" value="1" id="cjcxkzzt"/>
<input type="hidden" name="cjztkz" value="0" id="cjztkz"/>
<input type="hidden" name="cjzt" value="" id="cjzt"/>
<div id="alertBox">
  平均学分绩点：<font size="2px">3.52</font>&nbsp;
  计划总课程 60 门 通过 52 门 未通过 3 门 未修 4 门 在读 1 门，
  计划外 通过 3 门 未通过 1 门
</div>
<script>
\$("<ul id='ul1000'><li id='li1000' class='' fxfyqjd_id='' >" +
  "<div class='title' xfyqjd_id='1000' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1000' yxxf='52.5' yqzdxf='170' sftg='0'>" +
  "主修&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":170.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":52.5&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":117.5&nbsp;" +
  "<span id='showKc1000'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1100'><li id='li1100' class='' fxfyqjd_id='1000' >" +
  "<div class='title' xfyqjd_id='1100' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1100' yxxf='4.0' yqzdxf='8' sftg='0'>" +
  "通识课&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":8.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":4.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":4.0&nbsp;" +
  "<span id='showKc1100'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1110'><li id='li1110' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1110' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1110' yxxf='0.0' yqzdxf='0' sftg='1'>" +
  "人文精神与明德修养&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":0.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":0.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1110'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1111'><li id='li1111' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1111' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1111' yxxf='0.0' yqzdxf='2' sftg='0'>" +
  "科学精神与技术创新&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":2.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":0.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":2.0&nbsp;" +
  "<span id='showKc1111'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1112'><li id='li1112' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1112' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1112' yxxf='2.0' yqzdxf='2' sftg='1'>" +
  "企业文化与职业素养&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":2.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":2.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1112'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1113'><li id='li1113' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1113' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1113' yxxf='2.0' yqzdxf='2' sftg='1'>" +
  "公共艺术类课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":2.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":2.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1113'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1200'><li id='li1200' class='' fxfyqjd_id='1000' >" +
  "<div class='title' xfyqjd_id='1200' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1200' yxxf='33.5' yqzdxf='54' sftg='0'>" +
  "公共基础课&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":54.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":33.5&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":20.5&nbsp;" +
  "<span id='showKc1200'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1210'><li id='li1210' class='' fxfyqjd_id='1200' >" +
  "<div class='title' xfyqjd_id='1210' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1210' yxxf='13.5' yqzdxf='17.5' sftg='0'>" +
  "数理课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":17.5&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":13.5&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":4.0&nbsp;" +
  "<span id='showKc1210'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1211'><li id='li1211' class='' fxfyqjd_id='1210' >" +
  "<div class='title' xfyqjd_id='1211' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1211' yxxf='10.0' yqzdxf='10' sftg='1'>" +
  "高等数学&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":10.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":10.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1211'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1212'><li id='li1212' class='' fxfyqjd_id='1211' >" +
  "<div class='title' xfyqjd_id='1212' jdkcsx='1' leaf='' sfmjd='1' ><p class='title1' id='p1212' yxxf='10.0' yqzdxf='10' sftg='1'>" +
  "工科&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":10.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":10.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1212'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1220'><li id='li1220' class='' fxfyqjd_id='1200' >" +
  "<div class='title' xfyqjd_id='1220' jdkcsx='1' leaf='' sfmjd='1' ><p class='title1' id='p1220' yxxf='11.0' yqzdxf='18' sftg='0'>" +
  "思政课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":18.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":11.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":7.0&nbsp;" +
  "<span id='showKc1220'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul2000'><li id='li2000' class='' fxfyqjd_id='' >" +
  "<div class='title' xfyqjd_id='2000' jdkcsx='1' leaf='' sfmjd='1' ><p class='title1' id='p2000' yxxf='2.0' yqzdxf='' sftg='1'>" +
  "其他课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":2.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":&nbsp;" +
  "<span id='showKc2000'></span></p></div></li></ul>").appendTo("body");
</script>
</body></html>
''';

/// 老版/静态方言的页面（节点直接渲染成 HTML，没有 JS 模板）：
/// 用于回归「其它学校/旧版正方」的解析回退。
const String _academicStaticPage = '''
<html><body>
<h5>学生学业情况查询</h5>
<form id="form"><input type="hidden" id="xh_id" value="25110001"/></form>
<div id="alertBox">
  平均学分绩点：<font size="2px">3.52</font>&nbsp;
  计划总课程 60 门 通过 52 门 未通过 3 门 未修 4 门 在读 1 门，
  计划外 通过 3 门 未通过 1 门
</div>
<div class="panel"><div class="panel-heading">
  <a data-toggle="collapse">专业核心课</a>
  <span>要求学分：33.0&nbsp;获得学分：28.0&nbsp;未获得学分：5.0</span>
  <span id='showKc9002'></span>
</div></div>
</body></html>
''';

/// 学业情况节点课程明细（真实接口是大写字段，按 xfyqjd_id 分组）。
/// 只放「教学计划课程」节点（jdkcsx='1'）；非课程节点见 [_academicNonCourses]。
const Map<String, List<Map<String, Object?>>> _academicCourses = {
  // 深层叶子：主修 → 公共基础课 → 数理课程 → 高等数学 → 工科（5 层）
  '1212': [
    {'KCH': 'MA1201', 'KCMC': '高等数学（工）2', 'XF': '4.0', 'KCXZMC': '必修',
      'KCLBMC': '数理课程', 'XDZT': '4', 'MAXCJ': '92', 'JD': '4.2',
      'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
    {'KCH': 'MA1305', 'KCMC': '线性代数', 'XF': '2.0', 'KCXZMC': '必修',
      'KCLBMC': '数理课程', 'XDZT': '4', 'MAXCJ': '85', 'JD': '3.5',
      'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
    // 在修（XDZT=1）：用于回归「在修」黄色标签
    {'KCH': 'MA1306', 'KCMC': '概率论与数理统计', 'XF': '3.0', 'KCXZMC': '必修',
      'KCLBMC': '数理课程', 'XDZT': '1', 'MAXCJ': '', 'JD': '',
      'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
  ],
  '1220': [
    {'KCH': 'B1280001', 'KCMC': '形势与政策（1）', 'XF': '0.5', 'KCXZMC': '必修',
      'KCLBMC': '公共基础课', 'XDZT': '4', 'MAXCJ': '97', 'JD': '4.7',
      'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
    {'KCH': 'B1280003', 'KCMC': '中国近现代史纲要', 'XF': '3.0', 'KCXZMC': '必修',
      'KCLBMC': '公共基础课', 'XDZT': '4', 'MAXCJ': '89', 'JD': '3.9',
      'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
    // 未修（XDZT=3）：用于回归「未修」红色标签
    {'KCH': 'B1280005', 'KCMC': '思想道德与法治', 'XF': '3.0', 'KCXZMC': '必修',
      'KCLBMC': '公共基础课', 'XDZT': '3', 'MAXCJ': '', 'JD': '',
      'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
  ],
  // 根节点直接挂课程（其他课程）
  '2000': [
    {'KCH': 'AI2201', 'KCMC': '人工智能导论', 'XF': '2.0', 'KCXZMC': '选修',
      'KCLBMC': '其他课程', 'XDZT': '4', 'MAXCJ': '88', 'JD': '3.3',
      'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
    {'KCH': 'CS2301', 'KCMC': 'Python 编程实训', 'XF': '1.0', 'KCXZMC': '实践',
      'KCLBMC': '其他课程', 'XDZT': '4', 'MAXCJ': '95', 'JD': '4.5',
      'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
  ],
  // 老版静态页面回归用例用（debugAcademicStaticPage 里的 showKc9002）
  '9002': [
    {'KCH': 'MA1102', 'KCMC': '高等数学(下)', 'XF': '4.0', 'KCXZMC': '必修',
      'KCLBMC': '专业核心课', 'XDZT': '1', 'MAXCJ': '92', 'JD': '4.2',
      'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
    {'KCH': 'CS2101', 'KCMC': '数据结构', 'XF': '3.5', 'KCXZMC': '必修',
      'KCLBMC': '专业核心课', 'XDZT': '1', 'MAXCJ': '88', 'JD': '3.3',
      'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
  ],
};

/// 「非课程信息」节点明细（jdkcsx != '1'）：通识课下的叶子节点走这个接口，
/// 这正是「通识课有学分但 App 显示 0 门」的那个缺口。
const Map<String, List<Map<String, Object?>>> _academicNonCourses = {
  '1112': [
    {'KCH': 'GE1101', 'KCMC': '企业文化与职业素养（慕课）', 'XF': '2.0',
      'KCXZMC': '选修', 'KCLBMC': '通识课', 'XDZT': '4', 'MAXCJ': '85',
      'JD': '3.5', 'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
  ],
  '1113': [
    {'KCH': 'GE1102', 'KCMC': '艺术鉴赏', 'XF': '2.0', 'KCXZMC': '选修',
      'KCLBMC': '通识课', 'XDZT': '4', 'MAXCJ': '90', 'JD': '4.0',
      'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
  ],
  '1110': [],
  '1111': [],
};

const List<Map<String, String>> _scoreHeader = [
  {'fieldCode': 'xh', 'fieldName': '学号', 'fieldTh': '基本信息'},
  {'fieldCode': 'xm', 'fieldName': '姓名', 'fieldTh': '基本信息'},
  {'fieldCode': 'nj', 'fieldName': '年级', 'fieldTh': '基本信息'},
  {'fieldCode': 'bmmc', 'fieldName': '院系', 'fieldTh': '基本信息'},
  {'fieldCode': 'zymc', 'fieldName': '专业', 'fieldTh': '基本信息'},
  {'fieldCode': 'bjmc', 'fieldName': '班级', 'fieldTh': '基本信息'},
  {'fieldCode': 'zxs', 'fieldName': '总学时', 'fieldTh': '统计'},
  {'fieldCode': 'sjxf', 'fieldName': '实践学分', 'fieldTh': '统计'},
  {'fieldCode': 'dlxs_dy', 'fieldName': '德育小计', 'fieldTh': '德育'},
  {'fieldCode': 'rdxs_dy_jzbg', 'fieldName': '讲座报告', 'fieldTh': '德育'},
  {'fieldCode': 'rdxs_dy_ztjy', 'fieldName': '主题教育', 'fieldTh': '德育'},
  {'fieldCode': 'rdxs_dy_zygy', 'fieldName': '志愿公益', 'fieldTh': '德育'},
  {'fieldCode': 'dlxs_ly', 'fieldName': '劳育小计', 'fieldTh': '劳育'},
  {'fieldCode': 'rdxs_ly_ldkt', 'fieldName': '劳动课堂', 'fieldTh': '劳育'},
  {'fieldCode': 'rdxs_ly_shsj', 'fieldName': '社会实践', 'fieldTh': '劳育'},
  {'fieldCode': 'dlxs_my', 'fieldName': '美育小计', 'fieldTh': '美育'},
  {'fieldCode': 'dlxs_jkjy', 'fieldName': '健康教育小计', 'fieldTh': '健康教育'},
];

const Map<String, Object?> _scoreItem = {
  'xh': MockCampusServer.studentId,
  'xm': MockCampusServer.realName,
  'nj': MockCampusServer.grade,
  'bmmc': '计算机学院', 'zymc': '计算机科学与技术', 'bjmc': '计科2501',
  'zxs': '8.0', 'sjxf': '5.5',
  'dlxs_dy': '2.0', 'rdxs_dy_jzbg': '0.8', 'rdxs_dy_ztjy': '0.4', 'rdxs_dy_zygy': '0.8',
  'dlxs_ly': '1.5', 'rdxs_ly_ldkt': '0.5', 'rdxs_ly_shsj': '1.0',
  'dlxs_my': '0.5', 'dlxs_jkjy': '0.5',
};

const Map<String, Map<String, Object?>> _activityItems = {
  'm001': {
    'id': 'm001',
    'hdmc': 'AI 赋能学习效率提升讲座',
    'zbfmc': '校学生会',
    'hdbmkssj': '2026-09-25 10:00:00',
    'hdbmjzsj': '2026-10-08 22:00:00',
    'hdkssj': '2026-10-10 14:00:00',
    'hdjssj': '2026-10-10 16:00:00',
    'hdms': '邀请企业 AI 工程师分享大模型在学习场景的实践应用，参与可获思想成长模块 0.2 分。\n'
        '人数：200 人\n报名请加 QQ 群 765432198，联系人：李同学 13800000000',
  },
  'm002': {
    'id': 'm002',
    'hdmc': '秋季校园马拉松志愿者',
    'zbfmc': '校团委',
    'hdbmkssj': '2026-10-05 12:00:00',
    'hdbmjzsj': '2026-10-12 18:00:00',
    'hdkssj': '2026-10-18 07:00:00',
    'hdjssj': '2026-10-18 13:00:00',
    'hdms': '负责奉贤赛道补给站物资发放与观众引导，计社会实践 0.5 分。\n'
        '名额：80 人\n报名方式：扫码填写问卷，联系人：王老师',
  },
  'm003': {
    'id': 'm003',
    'hdmc': '实验室开放日参观',
    'zbfmc': '计算机学院',
    'hdbmkssj': '2026-09-01 09:00:00',
    'hdbmjzsj': '2026-09-02 17:00:00',
    'hdkssj': '2026-09-20 13:30:00',
    'hdjssj': '2026-09-20 17:00:00',
    'hdms': '参观徐汇人工智能实验室与机器人实验室，了解本科生科研训练项目报名方式。',
  },
};
