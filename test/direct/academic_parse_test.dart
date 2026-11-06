import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 学业情况页面解析的纯函数用例（不联网、不起 mock 服务）：
/// 覆盖「正常页 / 属性顺序变 / &nbsp; 占位 / 学校报错 / 登录页 / 无 showKc 占位」
/// 几种页面形态，以及明细 JSON 的两种包法。

const String _indexHtml = '''
<html><body>
<h5>学生学业情况查询</h5>
<form id="form"><input type="hidden" id="xh_id" value="25110001"/></form>
<div id="alertBox">
  平均学分绩点：<font size="2px">3.52</font>&nbsp;
  计划总课程 60 门 通过 52 门 未通过 3 门 未修 4 门 在读 1 门，
  计划外 通过 3 门 未通过 1 门
</div>
<div class="panel"><div class="panel-heading">
  <a data-toggle="collapse">主修</a>
  <span>要求学分：160.0&nbsp;获得学分：83.0&nbsp;未获得学分：77.0</span>
  <span id='showKc9001'></span>
</div></div>
<div class="panel"><div class="panel-heading">
  <a data-toggle="collapse">专业核心课</a>
  <span>要求学分：33.0&nbsp;获得学分：28.0&nbsp;未获得学分：5.0</span>
  <span id='showKc9002'></span>
</div></div>
</body></html>
''';

void main() {
  test('解析正常页：学号、GPA、计划内外统计、类别与学分', () {
    final r = parseAcademicIndex(_indexHtml);
    expect(r['login'], isFalse);
    expect(r['error'], isEmpty);
    expect(r['sid'], '25110001');

    final stats = r['statistics'] as Map<String, dynamic>;
    expect(stats['gpa'], 3.52);
    final planed = stats['planed'] as Map<String, dynamic>;
    expect(planed['total'], 60);
    expect(planed['passed'], 52);
    expect(planed['failed'], 3);
    expect(planed['missed'], 4);
    expect(planed['in'], 1);
    final unplaned = stats['unplaned'] as Map<String, dynamic>;
    expect(unplaned['passed'], 3);
    expect(unplaned['failed'], 1);

    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats.length, 2);
    expect(cats[0]['name'], '主修');
    expect(cats[0]['id'], '9001');
    expect(cats[0]['required'], 160.0);
    expect(cats[0]['earned'], 83.0);
    expect(cats[0]['missed'], 77.0);
    expect(cats[1]['name'], '专业核心课');
    expect(cats[1]['id'], '9002');
    expect(cats[1]['required'], 33.0);
  });

  test('属性顺序颠倒、引号单双混用的页面也能取到学号', () {
    final html = _indexHtml.replaceFirst(
      '<input type="hidden" id="xh_id" value="25110001"/>',
      '<input type="hidden" value="25110001" id="xh_id"/>',
    );
    expect(parseAcademicIndex(html)['sid'], '25110001');

    final quoted = _indexHtml.replaceFirst(
      '<input type="hidden" id="xh_id" value="25110001"/>',
      "<input type='hidden' id='xh_id' value='25110001'/>",
    );
    expect(parseAcademicIndex(quoted)['sid'], '25110001');
  });

  test('学校业务错误（alert-danger）原文透出', () {
    final r = parseAcademicIndex(
      '<html><body><h5>学生学业情况查询</h5>'
      '<div class="alert alert-danger">未配置培养方案，请联系教务处</div>'
      '</body></html>',
    );
    expect(r['error'], '未配置培养方案，请联系教务处');
  });

  test('未登录页（h5 用户登录 / 正方登录页）判 login=true', () {
    expect(
      parseAcademicIndex('<html><body><h5>用户登录</h5></body></html>')['login'],
      isTrue,
    );
    expect(
      parseAcademicIndex(
        '<html><body><form action="/jwglxt/xtgl/login_slogin.html"></form></body></html>',
      )['login'],
      isTrue,
    );
  });

  test('缺 alertBox 时 GPA/统计留 null，不编造 0', () {
    final r = parseAcademicIndex(
      '<html><body><h5>学生学业情况查询</h5>'
      '<input id="xh_id" value="25110001"/></body></html>',
    );
    final stats = r['statistics'] as Map<String, dynamic>;
    expect(stats['gpa'], isNull);
    expect(stats['planed'], isNull);
    expect(stats['unplaned'], isNull);
  });

  test('没有 showKc 占位时退化成按「要求学分」切块', () {
    final r = parseAcademicIndex(
      '<html><body><h5>学生学业情况查询</h5>'
      '<p>专业选修课</p>'
      '<p>要求学分：20.0 获得学分：18.0 未获得学分：2.0</p>'
      '</body></html>',
    );
    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats, hasLength(1));
    expect(cats.first['name'], '专业选修课');
    expect(cats.first['id'], '');
    expect(cats.first['required'], 20.0);
    expect(cats.first['earned'], 18.0);
  });

  test('新版 JS 模板页：解析节点树（父子/层级）、隐藏域与「未获得学分」推算', () {
    // 复刻 SIT 真实页面的模板片段：中文标签只在 /* 注释 */ 里，正文是 JS 字符串拼接。
    const html = '''
<html><body>
<h5>学生学业情况查询</h5>
<input type="hidden" name="xh_id" value="251184Y304" id="xh_id"/>
<input type="hidden" name="cjlrxn" value="2026" id="cjlrxn"/>
<input type="hidden" name="cjlrxq" value="3" id="cjlrxq"/>
<div id="alertBox">平均学分绩点：3.4</div>
<script>
\$("<ul id='ul1'><li id='li1' class='' fxfyqjd_id='' >" +
  "<div class='title' xfyqjd_id='1' jdkcsx='1'><p class='title1' id='pA1B2C3D4E5F60718293A4B5C6D7E8F900' yxxf='52.5' yqzdxf='170' sftg='0'>" +
  "主修&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":170.0&nbsp;" +
  "<span id='showKcA1B2C3D4E5F60718293A4B5C6D7E8F900'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul2'><li id='li2' class='' fxfyqjd_id='A1B2C3D4E5F60718293A4B5C6D7E8F900' >" +
  "<div class='title' xfyqjd_id='2' jdkcsx='4'><p class='title1' id='pB1B2C3D4E5F60718293A4B5C6D7E8F901' yxxf='28.0' yqzdxf='33.0' sftg='0'>" +
  "专业核心课&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":33.0&nbsp;" +
  "<span id='showKcB1B2C3D4E5F60718293A4B5C6D7E8F901'></span></p></div></li></ul>").appendTo("body");
</script>
</body></html>
''';
    final r = parseAcademicIndex(html);
    expect(r['sid'], '251184Y304');
    final params = (r['params'] as Map).cast<String, String>();
    expect(params['xh_id'], '251184Y304');
    expect(params['cjlrxn'], '2026');
    expect(params['cjlrxq'], '3');

    final cats = (r['categories'] as List).cast<Map<String, dynamic>>();
    expect(cats, hasLength(2));
    expect(cats[0]['name'], '主修');
    expect(cats[0]['id'], 'A1B2C3D4E5F60718293A4B5C6D7E8F900');
    expect(cats[0]['level'], 0);
    expect(cats[0]['required'], 170);
    expect(cats[0]['earned'], 52.5);
    expect(cats[0]['missed'], 117.5);
    expect(cats[0]['jdkcsx'], '1');
    expect(cats[1]['name'], '专业核心课');
    expect(cats[1]['parent'], 'A1B2C3D4E5F60718293A4B5C6D7E8F900');
    expect(cats[1]['level'], 1);
    expect(cats[1]['jdkcsx'], '4');
    expect(cats[1]['passed'], isFalse);
  });

  test('明细 JSON：直接数组 / {items:...} 两种包法都能归一', () {
    final rows = [
      {
        'KCH': 'MA1102', 'KCMC': '高等数学(下)', 'XF': '4.0', 'KCXZMC': '必修',
        'KCLBMC': '专业核心课', 'XDZT': '1', 'MAXCJ': '92', 'JD': '4.2',
        'JYXDXNM': '2026', 'JYXDXQMC': '第一学期',
      },
      {
        'KCH': 'AI2201', 'KCMC': '人工智能导论', 'XF': '2.0', 'KCXZMC': '选修',
        'KCLBMC': '专业选修课', 'XDZT': '2', 'MAXCJ': '', 'JD': '',
        'JYXDXNM': '2025', 'JYXDXQMC': '第二学期',
      },
    ];
    final direct = parseAcademicCourses(rows, sid: '25110001');
    expect(direct, hasLength(2));
    expect(direct[0]['name'], '高等数学(下)');
    expect(direct[0]['credit'], '4.0');
    expect(direct[0]['score'], '92');
    expect(direct[0]['point'], '4.2');
    expect(direct[0]['status'], '1');
    expect(direct[0]['term'], '大二上'); // 2025 入学、2026 学年第一学期
    expect(direct[1]['term'], '大一下'); // 2025 入学、2025 学年第二学期
    expect(direct[1]['score'], isEmpty);

    final wrapped = parseAcademicCourses({'items': rows}, sid: '25110001');
    expect(wrapped, hasLength(2));
    expect(parseAcademicCourses(null), isEmpty);
    expect(parseAcademicCourses({'data': const []}), isEmpty);
  });
}
