import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';
import 'site_icon.dart';

/// 拓展卡片图标：自定义的 emoji / 图片网址优先，其次是网站图标（[SiteIcon]），
/// 都没有（或拿不到 / 本地压缩包）就用名称首字。
/// 尺寸与「工具」宫格一致：8 内边距的圆角色块 + 24 的图标。
///
/// 「拓展」页与「插件市场」页共用（市场里的条目也要按同一规格画）。
class ExtIcon extends StatelessWidget {
  const ExtIcon({super.key, required this.item, this.size = 24});

  final ExtensionItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget box(Widget child) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SemColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(width: size, height: size, child: Center(child: child)),
        );

    final letter = Text(
      item.name.isEmpty ? '?' : item.name.characters.first.toUpperCase(),
      style: TextStyle(
          fontSize: size * 0.67, fontWeight: FontWeight.bold, color: SemColors.accent),
    );

    // 自己填的文字 / emoji
    if (item.icon.isNotEmpty && !item.iconIsImage) {
      return box(Text(item.icon, style: TextStyle(fontSize: size * 0.83)));
    }
    // 自己填的图片网址
    if (item.iconIsImage) {
      return box(Image.network(item.icon,
          width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => letter));
    }
    // 本地压缩包没有站点：直接用首字
    if (item.bundled) return box(letter);
    // 网站图标：抓到之前 / 抓不到都先显示首字（拿到后自动换成图标）
    return box(FutureBuilder<Uint8List?>(
      future: SiteIcon.loader(item.url),
      builder: (_, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return letter;
        return Image.memory(bytes,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => letter);
      },
    ));
  }
}
