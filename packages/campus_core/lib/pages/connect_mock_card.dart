import 'package:flutter/material.dart';

import '../direct/mock_campus_server.dart';
import '../widgets/common.dart';

/// 本地模拟服务卡（仅 debug 构建）：没有校园网时在 App 进程内跑一套行为一致的学校系统。
class ConnectMockCard extends StatelessWidget {
  const ConnectMockCard({
    super.key,
    required this.testing,
    required this.onUseMock,
  });

  final bool testing;
  final VoidCallback onUseMock;

  @override
  Widget build(BuildContext context) {
    final mock = MockCampusServer.instance;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: SemColors.accent),
              SizedBox(width: 6),
              Text(
                '本地模拟服务（仅调试构建）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '在 App 内监听 127.0.0.1 起一套与学校系统行为一致的模拟服务：'
            '正方教务（RSA 加密 + 图形验证码）、统一认证 CAS（AES 加密 + 图形验证码）、'
            '学工二课、校园卡（SM4 支付密码）。没有校园网也能把直连链路跑通。',
            style: TextStyle(
              fontSize: 12,
              color: SemColors.textSecondary,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: testing ? null : onUseMock,
                  child: Text(mock.running ? '重启并切到本地模拟服务' : '使用本地模拟服务'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mock.running
                ? '运行中：${mock.baseUrl}（模拟凭据 学号 ${MockCampusServer.studentId} / '
                    '密码 ${MockCampusServer.password} / 支付密码 ${MockCampusServer.payPassword}）'
                : '模拟凭据：学号 ${MockCampusServer.studentId} / 密码 ${MockCampusServer.password} / '
                    '支付密码 ${MockCampusServer.payPassword} / 寝室 ${MockCampusServer.dorm}',
            style: TextStyle(
              fontSize: 11,
              color: SemColors.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
