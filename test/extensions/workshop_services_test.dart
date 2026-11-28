import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// 工坊注入给网页的服务面：模型 / 语音 / 目标 / 计划的接口都得在，
/// 少一个网页就会在用到时抛「未定义」。
void main() {
  setUpExtensionEnv();

  test('工坊页面注入了模型切换、语音与技能导入用的服务', () async {
    final item = kBuiltinExtensions.first;
    final page = await CordisBundleLoader.load(item, appVersion: '1.25.0');

    for (final method in [
      'ai.models',
      'ai.current',
      'ai.setModel',
      'voice.start',
      'voice.stop',
      'voice.cancel',
      'voice.available',
    ]) {
      expect(page.html, contains(method), reason: '缺少 $method');
    }
  });

  test('工坊清单声明了 files 与 voice（用到才不报没权限）', () {
    final item = kBuiltinExtensions.first;
    expect(item.permissions, contains('files'));
    expect(item.permissions, contains('voice'));
    expect(item.permissions, contains('ai'));
  });

  test('内置工坊的 main.js 里有目标 / 计划工具与卡片', () async {
    final file = File(
      'packages/plugin_ext/assets/builtin/workshop/main.js',
    );
    expect(file.existsSync(), isTrue);
    final js = await file.readAsString();
    for (final token in [
      "name: 'set_goal'",
      "name: 'update_plan'",
      "'goal/set'",
      "'plan/update'",
      "role: 'goal'",
      "role: 'plan'",
    ]) {
      expect(js, contains(token), reason: '缺少 $token');
    }
  });
}
