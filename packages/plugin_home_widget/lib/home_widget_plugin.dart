import 'package:campus_core/campus_core.dart';

import 'home_widget_capability_impl.dart';

/// 桌面卡片 + 长按图标的快捷方式。
///
/// * **桌面卡片**：主屏小组件「今日课程」「校园卡余额」，标准 Android App Widget，
///   ColorOS / OriginOS / 澎湃OS 等桌面都支持；数据由 App 同步过去，点卡片回到对应页面。
/// * **长按图标**：快捷方式（static shortcuts）直接跳「校园码 / 课程表」——
///   菜单由系统桌面绘制，App 只声明动作。
///
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
    // 点卡片 / 长按快捷方式进来：把原生动作转给主界面（切到对应底栏页）。
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

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 能力挂在本插件 id 上：课表保存后由 [TimetableStore] 同步今日课程；
/// 校园码拿到余额后由它同步余额。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_HOME_WIDGET=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉（卡片仍留在桌面上，但不再更新）。
const PluginBundle pluginBundle = PluginBundle(
  features: [HomeWidgetPlugin()],
  capabilities: {PluginIds.homeWidget: HomeWidgetCapabilityImpl()},
);
