import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'market/market_page.dart';

/// 「添加拓展」页：三种加法 + 进入「插件市场」独立页的入口。
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
          body: ListView(
            // 顶部让出悬浮顶栏
            padding: EdgeInsets.fromLTRB(
              12,
              8 + topInset,
              12,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              AppCard(
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
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('插件市场'),
                  subtitle: const Text(
                    '从市场目录里发现并安装别人做的拓展',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MarketPage(onInstalled: onInstalled),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
