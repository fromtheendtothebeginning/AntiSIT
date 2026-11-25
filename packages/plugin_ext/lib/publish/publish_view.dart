import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:campus_core/campus_core.dart';

import '../cordis_bundle.dart';
import 'publish_models.dart';

/// 发布页顶部的拓展信息卡：名称 / id / 权限 / 发布说明。
class PublishHeaderCard extends StatelessWidget {
  const PublishHeaderCard({super.key, required this.manifest});

  final CordisManifest manifest;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SemColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SemColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${manifest.name}  v${manifest.version}',
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(manifest.id,
                style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            const SizedBox(height: 8),
            Text(
              manifest.permissions.isEmpty
                  ? '权限：无'
                  : '权限：${manifest.permissions.join(' / ')}',
              style: TextStyle(fontSize: 12, color: SemColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              '发布后：别人扫结果页的二维码可直接安装；把源地址加到市场就能接收后续更新。',
              style: TextStyle(
                fontSize: 11.5,
                color: SemColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '发布密钥只存在本机加密存储：清除 App 数据 / 换机后指纹会变，别人需要重新添加源。',
              style: TextStyle(
                fontSize: 11.5,
                color: SemColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}

/// 本机发布公钥指纹卡：展示并可复制指纹。
class PublishFingerprintCard extends StatelessWidget {
  const PublishFingerprintCard({super.key, required this.fingerprint, required this.onCopy});

  final String? fingerprint;
  final Future<void> Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: SemColors.cardElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '发布公钥指纹',
                    style:
                        TextStyle(fontSize: 11.5, color: SemColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    fingerprint ?? '生成中…',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '复制指纹',
              onPressed: fingerprint == null
                  ? null
                  : () => onCopy(fingerprint!, '公钥指纹'),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
          ],
        ),
      );
}

/// 发布失败的错误卡。
class PublishErrorCard extends StatelessWidget {
  const PublishErrorCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SemColors.dangerSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          text,
          style:
              TextStyle(fontSize: 12.5, height: 1.5, color: SemColors.danger),
        ),
      );
}

/// 发布成功后的结果卡：两张二维码与可复制的源地址 / 安装码。
class PublishResultCard extends StatelessWidget {
  const PublishResultCard({super.key, required this.result, required this.onCopy});

  final PublishResult result;
  final Future<void> Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SemColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SemColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: SemColors.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已发布「${result.name}」v${result.version}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '别人用 AntiSIT「拓展 → 扫一扫」扫下面两张码：一张直接安装，'
            '一张把源加进市场（接收后续更新）。',
            style: TextStyle(
              fontSize: 12,
              color: SemColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '直装（扫码安装）',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SemColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: result.installCode,
                size: 220,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '添加插件源（接收后续更新）',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SemColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: result.sourceCode,
                size: 200,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '扫码后会先拉一次目录并核对公钥指纹，一致才让你确认添加。',
            style: TextStyle(
              fontSize: 11.5,
              color: SemColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _row('源地址', result.sourceInput),
          const SizedBox(height: 6),
          _row('分支', result.branch),
          const SizedBox(height: 6),
          _row('公钥指纹', result.fingerprint),
          const SizedBox(height: 12),
          Text(
            '想接收后续更新：让对方扫上面第二张码，或在「拓展 → 市场 → 添加第三方源」'
            '填上面的源地址，核对指纹后添加；以后你重新发布，他们就能在列表里一键更新。',
            style: TextStyle(
              fontSize: 11.5,
              color: SemColors.textMuted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => onCopy(result.sourceInput, '源地址'),
                child: const Text('复制源地址'),
              ),
              OutlinedButton(
                onPressed: () => onCopy(result.installCode, '安装码'),
                child: const Text('复制安装码'),
              ),
              OutlinedButton(
                onPressed: () => onCopy(result.sourceCode, '源二维码内容'),
                child: const Text('复制源二维码内容'),
              ),
              OutlinedButton(
                onPressed: () => onCopy(result.shareText, '分享文案'),
                child: const Text('复制分享文案'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ],
      );
}
