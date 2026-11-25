import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart';

const String _antisitRepo =
    'https://github.com/fromtheendtothebeginning/AntiSIT';
const String _anticraftRepo =
    'https://github.com/fromtheendtothebeginning/anticraft';

/// 服务器模式下的自建指引：本项目（含 API 文档）与现成开源服务端（GPL-3.0）。
class ConnectSelfHostCard extends StatelessWidget {
  const ConnectSelfHostCard({super.key});

  /// 打开仓库链接；打不开（无浏览器 / 网络受限）时复制到剪贴板兜底。
  Future<void> _openRepo(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制链接：$url'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _repoLink(BuildContext context, String label, String url) => InkWell(
        onTap: () => _openRepo(context, url),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 15, color: SemColors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: SemColors.accent,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '自建服务器',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            '上面填的地址可以是任何实现了同一套开放接口的服务器，两种方式：',
            style: TextStyle(
              fontSize: 12.5,
              color: SemColors.textSecondary,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '① 参照 API 文档自行实现：本项目仓库内 docs/campus-api.md 是完整接口规约，'
            '照此用任意语言 / 框架重建服务端即可接入本 App。',
            style: TextStyle(
              fontSize: 12.5,
              color: SemColors.textSecondary,
              height: 1.7,
            ),
          ),
          _repoLink(
            context,
            'github.com/fromtheendtothebeginning/AntiSIT（含 API 文档）',
            _antisitRepo,
          ),
          const SizedBox(height: 8),
          Text(
            '② 直接部署现成服务端：anticraft 校园服务网站就是这套接口的参考实现，同样开源，'
            '部署好把地址填到上方即可。',
            style: TextStyle(
              fontSize: 12.5,
              color: SemColors.textSecondary,
              height: 1.7,
            ),
          ),
          _repoLink(
            context,
            'github.com/fromtheendtothebeginning/anticraft（GPL-3.0）',
            _anticraftRepo,
          ),
          const SizedBox(height: 6),
          Text(
            '两个项目均为 GPL-3.0 开源。协议要点：可自由使用、学习、修改与再分发；'
            '再分发或衍生作品必须同样以 GPL-3.0 开源并提供完整源码；软件不含任何担保。',
            style: TextStyle(
              fontSize: 11.5,
              color: SemColors.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
