import 'package:flutter/material.dart';

/// 退出登录确认弹窗：说清会清掉什么，返回 true 表示用户确认退出。
Future<bool> confirmLogout(BuildContext context, {required bool direct}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('退出登录'),
      content: Text(direct
          ? '将清除本机保存的校园密码并断开学校系统会话，返回浏览模式（不会进入登录页）；'
              '学号 / 学校信息保留，再次查询时需要重新输入密码。'
          : '将清除本机登录 token 与保存的密码，断开 VPN 隧道，返回浏览模式（不会进入登录页）；'
              '「记住密码并自动重登」也会一起关掉，下次登录需要重新输入密码。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
      ],
    ),
  );
  return ok == true;
}
