import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_capability_impl.dart';
import 'risk_notice_page.dart';
import 'risk_terms.dart';

/// 风险提醒：受拦截行为（校园码付款码 / 宿舍电费充值）前面的**默认启用**的一道闸。
///
/// * **启用（默认）**：那两项行为不予执行——付款码的位置换成引导、充值入口改成
///   提醒，都指向「插件管理页停用」；停用之前还要经一遍条款确认（见 [RiskNoticeCapability]）。
/// * **停用**：依《[RiskTerms.title]》第五条，视为用户已同意全部条款，两项行为即行恢复；
///   插件管理里随时能再启用。
///
/// 本组件不发起网络请求、不传输用户数据，也不改变账号、卡片与账务，只做本机拦截。
/// 用户可见的措辞一律取自 [RiskTerms]（法律条文，先定义后使用），本文件不放文案。
class RiskPlugin extends FeaturePlugin {
  const RiskPlugin();

  static const pluginId = 'risk';

  @override
  String get id => pluginId;
  @override
  String get name => '风险提醒';
  @override
  String get description => '默认启用：依《${RiskTerms.title}》不予执行受拦截行为（校园码付款码、宿舍电费充值）';

  /// 装进清单就生效。默认值本来就是 true，这里写出来是为了把语义钉死：
  /// 用户停用之后由注册表记住这个选择，不会自己再启用。
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
          subtitle: const Text('受拦截行为的拦截规则与责任条款（全文）',
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
