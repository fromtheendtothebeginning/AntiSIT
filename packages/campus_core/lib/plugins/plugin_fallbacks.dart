import 'package:flutter/widgets.dart';

import '../widgets/common.dart';
import 'plugin.dart';

/// 一个主题包都没装时的兜底主题（见 `PluginRegistry.theme`）。
class FallbackTheme extends ThemePlugin {
  const FallbackTheme();

  @override
  String get id => 'theme.fallback';
  @override
  String get name => '默认';
  @override
  String get description => '兜底主题：没有安装任何主题插件时使用';
  @override
  GlassPalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? GlassPalette.dark : GlassPalette.light;
  @override
  List<GlassWell> wells(Brightness brightness) =>
      brightness == Brightness.dark ? kGlassWellsDark : kGlassWellsLight;
}

/// 一个提供商包都没装时的兜底（见 `PluginRegistry.resolveProvider`）。
/// 基址为空 → `AiConfig.ready` 为假，界面表现为「未配置」，不会崩。
class FallbackAiProvider extends AiProviderPlugin {
  const FallbackAiProvider();

  @override
  String get id => 'none';
  @override
  String get label => '未选择提供商';
  @override
  String get description => '没有装入任何 AI 提供商插件';
  @override
  String get baseUrl => '';
  @override
  List<String> get models => const [];
  @override
  String get defaultModel => '';
  @override
  String get docs => '';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => '';
}
