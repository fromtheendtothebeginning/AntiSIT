import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评教的协议层：解析评分表单、拼提交参数、列表解析、代理解析。
/// 真机连教务要校园代理 + 账号，这里钉住「页面/JSON 给了什么 → App 怎么理解」。
String _fixture() => File('test/fixtures/eval_display_theory.html').readAsStringSync();

void main() {
  group('评分表单解析', () {
    test('理论类模板：身份字段、模板、一级/二级指标与权重', () {
      final form = EvalForm.tryParse(_fixture());
      expect(form, isNotNull);
      // 提交要用表单里的 jgh_id，而不是列表里那个 256 位串
      expect(form!.jghId, 'FORM_JGH_ID_001');
      expect(form.jxbId, '55982D546A5F463EE065E2219BB20201');
      expect(form.kchId, 'S1230125');
      expect(form.xsdm, '01');
      expect(form.ztpjbl, '100');
      expect(form.commentMax, 500);

      expect(form.models, hasLength(1));
      final model = form.models.single;
      expect(model.id, 'MODEL_ID_001');
      expect(model.groups, hasLength(2));
      expect(model.groups.first.title, '一、目标明确度');
      expect(model.groups.first.weight, closeTo(0.4, 1e-9));
      expect(model.groups.first.items, hasLength(2));
      expect(form.count, 3);
      expect(form.requiredCount, 3);
    });

    test('题干去掉必填星号、题号与「（100分）」', () {
      final form = EvalForm.tryParse(_fixture())!;
      final first = form.items.first;
      expect(first.text, startsWith('通过教师的授课'));
      expect(first.text, isNot(contains('*')));
      expect(first.text, isNot(contains('100分')));
      expect(first.min, 0);
      expect(first.max, 100);
      expect(first.gradeCodeId, 'GRADE_CODE');
      expect(first.templateCodeId, 'TPL_CODE');
      expect(first.required, isTrue);
    });

    test('加权总分按一级权重 × 二级权重 × 分数算', () {
      final form = EvalForm.tryParse(_fixture())!;
      final scores = {
        'ITEM_A1': 100.0,
        'ITEM_A2': 80.0,
        'ITEM_B1': 90.0,
      };
      // 0.4*(1*100 + .6*80) + 0.6*(1*90) = 0.4*148 + 54 = 113.2
      expect(form.total(scores), closeTo(113.2, 1e-6));
    });

    test('已保存过的条目：页面回填的分数被读出来，打开时直接显示上次的分', () {
      final form = EvalForm.tryParse(_fixture())!;
      final saved = form.savedScores;
      expect(saved['ITEM_A1'], 88, reason: 'value="88" 应该被读出来');
      expect(saved.containsKey('ITEM_A2'), isFalse, reason: '没保存过的题不应凭空有分');
      final init = form.initialScores(fallback: 95);
      expect(init['ITEM_A1'], 88);
      expect(init['ITEM_A2'], 95, reason: '没存过的用兜底满分档');
    });

    test('全部题都有已保存分时，初始分数就是上次那套', () {
      var html = _fixture();
      html = html.replaceAll('value=""', 'value="70"');
      html = html.replaceAll('value="88"', 'value="70"');
      final form = EvalForm.tryParse(html)!;
      expect(form.savedScores.length, form.count);
      expect(form.initialScores().values.every((v) => v == 70), isTrue);
    });

    test('不是评分页（没有 xspj-body）时返回 null', () {
      expect(EvalForm.tryParse('<html><body>无功能权限</body></html>'), isNull);
    });

    test('指标分值范围照页面读，不写死 0-100', () {
      final html = _fixture().replaceAll('data-zdfz="100"', 'data-zdfz="20"');
      final form = EvalForm.tryParse(html)!;
      expect(form.items.first.max, 20);
    });
  });

  group('提交参数', () {
    EvalForm form() => EvalForm.tryParse(_fixture())!;

    test('保存：tjzt=0，每个指标带齐四个字段', () {
      final fields = buildSubmitFields(
        form(),
        {'ITEM_A1': 95, 'ITEM_A2': 95, 'ITEM_B1': 95},
        submit: false,
      );
      expect(fields['tjzt'], '0');
      expect(fields['sfbhmgc'], '0');
      expect(fields['jgh_id'], 'FORM_JGH_ID_001');
      expect(fields['modelList[0].pjmbmcb_id'], 'MODEL_ID_001');
      expect(fields['modelList[0].pjzt'], '1');
      expect(fields['modelList[0].xspjList[0].pjzbxm_id'], 'GROUP_A');
      expect(fields['modelList[0].xspjList[0].childXspjList[0].pjzbxm_id'], 'ITEM_A1');
      expect(fields['modelList[0].xspjList[0].childXspjList[0].pfdjdmb_id'], 'GRADE_CODE');
      expect(fields['modelList[0].xspjList[0].childXspjList[0].zsmbmcb_id'], 'TPL_CODE');
      expect(fields['modelList[0].xspjList[0].childXspjList[0].pjf'], '95');
      expect(fields['modelList[0].xspjList[1].pjzbxm_id'], 'GROUP_B');
      expect(fields['modelList[0].xspjList[1].childXspjList[0].pjf'], '95');
    });

    test('提交：tjzt=1', () {
      final fields = buildSubmitFields(
        form(),
        {'ITEM_A1': 90, 'ITEM_A2': 90, 'ITEM_B1': 90},
        submit: true,
      );
      expect(fields['tjzt'], '1');
    });

    test('少打一项必填分直接拒绝，绝不发半截数据', () {
      expect(
        () => buildSubmitFields(form(), {'ITEM_A1': 90}, submit: true),
        throwsA(isA<EvaluateError>()),
      );
    });

    test('分数是整数，不许出现 95.0000000000001', () {
      final fields = buildSubmitFields(
        form(),
        {'ITEM_A1': 95.00000000000001, 'ITEM_A2': 94.6, 'ITEM_B1': 80.4},
        submit: true,
      );
      expect(fields['modelList[0].xspjList[0].childXspjList[0].pjf'], '95');
      expect(fields['modelList[0].xspjList[0].childXspjList[1].pjf'], '94.6');
      expect(fields['modelList[0].xspjList[1].childXspjList[0].pjf'], '80.4');
    });

    test('评语先做一次百分号编码（页面 JS 的那次 encodeURIComponent）', () {
      final fields = buildSubmitFields(
        form(),
        {'ITEM_A1': 90, 'ITEM_A2': 90, 'ITEM_B1': 90},
        submit: true,
        comment: '讲得好 继续',
      );
      expect(fields['modelList[0].py'], Uri.encodeComponent('讲得好 继续'));
    });

    test('表单编码：键里的方括号也要转义', () {
      final body = EvaluateApi.encodeForm({'a[0].b': 'x y'});
      expect(body, contains('a%5B0%5D.b='));
      expect(body, contains('x%20y'));
    });
  });

  group('待评列表解析', () {
    test('正常条目 → EvalTarget（教师 / 课程 / 状态）', () {
      final t = EvalTarget.tryParse({
        'jxb_id': 'JXB1',
        'kch_id': 'KCH1',
        'jgh_id': 'JGH1',
        'sfcjlrjs': '1',
        'tjzt': '-1',
        'kcmc': '离散数学',
        'jzgmc': '马秀莹',
        'jxbmc': '2602121',
        'jgmc': '计算机学院',
        'sksj': '星期一第3-4节{1-12周}',
        'xsdm': '01',
      });
      expect(t, isNotNull);
      expect(t!.course, '离散数学');
      expect(t.teacher, '马秀莹');
      expect(t.pending, isTrue);
      expect(t.statusLabel, '未评');
      expect(t.id, 'JXB1|JGH1');
    });

    test('超星尔雅那类缺 sksj / jxdd / zcmc 的条目也要能解析', () {
      final t = EvalTarget.tryParse({
        'jxb_id': 'JXB2',
        'kch_id': 'KCH2',
        'jgh_id': 'JGH2',
        'tjzt': '0',
        'kcmc': '艺术美学',
        'jzgmc': '超星尔雅',
      });
      expect(t, isNotNull);
      expect(t!.time, isEmpty);
      expect(t.saved, isTrue);
      expect(t.statusLabel, '已保存');
    });

    test('缺 jxb_id / jgh_id 的脏数据直接跳过', () {
      expect(EvalTarget.tryParse({'kch_id': 'K', 'kcmc': 'x', 'jzgmc': 'y'}), isNull);
      expect(EvalTarget.tryParse(null), isNull);
      expect(EvalTarget.tryParse(<String, dynamic>{}), isNull);
    });

    test('已提交条目的状态文案', () {
      final t = EvalTarget.tryParse({
        'jxb_id': 'J',
        'kch_id': 'K',
        'jgh_id': 'G',
        'tjzt': '1',
        'kcmc': '课',
        'jzgmc': '师',
      })!;
      expect(t.submitted, isTrue);
      expect(t.statusLabel, '已提交');
    });
  });

  group('一键打分', () {
    test('统一分数摊到全部指标上，各自吸附到合法范围', () {
      final form = EvalForm.tryParse(_fixture())!;
      final scores = presetScores(form, 88);
      expect(scores, hasLength(3));
      expect(scores.values.every((v) => v == 88), isTrue);
    });

    test('超出范围的分数被夹住', () {
      final form = EvalForm.tryParse(_fixture())!;
      expect(presetScores(form, 999).values.every((v) => v == 100), isTrue);
      expect(presetScores(form, -5).values.every((v) => v == 0), isTrue);
    });
  });

  group('校园隧道代理地址', () {
    test('http://host:port 与裸 host:port 都能解析', () {
      final a = parseHttpProxy('http://anticraft.top:10004');
      expect(a, isNotNull);
      expect(a!.host, 'anticraft.top');
      expect(a.port, 10004);
      final b = parseHttpProxy('10.0.0.2:10004');
      expect(b!.host, '10.0.0.2');
      expect(b.port, 10004);
    });

    test('带路径 / 带凭据 / 多余斜杠都不影响', () {
      final a = parseHttpProxy('http://u:p@proxy.internal:8080/');
      expect(a!.host, 'proxy.internal');
      expect(a.port, 8080);
    });

    test('空串、缺端口、端口非数字 → null（调用方据此给引导）', () {
      expect(parseHttpProxy(''), isNull);
      expect(parseHttpProxy('   '), isNull);
      expect(parseHttpProxy('hostonly'), isNull);
      expect(parseHttpProxy('host:abc'), isNull);
      expect(parseHttpProxy(':8080'), isNull);
    });
  });
}