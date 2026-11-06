import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';
import 'site_icon.dart';

/// 拓展卡片图标：`line:<name>` 镂空线性图标优先，其次是自定义的 emoji / 图片网址，
/// 再其次是网站图标（[SiteIcon]），都没有（或拿不到 / 本地压缩包）就用名称首字。
/// 尺寸与「工具」宫格一致：8 内边距的圆角色块 + 24 的图标。
///
/// 「拓展」页与「插件市场」页共用（市场里的条目也要按同一规格画）。
class ExtIcon extends StatelessWidget {
  const ExtIcon({super.key, required this.item, this.size = 24});

  final ExtensionItem item;
  final double size;

  /// 官方 / 投稿拓展用的镂空图标名 → Material Outlined 图标。
  ///
  /// 市场仓库的 `market_manifest.dart` 维护同一份白名单；新增时两边一起改，
  /// 否则市场会以「图标名不认识」拦下投稿。
  static const Map<String, IconData> lineIcons = {
    'extension': Icons.extension_outlined,
    'handyman': Icons.handyman_outlined,
    'grid_view': Icons.grid_view_outlined,
    'flag': Icons.flag_outlined,
    'sports_esports': Icons.sports_esports_outlined,
    'calculate': Icons.calculate_outlined,
    'menu_book': Icons.menu_book_outlined,
    'fitness_center': Icons.fitness_center_outlined,
    'schedule': Icons.schedule_outlined,
    'payments': Icons.payments_outlined,
    'school': Icons.school_outlined,
    'science': Icons.science_outlined,
    'terminal': Icons.terminal_outlined,
    'brush': Icons.brush_outlined,
    'music_note': Icons.music_note_outlined,
    'photo_camera': Icons.photo_camera_outlined,
    'place': Icons.place_outlined,
    'search': Icons.search_outlined,
    'settings': Icons.settings_outlined,
    'star': Icons.star_outlined,
    'favorite': Icons.favorite_outline,
    'home': Icons.home_outlined,
    'work': Icons.work_outline,
    'build': Icons.build_outlined,
    'code': Icons.code_outlined,
    'cloud': Icons.cloud_outlined,
    'chat': Icons.chat_outlined,
    'mail': Icons.mail_outline,
    'map': Icons.map_outlined,
    'book': Icons.book_outlined,
    'timer': Icons.timer_outlined,
    'wallet': Icons.wallet_outlined,
    'receipt_long': Icons.receipt_long_outlined,
    'event': Icons.event_outlined,
    'checklist': Icons.checklist_outlined,
    'insights': Icons.insights_outlined,
    'translate': Icons.translate_outlined,
    'qr_code': Icons.qr_code_2_outlined,
    'auto_awesome': Icons.auto_awesome_outlined,
  };

  /// `line:` 前缀的图标名（其它写法返回 null）。
  static IconData? lineIcon(String icon) {
    if (!icon.startsWith('line:')) return null;
    return lineIcons[icon.substring(5)] ?? Icons.extension_outlined;
  }

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

    // 官方 / 投稿拓展：镂空线性图标
    final line = lineIcon(item.icon);
    if (line != null) {
      return box(Icon(line, size: size, color: SemColors.accent));
    }
    // 自己填的文字 / emoji
    if (item.icon.isNotEmpty && !item.iconIsImage) {
      return box(Text(item.icon, style: TextStyle(fontSize: size * 0.83)));
    }
    // 自己填的图片网址
    if (item.iconIsImage) {
      return box(Image.network(item.icon,
          width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => letter));
    }
    // Cordis 拓展没有站点：没配图标时统一给镂空图标，不显示首字
    if (item.bundled) {
      return box(Icon(Icons.extension_outlined, size: size, color: SemColors.accent));
    }
    // 本地压缩包没有站点 / 网址不合法：直接用首字
    final bool httpUrl = item.url.startsWith('http://') || item.url.startsWith('https://');
    if (!httpUrl) return box(letter);
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
