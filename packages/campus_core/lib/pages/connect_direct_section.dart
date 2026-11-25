import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// 直连模式段：校园网提示 + 本地模拟服务卡（仅 debug）+ 校园凭据卡 + 学校信息卡。
class ConnectDirectSection extends StatelessWidget {
  const ConnectDirectSection({
    super.key,
    required this.credentials,
    required this.schoolCard,
    this.mockCard,
  });

  final Widget credentials;
  final Widget schoolCard;

  /// 仅 debug 构建传入（本地模拟服务卡）。
  final Widget? mockCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SemColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: SemColors.warning.withValues(alpha: 0.35)),
          ),
          child: Text(
            '直连模式不走服务器：请先连接校园网或校内 VPN（校园内网）。校外且没有校内 VPN 时，'
            '请改用服务器模式，或让学校提供可访问的服务器地址。',
            style: TextStyle(
                fontSize: 12.5, color: SemColors.warning, height: 1.7),
          ),
        ),
        const SizedBox(height: 10),
        if (mockCard != null) ...[mockCard!, const SizedBox(height: 10)],
        credentials,
        const SizedBox(height: 10),
        schoolCard,
      ],
    );
  }
}
