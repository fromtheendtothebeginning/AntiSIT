import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_capability_impl.dart';
import 'risk_notice_page.dart';

/// 风险提醒：高风险功能（校园码付款码 / 宿舍电费充值）前面的**默认开启**的一道闸。
///
/// * **开启（默认）**：那两项功能不直接放行——付款码的位置换成引导、充值按钮改成
///   提醒，都指向「插件管理里关掉它」；关之前还要过一遍条款（见 [RiskNoticeCapability]）。
/// * **关闭**：视为用户自担风险，两项功能立即恢复；插件管理里随时能再开回来。
///
/// 自己不联网、不上传任何数据，也不改变账号或卡片状态，只做本机拦截。
class RiskPlugin extends FeaturePlugin {
  const RiskPlugin();

  static const pluginId = 'risk';

  @override
  String get id => pluginId;
  @override
  String get name => '风险提醒';
  @override
  String get description => '默认开启：付款码与电费充值先拦一道，关闭前需阅读风险条款';

  /// 装进清单就生效。默认值本来就是 true，这里写出来是为了把语义钉死：
  /// 用户关掉之后由注册表记住这个选择，不会自己再开回来。
  @override
  bool get defaultEnabled => true;

  /// 「我的 → 设置」里放一条：条款随时能读（拦截引导里也有入口），排在 AI / 反馈后面。
  @override
  int get settingsOrder => 90;

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) => [
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('风险提醒'),
          subtitle: const Text('付款码 / 电费充值的拦截与免责声明',
              style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RiskNoticePage())),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_RISK=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉——那之后没有拦截，行为等同「没装风险提醒」。
const PluginBundle pluginBundle = PluginBundle(
  features: [RiskPlugin()],
  // 能力挂在本插件 id 上：被拦的功能按「接口 + 'risk'」取用；
  // 停用 / 没装时取不到 → 直接放行（见 RiskNoticeCapability 的说明）。
  capabilities: {RiskPlugin.pluginId: RiskNoticeCapabilityImpl()},
);
