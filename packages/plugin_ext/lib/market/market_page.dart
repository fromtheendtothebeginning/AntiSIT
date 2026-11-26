import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'market_view.dart';

/// 插件市场独立页：从「添加拓展」里的「插件市场」进来。
class MarketPage extends StatelessWidget {
  const MarketPage({super.key, this.onInstalled, this.focusId});

  /// 装完 / 更新完说一句。
  final void Function(String message)? onInstalled;

  /// 从拓展页「有更新的卡片」跳进来时带上：市场自动过滤并高亮这条。
  final String? focusId;

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
          // 列表顶部留白放进滚动内容里：内容从顶栏下方开始，滚动时穿过顶栏
          body: GlassFadedBody(
            barHeight: topInset,
            child: MarketView(
            onInstalled: onInstalled,
            focusId: focusId,
            topPadding: topInset,
          ),
          ),
        );
      },
    );
  }
}
