import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'capability.dart';
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

  /// 构建页面：[index] 是此刻在底栏里的位置（插件可被停用，不要写死常量）。
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

/// 功能插件——App 里一切可增删的功能单位（一个插件 = 一个 Dart 包）。
///
/// 插件间只按 id 声明依赖、不 import 彼此的代码，所以删包只会变成
/// [PluginRegistry.problems] 里的一条告警，不会编译不过。
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

  /// 默认启停：false = 装进清单后默认关闭，用户开关记在 `plugin_user_enabled`。
  bool get defaultEnabled => true;

  /// 底栏页面；返回空列表 = 不是导航页（也可能因为没有可用内容而隐藏自己）。
  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) => const [];

  /// 「工具」宫格卡片。
  List<PluginTool> tools(PluginRegistry registry) => const [];

  /// 设置卡片里的条目（开关 / 跳转 / 分组由插件自己定）。
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) => const [];

  /// 「我的 → 配置」页里的条目，顺序按 [settingsOrder]。
  List<Widget> configTiles(BuildContext context, PluginRegistry registry) => const [];

  /// 「课程表设置」二级页里的条目，顺序按 [settingsOrder]。
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
/// id 是持久化键（[AiConfig] 的 Key、模型缓存都按它存），**改名等于丢用户已填的 Key**。
/// 停用后它从 AI 设置的选择器里消失、AI 按「未配置」处理，存档里的 Key 保留。
abstract class AiProviderPlugin {
  const AiProviderPlugin();

  String get id;
  String get label;

  /// 一句话说明（插件管理页的列表用）。
  String get description;

  /// OpenAI 兼容基址；空 = 自定义提供商（界面让用户自己填地址）。
  String get baseUrl;

  /// 内置模型列表——只在拉不到官方 `GET {base}/models` 时兜底（只列能识图的）。
  List<String> get models;
  String get defaultModel;

  /// 申请（或订阅）页面：AI 设置页的按钮跳这里；空 = 不显示按钮。
  String get docs;

  /// 按钮文案：普通提供商「申请 API Key」，订阅套餐「订阅 Token Plan」。
  String get applyLabel;

  /// 品牌 logo：`packages/<包名>/assets/x.svg`；空 = 字母徽章兜底。
  String get logo;

  /// 关闭思考要加进请求体的字段：各家协议不同，未识别的一律返回空（乱加字段会 400）。
  Map<String, dynamic> thinkingOff(String model) => const {};

  /// 指定思考深度要加进请求体的字段（[effort] 为 'low' / 'medium' / 'high' / 'none'）。
  /// 默认原样交给 OpenAI 兼容的 `reasoning_effort`——多数端点认这个字段；
  /// 认不出的（智谱 / MiniMax 这类要别名字段或根本没有档位的）在这里覆写成空 Map。
  Map<String, dynamic> reasoningEffort(String model, String effort) =>
      {'reasoning_effort': effort};

  /// false = 界面上不给停用（核心提供商）。
  bool get removable => true;

  bool get isCustom => baseUrl.isEmpty;
}

/// 跨包引用的插件 id：插件之间只按 id 声明依赖，不 import 彼此的包。
abstract final class PluginIds {
  static const network = 'network';
  static const profile = 'profile';
  static const timetable = 'timetable';
  static const ai = 'ai';
  static const reminder = 'reminder';

  /// 风险提醒：付款码 / 电费充值前面的拦截闸。
  static const risk = 'risk';
  static const tools = 'tools';
  static const webview = 'webview';

  /// 学生评教助手：内嵌教务评教页，一键同分 / 逐项调分。
  static const evaluate = 'evaluate';
  static const camera = 'camera';
  static const scan = 'scan';
  static const activities = 'activities';

  /// 流体云：走系统通知 API 的常驻进度通知，不需要厂商 SDK。
  static const fluidCloud = 'fluid_cloud';

  /// 流体云课程通知：在流体云能力与课程表之上做通知策略三选一。
  static const courseCloud = 'course_cloud';

  /// 桌面卡片（App Widget）+ 长按图标快捷方式：只做数据转发，不占底栏。
  static const homeWidget = 'home_widget';

  /// 校园码：底栏页 + 桌面卡片（余额）。
  static const ecard = 'ecard';
  static const themeGlass = 'theme.glass';
}

/// 一个插件包交给宿主的东西：功能插件、主题插件、AI 提供商与对外能力。
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

  /// 本包对外提供的能力：key = 提供它的插件 id（必须是本包贡献的 id）。
  /// 声明在这里而不是 `init()` 里注册，因为 `init()` 运行期启用插件不会补跑。
  final Map<String, PluginCapability> capabilities;
}
