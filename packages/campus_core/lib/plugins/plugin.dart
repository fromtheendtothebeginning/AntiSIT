import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/common.dart';
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
  static const themeGlass = 'theme.glass';
}

/// 一个插件包交给宿主的东西：它的功能插件与主题插件。
/// 插件包的 barrel 里暴露一个 `pluginBundle` 常量，清单生成器按包名登记它。
class PluginBundle {
  const PluginBundle({this.features = const [], this.themes = const []});

  final List<FeaturePlugin> features;
  final List<ThemePlugin> themes;
}
