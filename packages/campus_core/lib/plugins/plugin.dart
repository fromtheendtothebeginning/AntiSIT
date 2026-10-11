import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'capability.dart';
// 只为贡献点方法的参数类型而引用（Dart 允许库之间循环 import：
// 插件实现要拿到注册表判断「我有没有可用内容」，注册表要收集插件贡献）。
import 'registry.dart';

/// 一个插件贡献的底栏页面。
class PluginNavItem {
  const PluginNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.build,
    this.order = 50,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// 构建页面。[index] = 该页此刻在底栏里的位置：插件能被停用，下标会变，
  /// 需要判断「我是不是当前这一页」的页面（校园码）靠它，不要写死常量。
  final Widget Function(int index) build;

  /// 底栏顺序（小的靠左），与插件在清单里的先后无关。
  final int order;
}

/// 一个插件贡献到「工具」宫格的卡片。
class PluginTool {
  const PluginTool({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.open,
  });

  final IconData icon;
  final Color color;
  final String title;

  /// 卡面副标题：每次构建求值，可反映 [FeaturePlugin.prefetch] 拉到的缓存。
  final String Function() subtitle;
  final Widget Function() open;
}

/// 功能插件——App 里一切可增删的功能单位。
///
/// **一个插件 = 一个 Dart 包**（`packages/plugin_xxx/`），只依赖 [campus_core]。
/// **导入**：`dart create` 出来的包照抄隔壁插件的 pubspec，写一个
/// `const PluginBundle pluginBundle = ...`，然后在宿主 pubspec 的依赖里加一行，
/// 再跑 `dart run tool/gen_plugins.dart` 重新生成清单。
/// **删除**：宿主 pubspec 去掉那一行依赖 → 重新生成 → 完事（包目录想留想删都行）。
/// 别的插件只按 id 声明依赖、不 import 彼此的代码，所以依赖没了只会变成
/// [PluginRegistry.problems] 里的一条告警，不会编译不过。
/// **停用**：管理页开关，运行期生效（代码仍在包里）。
/// **剔除**：`--dart-define=EXCLUDE_XXX=true` 构建时注册分支 const 为假，
/// AOT 摇树会把该插件及其页面从二进制里删掉。
abstract class FeaturePlugin {
  const FeaturePlugin();

  /// 全局唯一 id：依赖引用、持久化键、关系图节点都用它。
  String get id;
  String get name;
  String get description;

  /// 硬依赖：启用我时一起启用；停用它们会连带停用我（关系图画实线）。
  List<String> get dependencies => const [];

  /// 软依赖：有它增强、没它降级，不联动启停（关系图画虚线）。
  List<String> get optionalDependencies => const [];

  /// false = 核心插件（壳 / 登录 / 设置宿主），界面上不给关。
  bool get removable => true;

  /// 底栏页面；返回空列表 = 不是导航页（也可能因为没有可用内容而隐藏自己）。
  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) => const [];

  /// 「工具」宫格卡片。
  List<PluginTool> tools(PluginRegistry registry) => const [];

  /// 设置卡片里的条目（返回现成 widget：开关 / 跳转 / 分组由插件自己定）。
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) => const [];

  /// 「课程表设置」二级页里的条目（学期 / 调休 / 上课提醒 / 已上完的课淡化都收在那儿）。
  /// 与 [settingsTiles] 同一套 widget 约定，只是宿主换成了课表设置页；
  /// 顺序同样按 [settingsOrder]——课表页自己不贡献，它自己那几项直接写死在页面里。
  List<Widget> timetableSettingsTiles(BuildContext context, PluginRegistry registry) => const [];

  /// 设置条目顺序（小的靠前）。
  int get settingsOrder => 50;

  /// 拉一次工具卡面速览要用的缓存（余额、学分…）。
  Future<void> prefetch() async {}

  /// 启动初始化，只对已启用的插件调用。
  Future<void> init() async {}
}

/// 主题插件——一套浅色 / 深色色板 + 全局背景场景。
abstract class ThemePlugin {
  const ThemePlugin();

  String get id;
  String get name;
  String get description;

  GlassPalette palette(Brightness brightness);

  /// 背景光斑；默认无（纯色底），玻璃类主题自己提供。
  List<GlassWell> wells(Brightness brightness) => const [];
}

/// AI 提供商插件——一条「OpenAI 兼容服务」的描述（基址 / 模型 / 申请页 / 关思考写法）。
///
/// **一个提供商 = 一个 Dart 包**（`packages/plugin_ai_xxx/`），只依赖 [campus_core]，
/// 在 barrel 里暴露 `const PluginBundle pluginBundle = PluginBundle(providers: [...]);`。
/// id 是持久化键（[AiConfig] 的 Key、模型缓存都按它存），**改名等于丢用户已填的 Key**。
///
/// **停用**：插件管理页逐家开关（与功能插件共用 `plugin_disabled` 键）。停用后它不再出现在
/// AI 设置的选择器里，AI 也按「未配置」处理；存档里的 Key 留着，开回来就能继续用。
/// **剔除 / 删除**：`--dart-define=EXCLUDE_AI_XXX=true` 构建时剔除，或去掉 pubspec 那两行
/// ——连包里的 logo 一起从构建里消失。
abstract class AiProviderPlugin {
  const AiProviderPlugin();

  String get id;
  String get label;

  /// 一句话说明（插件管理页的列表用）。
  String get description;

  /// OpenAI 兼容基址；空 = 自定义提供商（界面让用户自己填地址）。
  String get baseUrl;

  /// 内置模型列表——只在拉不到官方 `GET {base}/models` 时兜底。
  /// 本 App 的两个功能都吃图片输入，所以只列能识图的模型。
  List<String> get models;
  String get defaultModel;

  /// 申请（或订阅）页面：AI 设置页的按钮跳这里；空 = 不显示按钮。
  String get docs;

  /// 按钮文案：普通提供商「申请 API Key」，订阅套餐「订阅 Token Plan」。
  String get applyLabel;

  /// 品牌 logo：`packages/<包名>/assets/x.svg`（包自己声明 assets）；空 = 字母徽章兜底。
  String get logo;

  /// 关闭思考要加进请求体的字段。各家协议不同，未识别的一律返回空——
  /// 乱加字段会 400（见各提供商包里的注释与 test/ai_settings_test.dart）。
  Map<String, dynamic> thinkingOff(String model) => const {};

  /// false = 界面上不给停用（核心提供商；目前没有用到，留给「这家必须能配」的场景）。
  bool get removable => true;

  bool get isCustom => baseUrl.isEmpty;
}

/// 跨包引用的插件 id。
///
/// 插件之间**只按 id 声明依赖，不 import 彼此的包**——那样删掉一个插件包会让
/// 依赖它的包编译不过，「自由删除」就断了。所以这类 id 集中在这里；被引用的插件
/// 真被删掉时，由 [PluginRegistry.validate] 报成 problems，而不是编译错误。
abstract final class PluginIds {
  static const network = 'network';
  static const profile = 'profile';
  static const timetable = 'timetable';
  static const ai = 'ai';
  static const reminder = 'reminder';
  static const tools = 'tools';
  static const themeGlass = 'theme.glass';
}

/// 一个插件包交给宿主的东西：它的功能插件、主题插件、AI 提供商与对外能力。
/// 插件包的 barrel 里暴露一个 `pluginBundle` 常量，清单生成器按包名登记它。
class PluginBundle {
  const PluginBundle({
    this.features = const [],
    this.themes = const [],
    this.providers = const [],
    this.capabilities = const {},
  });

  final List<FeaturePlugin> features;
  final List<ThemePlugin> themes;
  final List<AiProviderPlugin> providers;

  /// 本包对外提供的能力：key = **提供它的插件 id**（必须是本包贡献的插件 id），
  /// value = 能力实例。别的插件按「接口 + 这个 id」取用（见 [PluginCapability]）。
  /// 声明在这里而不是 `init()` 里注册：`init()` 只在启动时跑一次，运行期启用插件
  /// 不会补跑，声明在清单里就是构建期就位、只按启停状态决定能不能查到。
  final Map<String, PluginCapability> capabilities;
}
