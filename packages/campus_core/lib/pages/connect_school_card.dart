import 'package:flutter/material.dart';

import '../direct/school.dart';
import '../widgets/common.dart';
import 'connect_common.dart';

/// 直连模式的「学校信息」卡（默认收起）：当前学校、四套系统地址与高级选项。
class ConnectSchoolCard extends StatefulWidget {
  const ConnectSchoolCard({
    super.key,
    required this.schools,
    required this.school,
    required this.name,
    required this.authBase,
    required this.jwxtBase,
    required this.xgBase,
    required this.ecardBase,
    required this.aesKey,
    required this.allowSelfSigned,
    required this.onSelfSignedChanged,
    required this.onAdd,
    required this.onRemove,
    required this.onPick,
  });

  final List<SchoolProfile> schools;
  final SchoolProfile school;
  final TextEditingController name;
  final TextEditingController authBase;
  final TextEditingController jwxtBase;
  final TextEditingController xgBase;
  final TextEditingController ecardBase;
  final TextEditingController aesKey;
  final bool allowSelfSigned;
  final ValueChanged<bool> onSelfSignedChanged;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// 切换到另一所学校档案（由页面落实并刷新表单）。
  final Future<void> Function(SchoolProfile) onPick;

  @override
  State<ConnectSchoolCard> createState() => _ConnectSchoolCardState();
}

class _ConnectSchoolCardState extends State<ConnectSchoolCard> {
  bool _open = false;

  Widget _addrField(TextEditingController c, String label) =>
      GlassField(label: label, controller: c, keyboardType: TextInputType.url);

  @override
  Widget build(BuildContext context) {
    return ConnectCollapsibleCard(
      icon: Icons.dns_outlined,
      title: '学校信息',
      open: _open,
      onToggle: () => setState(() => _open = !_open),
      actions: [
        TextButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加', style: TextStyle(fontSize: 13)),
        ),
        if (widget.schools.length > 1)
          TextButton.icon(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除', style: TextStyle(fontSize: 13)),
          ),
      ],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          GlassDropdown<String>(
            label: '当前学校',
            value: widget.school.name,
            items: [
              for (final s in widget.schools)
                DropdownMenuItem(value: s.name, child: Text(s.name)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              final s = widget.schools.firstWhere((e) => e.name == v);
              await widget.onPick(s);
            },
          ),
          const SizedBox(height: 12),
          GlassField(label: '学校名称', controller: widget.name),
          const SizedBox(height: 10),
          _addrField(widget.jwxtBase, '教务系统'),
          const SizedBox(height: 10),
          _addrField(widget.xgBase, '学工系统'),
          const SizedBox(height: 10),
          _addrField(widget.authBase, '统一身份认证'),
          const SizedBox(height: 10),
          _addrField(widget.ecardBase, '校园卡'),
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text('高级', style: TextStyle(fontSize: 13.5)),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '允许学校系统使用自签证书',
                  style: TextStyle(fontSize: 13.5),
                ),
                subtitle: const Text(
                  '默认关闭：证书校验失败会直接断开，避免校园网里用假证书替换登录页。'
                  '仅当学校系统确实使用自签证书时开启；开启会降低登录密码的抗中间人能力。',
                  style: TextStyle(fontSize: 11.5, height: 1.5),
                ),
                value: widget.allowSelfSigned,
                onChanged: (v) => widget.onSelfSignedChanged(v),
              ),
              GlassField(label: '响应解密密钥', controller: widget.aesKey),
            ],
          ),
        ],
      ),
    );
  }
}
