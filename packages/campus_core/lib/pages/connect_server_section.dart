import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';
import '../widgets/common.dart';
import 'connect_self_host_card.dart';
import 'login_page.dart';

/// 用空体登录请求探测服务器：401 / 422 都说明该地址上跑着同一套开放接口。
Future<String> probeServerEndpoint(String url) async {
  try {
    final resp = await http
        .post(
          Uri.parse('$url/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: '{}',
        )
        .timeout(const Duration(seconds: 15));
    final ok = [400, 401, 422].contains(resp.statusCode);
    return ok
        ? '连接成功：$url（HTTP ${resp.statusCode}，接口可用）'
        : '该地址返回 HTTP ${resp.statusCode}，可能不是同款开放接口服务';
  } catch (e) {
    return '连接失败：$e';
  }
}

/// 服务器模式段：服务器地址卡 + 登录状态卡 + 自建服务器指引。
class ConnectServerSection extends StatelessWidget {
  const ConnectServerSection({
    super.key,
    required this.server,
    required this.probing,
    required this.probe,
    required this.onProbe,
    required this.onSave,
    required this.demo,
    required this.loggedIn,
    required this.username,
    required this.serverUrl,
  });

  final TextEditingController server;

  /// 正在测试连接（按钮显示转圈）。
  final bool probing;

  /// 上一次测试连接的结果文案；null = 还没测过。
  final String? probe;
  final VoidCallback onProbe;

  /// 保存服务器设置（异步，供「保存并登录」等待）。
  final Future<void> Function() onSave;
  final bool demo;
  final bool loggedIn;
  final String? username;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '服务器地址',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 10),
              GlassField(
                label: 'IP 或域名（可带端口）',
                controller: server,
                keyboardType: TextInputType.url,
                hintText: '192.168.1.10:8000 / my.server.cn:8443',
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: probing ? null : onProbe,
                    child: probing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('测试连接'),
                  ),
                  OutlinedButton(
                    onPressed: () => server.clear(),
                    child: const Text('清空'),
                  ),
                  if (kDebugMode)
                    OutlinedButton(
                      onPressed: () {
                        server.text = AppState.localUrl;
                      },
                      child: const Text('本地调试'),
                    ),
                ],
              ),
              if (probe != null) ...[
                const SizedBox(height: 8),
                Text(
                  probe!,
                  style: TextStyle(
                    fontSize: 12,
                    color: SemColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child:
                        FilledButton(onPressed: onSave, child: const Text('保存')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      // 保存后再跳登录页；页面在跳转前可能已被销毁。
                      onPressed: () async {
                        await onSave();
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text('保存并登录'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Row(
            children: [
              Icon(
                demo
                    ? Icons.science_outlined
                    : (loggedIn
                        ? Icons.check_circle
                        : Icons.info_outline),
                color: demo
                    ? SemColors.accent
                    : (loggedIn
                        ? SemColors.success
                        : SemColors.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  demo
                      ? '当前为演示模式（本地假数据，不发起请求）'
                      : (loggedIn
                          ? '已登录：${username ?? ''} @ ${serverUrl.isEmpty ? '未填写地址' : serverUrl}'
                          : '该服务器未登录：登录后即可查询校园数据'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: SemColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const ConnectSelfHostCard(),
      ],
    );
  }
}
