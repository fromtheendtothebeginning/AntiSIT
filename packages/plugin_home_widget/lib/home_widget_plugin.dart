import 'package:campus_core/campus_core.dart';

import 'home_widget_capability_impl.dart';

/// 桌面卡片 + 长按图标快捷方式：主屏小组件（今日课程 / 校园卡余额）与 static shortcuts。
/// 本插件只做通道与转发，不占底栏、不弹通知。
class HomeWidgetPlugin extends FeaturePlugin {
  const HomeWidgetPlugin();

  static const pluginId = PluginIds.homeWidget;

  @override
  String get id => pluginId;
  @override
  String get name => '桌面卡片';
  @override
  String get description => '主屏小组件（今日课程 / 校园卡余额）与长按图标的快捷方式，适配各厂商桌面';
  @override
  bool get defaultEnabled => true;
  @override
  int get settingsOrder => 47;

  @override
  Future<void> init() async {
    // 点卡片 / 快捷方式进来：把原生动作转给主界面（切到对应底栏页）。
    HomeWidgetCapabilityImpl.channel.setMethodCallHandler((call) async {
      if (call.method != 'launchAction') return null;
      final action = '${call.arguments ?? ''}'.trim();
      if (action.isNotEmpty) AppLaunch.I.post(action);
      return null;
    });
    // 冷启动时动作可能比这里先到：主动取一次，取到就转出去。
    final pending = await const HomeWidgetCapabilityImpl().takeLaunchAction();
    if (pending != null && pending.trim().isNotEmpty) AppLaunch.I.post(pending.trim());
  }
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；能力挂在 PluginIds.homeWidget 上，
/// 课表保存后同步今日课程、校园码拿到余额后同步余额；EXCLUDE_HOME_WIDGET 为真时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [HomeWidgetPlugin()],
  capabilities: {PluginIds.homeWidget: HomeWidgetCapabilityImpl()},
);
