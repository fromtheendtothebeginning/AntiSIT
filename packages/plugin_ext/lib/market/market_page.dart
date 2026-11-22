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
          // 列表顶部留白放进滚动内容里：内容从顶栏下方开始，但滚动时会穿过顶栏
          // （顶栏那层色带才有内容可淡出）。
          body: MarketView(onInstalled: onInstalled, topPadding: topInset),
        );
      },
    );
  }
}
