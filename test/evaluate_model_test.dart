import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评教助手的纯逻辑：网页消息解析、分值吸附、评教页地址。
/// 真机连教务才能验页面 DOM，这里钉住「页面发了什么 → App 怎么理解」这一层。
void main() {
  group('扫描结果解析', () {
    test('items 消息 → 评分项（标签 / 当前分 / 离散档位）', () {
      final scan = parseEvalMessage(jsonEncode({
        't': 'items',
        'login': false,
        'page': {'title': '学生评教'},
        'items': [
          {
            'index': 0,
            'label': '教学态度认真',
            'kind': 'radio',
            'value': 5,
            'min': 1,
            'max': 5,
            'step': 1,
            'values': [1, 2, 3, 4, 5],
          },
          {
            'index': 1,
            'label': '内容充实',
            'kind': 'range',
            'value': 80,
            'min': 0,
            'max': 100,
            'step': 10,
            'values': <double>[],
          },
        ],
      }));

      expect(scan, isNotNull);
      expect(scan!.items, hasLength(2));
      expect(scan.login, isFalse);
      expect(scan.items.first.label, '教学态度认真');
      expect(scan.items.first.discrete, isTrue);
      expect(scan.items.first.value, 5);
      expect(scan.items[1].discrete, isFalse, reason: '滑块没有离散档位');
      expect(scan.items[1].max, 100);
    });

    test('没有分值范围的项被跳过；标签空时退化成序号', () {
      final scan = parseEvalMessage(jsonEncode({
        't': 'items',
        'items': [
          {'index': 0, 'label': '', 'kind': 'radio', 'value': 3, 'min': 1, 'max': 5},
          {'index': 1, 'label': '坏数据', 'kind': 'radio', 'value': 3},
        ],
      }));
      expect(scan!.items, hasLength(1));
      expect(scan.items.single.title, '第 1 项');
    });

    test('一个都没识别到：提示带上候选控件计数，并区分是否登录页', () {
      final scan = parseEvalMessage(jsonEncode({
        't': 'none',
        'login': true,
        'counts': {'radio': 12, 'range': 0, 'slider': 2, 'select': 0},
      }));
      expect(scan, isNotNull);
      expect(scan!.items, isEmpty);
      expect(scan.login, isTrue);
      expect(scan.hint, contains('没识别到评分项'));
      expect(scan.hint, contains('单选组 12 个'));
      expect(scan.hint, contains('页面滑块 2 个'));
    });

    test('一个都没识别到：把页面输入控件的形态一起带出来（排查改版）', () {
      final scan = parseEvalMessage(jsonEncode({
        't': 'none',
        'login': false,
        'counts': {'text': 0, 'radio': 0},
        'samples': [
          {'tag': 'input', 'type': 'text', 'placeholder': '打分范围:0-100'},
        ],
      }));
      expect(scan!.hint, contains('一个候选控件都没找到'));
      expect(scan.hint, contains('input/text'));
      expect(scan.hint, contains('打分范围:0-100'));
    });

    test('评分输入框（正方 9.0 的「打分范围:0-100」文本框）也当评分项', () {
      final scan = parseEvalMessage(jsonEncode({
        't': 'items',
        'items': [
          {
            'index': 0,
            'label': '课程教学过程融入了价值塑造和情感教育的内容',
            'kind': 'text',
            'value': 0,
            'min': 0,
            'max': 100,
            'step': 1,
            'values': <double>[],
          },
        ],
      }));
      expect(scan!.items.single.discrete, isFalse);
      expect(scan.items.single.max, 100);
      expect(scan.items.single.snap(87), 87);
      expect(scan.items.single.snap(140), 100);
    });

    test('别的消息不当成扫描结果（应用回执走 parseEvalApplied）', () {
      expect(parseEvalMessage('{"t":"applied","values":{"0":5}}'), isNull);
      expect(parseEvalMessage('不是 JSON'), isNull);
    });

    test('applied 回执：下标 → 页面真实分值（离散项会被就近取档）', () {
      final applied = parseEvalApplied('{"t":"applied","values":{"0":5,"2":3}}');
      expect(applied, {0: 5.0, 2: 3.0});
      expect(parseEvalApplied('{"t":"items"}'), isEmpty);
    });
  });

  group('分值吸附', () {
    const discrete = EvalItem(
      index: 0,
      label: '教学态度',
      kind: 'radio',
      value: 5,
      min: 1,
      max: 5,
      values: [1, 2, 3, 4, 5],
    );
    const stepped = EvalItem(
      index: 1,
      label: '内容',
      kind: 'range',
      value: 60,
      min: 50,
      max: 100,
      step: 10,
    );

    test('离散项吸到最近的合法分值', () {
      expect(discrete.snap(4.4), 4);
      expect(discrete.snap(4.6), 5);
      expect(discrete.snap(100), 5);
      expect(discrete.snap(-3), 1);
    });

    test('连续项夹进范围并按步长对齐', () {
      expect(stepped.snap(63), 60);
      expect(stepped.snap(66), 70);
      expect(stepped.snap(1000), 100);
      expect(stepped.snap(0), 50);
    });

    test('非数字回落到当前分', () {
      expect(discrete.snap(double.nan), 5);
    });
  });

  group('评教页地址', () {
    test('默认 SIT 教务：按学校档案拼，不写死域名', () {
      expect(
        evalUrlFor('https://jwxt.sit.edu.cn'),
        'https://jwxt.sit.edu.cn/jwglxt'
        '/xspjgl/xspj_cxXspjIndex.html?doType=details&gnmkdm=N401605&layout=default',
      );
    });

    test('末尾斜杠不会拼出双斜杠；换学校自动换域名', () {
      expect(evalUrlFor('https://jw.example.edu/'), contains('jw.example.edu/jwglxt/xspjgl'));
      expect(evalLoginUrlFor('https://jw.example.edu'),
          'https://jw.example.edu/jwglxt/xtgl/login_slogin.html');
    });

    test('学校档案没填教务域名时返回空串（界面提示去配置）', () {
      expect(evalUrlFor(''), isEmpty);
      expect(evalLoginUrlFor('   '), isEmpty);
    });
  });
}
