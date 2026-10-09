import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 主题选择列表（单选）。「我的 → 外观」的弹层与插件管理页共用这一份实现。
class ThemePickerList extends StatelessWidget {
  const ThemePickerList({super.key, this.showHeader = false});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final registry = PluginRegistry.I;
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final active = registry.theme.id;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('主题',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: SemColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('主题也是插件：可在「我的 → 插件管理」里查看它们的来源',
                        style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
                  ],
                ),
              ),
            for (final t in registry.themes)
              ListTile(
                leading: _Swatch(theme: t),
                title: Text(t.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(t.description, style: const TextStyle(fontSize: 12)),
                trailing: Icon(
                  t.id == active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20,
                  color: t.id == active ? SemColors.accent : SemColors.textMuted,
                ),
                onTap: () => registry.setTheme(t.id),
              ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
}

/// 打开主题选择弹层。
Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SemColors.menuBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const SafeArea(
      child: SingleChildScrollView(child: ThemePickerList(showHeader: true)),
    ),
  );
}

/// 色板预览：底色 + 面底 + 强调色三层，一眼看出主题的气质。
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme});

  final ThemePlugin theme;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette(Theme.of(context).brightness);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SemColors.border),
      ),
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: p.accent, width: 2),
          ),
        ),
      ),
    );
  }
}
