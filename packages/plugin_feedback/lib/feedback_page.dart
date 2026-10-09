import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:campus_core/campus_core.dart';

const String _repo = 'https://github.com/fromtheendtothebeginning/AntiSIT';

/// 提交反馈：Issue（报问题/提建议）、PR（贡献代码）、Fork（GPL-3.0 自建分支），
/// 三种方式都跳转 GitHub 对应页面；打不开时复制链接兜底。
class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});

  /// 打开链接；打不开（无浏览器/网络受限）时复制到剪贴板兜底。
  Future<void> _open(String url, BuildContext context) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已复制链接：$url'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提交反馈')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _head(Icons.favorite_outline, 'AntiSIT 是开源项目'),
                const SizedBox(height: 6),
                Text('遇到问题、有好点子、想参与开发，都欢迎到 GitHub 上告诉我们：',
                    style: TextStyle(
                        fontSize: 12.5, color: SemColors.textSecondary, height: 1.7)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _way(
            context,
            icon: Icons.bug_report_outlined,
            title: '提交 Issue',
            desc: '报 Bug、提功能建议。描述清楚现象与复现步骤（附截图更好），'
                '我们会在 issue 区跟进处理。',
            url: '$_repo/issues/new',
          ),
          const SizedBox(height: 10),
          _way(
            context,
            icon: Icons.merge_type_outlined,
            title: '提交 PR',
            desc: '贡献代码 / 文档：fork 本仓库、改好后从 compare 页发起 Pull Request，'
                '合并后你就是项目贡献者。',
            url: '$_repo/compare',
          ),
          const SizedBox(height: 10),
          _way(
            context,
            icon: Icons.account_tree_outlined,
            title: 'Fork 成自己的项目',
            desc: '基于 AntiSIT 打造你自己的版本。本项目采用 GPL-3.0 协议：'
                'fork / 修改后的衍生作品必须同样以 GPL-3.0 开源，并保留原版权声明。',
            url: '$_repo/fork',
          ),
          const SizedBox(height: 14),
          Center(
            child: InkWell(
              onTap: () => _open(_repo, context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, size: 14, color: SemColors.textMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                          '仓库主页：github.com/fromtheendtothebeginning/AntiSIT（GPL-3.0）',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _head(IconData icon, String title) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: SemColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: SemColors.accent),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      );

  Widget _way(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required String url,
  }) {
    return AppCard(
      onTap: () => _open(url, context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: SemColors.accentSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: SemColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    Icon(Icons.open_in_new, size: 15, color: SemColors.textMuted),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12, color: SemColors.textSecondary, height: 1.7)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
