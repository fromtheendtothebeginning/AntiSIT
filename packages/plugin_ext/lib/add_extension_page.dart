import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'market/market_view.dart';

/// 「添加拓展」页：三种加法（填写网址 / 导入 Cordis 压缩包 / 导入 JSON）
/// 加上插件市场列表。
///
/// 市场原来是拓展页里的第二个滑块页（和「我的拓展」并排）；现在收进这一页，
/// 拓展页只剩自己的拓展列表，市场不再和它并排显示。
class AddExtensionPage extends StatelessWidget {
  const AddExtensionPage({
    super.key,
    required this.onAddUrl,
    required this.onImportBundle,
    required this.onImportJson,
    this.onInstalled,
  });

  /// 填写网址（打开新建弹窗）。
  final Future<void> Function() onAddUrl;

  /// 导入 Cordis 压缩包。
  final Future<void> Function() onImportBundle;

  /// 粘贴一份拓展 JSON。
  final Future<void> Function() onImportJson;

  /// 市场里装完 / 更新完说一句（拓展页拿它弹提示）。
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
          appBar: glassAppBar(context, title: const Text('添加拓展')),
          body: Column(
            children: [
              Padding(
                // 顶部让出悬浮顶栏
                padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.link_rounded),
                        title: const Text('填写网址'),
                        subtitle: const Text(
                          '给它起个名字，填一个 http(s) 网址',
                          style: TextStyle(fontSize: 12),
                        ),
                        onTap: onAddUrl,
                      ),
                      ListTile(
                        leading: const Icon(Icons.folder_zip_outlined),
                        title: const Text('导入 Cordis 压缩包'),
                        subtitle: const Text(
                          'ext.json + main.js 打成 zip；导入后自动解压',
                          style: TextStyle(fontSize: 12),
                        ),
                        onTap: onImportBundle,
                      ),
                      ListTile(
                        leading: const Icon(Icons.data_object_rounded),
                        title: const Text('导入 JSON'),
                        subtitle: const Text(
                          '粘贴一份拓展 JSON（单条或数组）',
                          style: TextStyle(fontSize: 12),
                        ),
                        onTap: onImportJson,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: MarketView(onInstalled: onInstalled)),
            ],
          ),
        );
      },
    );
  }
}
