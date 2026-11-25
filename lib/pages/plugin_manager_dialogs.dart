import 'package:flutter/material.dart';

/// 连带停用确认弹窗：列出会跟着停掉的插件，返回 true 表示用户确认。
Future<bool> confirmCascadeDisable(
  BuildContext context, {
  required String pluginName,
  required List<String> goneNames,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('连带停用'),
      content: Text(
        '这些插件依赖「$pluginName」，停用它会把它们一起停掉：\n\n'
        '${goneNames.map((n) => '· $n').join('\n')}\n\n'
        '之后重新启用「$pluginName」不会自动把它们打开。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('一并停用'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 停用当前正在使用的 AI 提供商的确认弹窗，返回 true 表示用户确认。
Future<bool> confirmDisableActiveProvider(
  BuildContext context, {
  required String providerLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('停用正在使用的提供商'),
      content: Text(
        '「$providerLabel」是当前选中的 AI 提供商。停用后它不再出现在「AI 设置」里，'
        'AI 识别按未配置处理（验证码退回手动输入、校历识别入口消失）。\n\n'
        '已填的 Key 会留着，重新启用就能继续用；也可以在「AI 设置」里先换一家。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('停用'),
        ),
      ],
    ),
  );
  return ok == true;
}
