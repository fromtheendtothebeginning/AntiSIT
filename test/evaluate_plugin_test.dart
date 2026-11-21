import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评教插件的接线：不再依赖 WebView 内核（原生界面），只在非演示模式出现入口。
void main() {
  const plugin = EvaluatePlugin();

  setUp(() => AppState.I.demo = false);
  tearDown(() => AppState.I.demo = false);

  test('不再依赖 WebView 内核：原生界面自己发请求', () {
    expect(plugin.id, 'evaluate');
    expect(plugin.dependencies, isEmpty);
    expect(plugin.navItems(PluginRegistry.I, ValueNotifier<int>(0)), isEmpty);
  });

  test('非演示模式：工具宫格出现「学生评教」卡片，点开是原生页', () {
    final tools = plugin.tools(PluginRegistry(features: const []));
    expect(tools, hasLength(1));
    expect(tools.single.title, '学生评教');
    expect(tools.single.open(), isA<EvaluatePage>());
  });

  test('演示模式（本地假数据）不出现评教入口', () {
    AppState.I.demo = true;
    expect(plugin.tools(PluginRegistry(features: const [])), isEmpty);
  });
}