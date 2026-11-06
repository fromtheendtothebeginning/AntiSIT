import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 正方 9.0 选课协议解析/参数拼装的纯函数用例（不联网）。
void main() {
  group('首页隐藏域与选课类别', () {
    const html = '''
<html><body>
<input type="hidden" name="xkxnm" value="2026">
<input type="hidden" name="xkxqm" value="12">
<input type="hidden" name="kklxdm" value="1">
<input type="hidden" name="firstXkkzId" value="FIRSTID">
<input type="hidden" name="firstXkkzXh" value="FIRSTXH">
<script>
  queryCourse('1', 'XKKZ1', '2025', 'ZY1', 'XH1');
  queryCourse('2', 'XKKZ2', '2025', 'ZY1');
  queryCourse('1', 'XKKZ1', '2025', 'ZY1', 'XH1');
</script>
</body></html>
''';

    test('隐藏域解析：属性顺序/单双引号都不敏感', () {
      final hidden = parseZfHiddenFields(html);
      expect(hidden['xkxnm'], '2026');
      expect(hidden['firstXkkzId'], 'FIRSTID');
    });

    test('queryCourse 解析出类别与两个独立控制值，重复项去掉', () {
      final hidden = parseZfHiddenFields(html);
      final cats = parseZfCourseCategories(html, hidden);
      expect(cats, hasLength(2));
      expect(cats[0].category, '1');
      expect(cats[0].control.id, 'XKKZ1');
      expect(cats[0].control.xh, 'XH1');
      expect(cats[0].grade, '2025');
      expect(cats[0].major, 'ZY1');
      expect(cats[1].category, '2');
      expect(cats[1].control.id, 'XKKZ2');
      expect(cats[1].control.xh, isEmpty);
    });

    test('没有 queryCourse 时退回隐藏域里的默认类别', () {
      final hidden = parseZfHiddenFields(
        '<input type="hidden" name="firstKklxdm" value="3">'
        '<input type="hidden" name="firstXkkzId" value="ID3">'
        '<input type="hidden" name="firstNjdmId" value="2025">'
        '<input type="hidden" name="firstZyhId" value="ZY3">'
        '<input type="hidden" name="firstKklxmc" value="通识课">',
      );
      final cats = parseZfCourseCategories('', hidden);
      expect(cats, hasLength(1));
      expect(cats.first.category, '3');
      expect(cats.first.control.id, 'ID3');
      expect(cats.first.name, '通识课');
    });

    test('类别合并展示页隐藏域：控制值补齐，冲突时保留首页原值', () {
      final cat = ZfCourseCategory(
        category: '1',
        control: const ZfSelectionControl(id: 'ID1', xh: 'XH1'),
        grade: '2025',
        major: 'ZY1',
        name: '主修',
      );
      final params = cat.merge(
        {'xkxnm': '2026', 'xkkz_id': 'OLD', 'firstXkkzId': 'ID1'},
        {'xkkz_id': 'ID1', 'xkkz_xh': 'XH1', 'kklxmc': '主修'},
      );
      expect(params['xkkz_id'], 'ID1');
      expect(params['xkkz_xh'], 'XH1');
      expect(params['kklxdm'], '1');
      expect(params['njdm_id'], '2025');
      expect(params['zyh_id'], 'ZY1');
      expect(params['xkxnm'], '2026');
      expect(params.containsKey('firstXkkzId'), isFalse);
    });
  });

  group('课程 / 教学班 / 已选列表', () {
    test('课程列表兼容 tmpList 包法，带名额与余量', () {
      final list = parseZfCourseOffers(
        {
          'tmpList': [
            {
              'kch_id': 'K001', 'kcmc': '高等数学', 'jsxm': '王老师', 'sksj': '周一 1-2 节',
              'jxdd': '二教 A101', 'xf': '4.0', 'jxbrl': '60', 'yxzrs': '60',
            },
            {'kch': 'K002', 'kcmc': '大学英语', 'jxbrl': 40, 'yxrs': 12},
          ],
        },
        scopeId: 'zf-0-1',
        scopeParams: {'kklxdm': '1', 'xkxnm': '2026'},
      );
      expect(list, hasLength(2));
      expect(list[0].id, 'K001');
      expect(list[0].name, '高等数学');
      expect(list[0].capacity, 60);
      expect(list[0].selected, 60);
      expect(list[0].isFull, isTrue);
      expect(list[0].remaining, 0);
      expect(list[0].raw['kklxdm'], '1');
      expect(list[1].selected, 12);
      expect(list[1].isFull, isFalse);
    });

    test('教学班列表：do_jxb_id 作为选课令牌，与 jxb_id 区分', () {
      final course = const CourseOffer(
        id: 'K001', name: '高等数学', teacher: '', time: '', location: '',
        credit: '', capacity: 60, selected: 60, scopeId: 'zf-0-1', raw: {},
      );
      final sections = parseZfCourseSections({
        'tmpList': [
          {
            'jxb_id': 'JXB1', 'do_jxb_id': 'TOKEN1', 'jxbmc': '01 班',
            'jsxm': '王老师', 'sksj': '周一 1-2 节', 'jxdd': '二教 A101',
            'jxbrl': '60', 'yxzrs': '59',
          },
        ],
      }, course);
      expect(sections, hasLength(1));
      expect(sections.first.id, 'JXB1');
      expect(sections.first.selectionId, 'TOKEN1');
      expect(sections.first.remaining, 1);
    });

    test('已选课程解析', () {
      final list = parseZfSelectedCourses({
        'tmpList': [
          {'jxb_id': 'JXB1', 'kch_id': 'K001', 'kcmc': '高等数学', 'jsxm': '王老师'},
        ],
      });
      expect(list, hasLength(1));
      expect(list.first.name, '高等数学');
      expect(list.first.courseId, 'K001');
      expect(list.first.sectionId, 'JXB1');
    });
  });

  group('请求参数', () {
    test('课程列表：偏移量从 1 开始，保留筛选词与控制值', () {
      final params = buildZfCourseListParams(
        {
          'xkxnm': '2026', 'xkxqm': '12', 'kklxdm': '1',
          'xkkz_id': 'ID1', 'xkkz_xh': 'XH1', 'jg_id_1': 'JG1',
          'unrelated': 'x',
        },
        keyword: '数学',
        start: 50,
        pageSize: 50,
      );
      expect(params['kspage'], '51');
      expect(params['jspage'], '100');
      expect(params['filter_list[0]'], '数学');
      expect(params['xkkz_id'], 'ID1');
      expect(params['xkkz_xh'], 'XH1');
      expect(params['jg_id'], 'JG1');
      expect(params.containsKey('unrelated'), isFalse);
    });

    test('教学班/选课参数只带控制字段与目标课程', () {
      final offer = const CourseOffer(
        id: 'K001', name: '高等数学', teacher: '', time: '', location: '',
        credit: '', capacity: null, selected: null, scopeId: 's',
        raw: {'kklxdm': '1', 'xkkz_id': 'ID1', 'xkxnm': '2026', 'xkxqm': '12'},
      );
      final section = const CourseSection(
        id: 'JXB1', courseId: 'K001', name: '01 班', teacher: '', time: '',
        location: '', capacity: null, selected: null,
        raw: {'jxb_id': 'JXB1', 'do_jxb_id': 'TOKEN1'},
      );
      final sectionParams = buildZfSectionParams(offer);
      expect(sectionParams['kch_id'], 'K001');
      expect(sectionParams['xkkz_id'], 'ID1');
      expect(sectionParams.containsKey('xkkz_xh'), isFalse);

      final selectParams = buildZfSelectParams(offer, section);
      expect(selectParams['jxb_ids'], 'TOKEN1');
      expect(selectParams['kch_id'], 'K001');
      expect(selectParams['kcmc'], '高等数学');
      expect(selectParams['kklxdm'], '1');
    });
  });

  group('选课响应', () {
    test('正方返回 1 = 成功', () {
      final r = parseZfSelectResponse('1', 200);
      expect(r.status, CourseSelectStatus.success);
      expect(r.ok, isTrue);
    });

    test('flag -1 + 人数/令牌/余量格式 = 名额已满', () {
      final r = parseZfSelectResponse('{"flag":"-1","msg":"60,abc123,0,"}', 200);
      expect(r.status, CourseSelectStatus.noCapacity);
      expect(r.ok, isFalse);
    });

    test('常见业务错误分类', () {
      expect(parseZfSelectResponse('{"flag":"0","msg":"已经选过该课程"}', 200).status,
          CourseSelectStatus.alreadySelected);
      expect(parseZfSelectResponse('{"flag":"-1","msg":"上课时间冲突"}', 200).status,
          CourseSelectStatus.conflict);
      expect(parseZfSelectResponse('{"flag":"-1","msg":"当前不属于选课阶段"}', 200).status,
          CourseSelectStatus.roundClosed);
      expect(parseZfSelectResponse('{"flag":"-1","msg":"超过学分上限"}', 200).status,
          CourseSelectStatus.creditLimit);
      expect(parseZfSelectResponse('{"flag":"-1","msg":"名额不足"}', 200).status,
          CourseSelectStatus.noCapacity);
    });

    test('登录页 / 401 = 会话失效', () {
      expect(parseZfSelectResponse('<html>login_slogin</html>', 200).status,
          CourseSelectStatus.sessionExpired);
      expect(parseZfSelectResponse('', 401).status, CourseSelectStatus.sessionExpired);
    });

    test('HTML 错误页取原文，不再当成成功', () {
      final r = parseZfSelectResponse(
          '<div class="error_text">该教学班已满，请选择其他教学班</div>', 200);
      expect(r.status, CourseSelectStatus.noCapacity);
      expect(r.message, contains('已满'));
    });
  });
}
