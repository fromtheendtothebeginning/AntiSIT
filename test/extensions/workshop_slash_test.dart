import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 工坊的「/」命令面板：输入 / 时弹出工具与技能候选，能用上下键选、回车补进输入框。
void main() {
  test('main.js 里有 / 面板的容器、候选生成与键位处理', () async {
    final js = await File('packages/plugin_ext/assets/builtin/workshop/main.js')
        .readAsString();
    for (final token in [
      "id=\"slashPanel\"",
      'function slashCandidates(',
      'function renderSlash(',
      'function applySlash(',
      'function syncSlash(',
      "value.startsWith('/')",
      "e.key === 'ArrowDown'",
    ]) {
      expect(js, contains(token), reason: '缺少 $token');
    }
  });

  test('/ 面板同时收录工具与技能', () async {
    final js = await File('packages/plugin_ext/assets/builtin/workshop/main.js')
        .readAsString();
    // 工具来自 availableTools()，技能来自 S.skills —— 两类都必须进候选
    expect(js, contains('availableTools().map'));
    expect(js, contains('(S && S.skills) || [])'));
  });
}
