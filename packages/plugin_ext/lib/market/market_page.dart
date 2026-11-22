import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'market_view.dart';

/// 插件市场独立页：从「添加拓展」里的「插件市场」进来。
class MarketPage extends StatelessWidget {
  const MarketPage({super.key, this.onInstalled});

  /// 装完 / 更新完说一句。
  final void Function(String message)? onInstalled;

  @override
  Widget build(BuildContext context) {
    // 整页监听 AppState：悬浮玻璃顶栏开关改完要连 Scaffold 一起重建
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('插件市场')),
          // 市场列表本身有搜索/筛选/下拉刷新，顶部让出悬浮顶栏即可
          body: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: MarketView(onInstalled: onInstalled),
          ),
        );
      },
    );
  }
}
