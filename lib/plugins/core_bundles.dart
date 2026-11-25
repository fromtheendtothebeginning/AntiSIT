import 'package:campus_core/campus_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../pages/profile_page.dart';

/// 宿主自带的两个**核心插件**（不是独立包：它们要用宿主的页面，放进包反而要来回注入回调）。
/// 都不可停用：`network` 是所有取数插件的硬依赖，「我的」是登录与恢复插件的唯一入口。
const PluginBundle appCoreBundle = PluginBundle(
  features: [NetworkPlugin(), ProfilePlugin()],
);

/// 核心：数据来源与登录态（服务器 token / 直连校园凭据）。
class NetworkPlugin extends FeaturePlugin {
  const NetworkPlugin();

  @override
  String get id => PluginIds.network;
  @override
  String get name => '网络与登录';
  @override
  String get description => '服务器 token / 直连校园凭据的读写与两种数据来源的切换（无界面，被所有取数插件依赖）';
  @override
  bool get removable => false;

  @override
  Future<void> init() async {
    // 调试构建：学校档案指向本机回环时拉起本地模拟校园服务（无校园网也能测直连）
    await MockCampusServer.instance.ensureIfConfigured();
  }
}

/// 核心：我的（登录入口 / 设置宿主 / 插件管理入口）。
class ProfilePlugin extends FeaturePlugin {
  const ProfilePlugin();

  @override
  String get id => PluginIds.profile;
  @override
  String get name => '我的';
  @override
  String get description => '账号与学籍、服务状态、设置项宿主、插件管理入口（底栏最后一页）';
  @override
  bool get removable => false;
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) => [
        PluginNavItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person,
          label: '我的',
          order: 99,
          build: (_) => const ProfilePage(),
        ),
      ];
}
