import 'package:flutter/material.dart';

import '../direct/campus_direct.dart';
import '../widgets/common.dart';
import 'connect_common.dart';

/// 直连模式的「校园凭据」卡（默认展开）：学号 / 密码 / 支付密码 / 寝室 / 姓名 / 年级。
class ConnectCredentialsCard extends StatefulWidget {
  const ConnectCredentialsCard({
    super.key,
    required this.sid,
    required this.pwd,
    required this.payPwd,
    required this.dormBuilding,
    required this.dormRoom,
    required this.realName,
    required this.grade,
    required this.testing,
    required this.probes,
    required this.onSave,
    required this.onTest,
  });

  final TextEditingController sid;
  final TextEditingController pwd;
  final TextEditingController payPwd;
  final TextEditingController dormBuilding;
  final TextEditingController dormRoom;
  final TextEditingController realName;
  final TextEditingController grade;

  /// 正在测试连接（按钮显示转圈）。
  final bool testing;

  /// 上一次测试结果；null = 还没测过。
  final List<ProbeResult>? probes;
  final VoidCallback onSave;
  final VoidCallback onTest;

  @override
  State<ConnectCredentialsCard> createState() => _ConnectCredentialsCardState();
}

class _ConnectCredentialsCardState extends State<ConnectCredentialsCard> {
  bool _open = true;
  bool _hidePwd = true;
  bool _hidePayPwd = true;

  @override
  Widget build(BuildContext context) {
    return ConnectCollapsibleCard(
      icon: Icons.badge_outlined,
      title: '校园凭据',
      open: _open,
      onToggle: () => setState(() => _open = !_open),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          GlassField(
            label: '学号',
            controller: widget.sid,
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
          const SizedBox(height: 10),
          GlassField(
            label: '统一身份认证密码',
            controller: widget.pwd,
            obscureText: _hidePwd,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidePwd = !_hidePwd),
              icon: Icon(
                _hidePwd
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GlassField(
            label: '校园卡支付密码',
            controller: widget.payPwd,
            obscureText: _hidePayPwd,
            prefixIcon: const Icon(Icons.credit_card_outlined),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidePayPwd = !_hidePayPwd),
              icon: Icon(
                _hidePayPwd
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 楼号和寝室号分开填，内部仍拼成校付宝要的「24号楼1016」。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GlassField(
                  label: '楼号',
                  controller: widget.dormBuilding,
                  prefixIcon: const Icon(Icons.apartment_outlined),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassField(
                  label: '寝室号',
                  controller: widget.dormRoom,
                  prefixIcon: const Icon(Icons.house_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassField(
            label: '姓名',
            controller: widget.realName,
            prefixIcon: const Icon(Icons.person_outline),
          ),
          const SizedBox(height: 10),
          GlassField(
            label: '年级',
            controller: widget.grade,
            prefixIcon: const Icon(Icons.school_outlined),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child:
                    FilledButton(onPressed: widget.onSave, child: const Text('保存')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.testing ? null : widget.onTest,
                  child: widget.testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('测试连接'),
                ),
              ),
            ],
          ),
          if (widget.probes != null) ...[
            const SizedBox(height: 10),
            for (final p in widget.probes!)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      p.ok ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: p.ok ? SemColors.success : SemColors.danger,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${p.name}：${p.detail}',
                        style: TextStyle(
                          fontSize: 12,
                          color: p.ok
                              ? SemColors.textSecondary
                              : SemColors.danger,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
