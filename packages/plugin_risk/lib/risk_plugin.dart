import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'risk_capability_impl.dart';
import 'risk_notice_page.dart';
import 'risk_terms.dart';

/// 风险提醒：受拦截行为（校园码付款码 / 宿舍电费充值）前的默认启用的一道闸，只做本机拦截。
/// 启用时两项行为不予执行并引导去插件管理停用，停用前需经条款确认，停用后即行恢复；
/// 不发起网络请求、不传输用户数据、不改变账号与账务，用户可见措辞一律取自 [RiskTerms]。
class RiskPlugin extends FeaturePlugin {
  const RiskPlugin();

  static const pluginId = 'risk';

  @override
  String get id => pluginId;
  @override
  String get name => '风险提醒';
  @override
  String get description => '默认启用：校园码付款码、宿舍电费充值等行为依《${RiskTerms.title}》不予执行';

  /// 默认启用；用户停用后由注册表记住该选择，不会自己再启用。
  @override
  bool get defaultEnabled => true;

  /// 「我的 → 设置」入口，排在 AI / 反馈后面。
  @override
  int get settingsOrder => 90;

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) => [
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('风险提醒'),
          subtitle: const Text('拦截规则与责任条款（全文）',
              style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RiskNoticePage())),
        ),
      ];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；能力挂在 'risk' 上，停用 / 没装时
/// 被拦功能取不到 → 直接放行；EXCLUDE_RISK 为真时整包被摇掉，等同没装。
const PluginBundle pluginBundle = PluginBundle(
  features: [RiskPlugin()],
  capabilities: {RiskPlugin.pluginId: RiskNoticeCapabilityImpl()},
);
