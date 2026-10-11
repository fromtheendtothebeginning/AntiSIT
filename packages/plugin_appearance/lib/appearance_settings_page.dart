import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 外观二级页：与外观有关的选项都收在这里——
/// 主题（主题插件单选）、深浅色（跟随系统 / 浅色 / 深色）、界面是否实时跟着滑块切换。
///
/// 深浅色滑块拖到中间时整站配色会在浅色板与深色板之间插值（见 [appearanceDarkness] /
/// [GlassPalette.lerp]）；「跟随滑块」开关控制的是**界面跟着滑块切换**这件事本身
/// （主界面底栏切页、连接设置那两套设置），关掉就回到「松手落位后才切」的旧行为。
class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  /// 深浅色滑块的连续位置（0=跟随系统 / 1=浅色 / 2=深色）：拖动时整站配色跟着插值。
  final ValueNotifier<double> _appearancePos = ValueNotifier<double>(1);

  @override
  void initState() {
    super.initState();
    _appearancePos.value = _appearanceIndex.toDouble();
    _appearancePos.addListener(_previewAppearance);
  }

  @override
  void dispose() {
    _appearancePos.removeListener(_previewAppearance);
    _appearancePos.dispose();
    AppState.I.setAppearancePreview(null); // 离开页面就别留着预览
    super.dispose();
  }

  int get _appearanceIndex => switch (AppState.I.themeMode) {
        ThemeMode.light => 1,
        ThemeMode.dark => 2,
        _ => 0,
      };

  /// 滑块每动一点就更新整站配色的预览（量化在 AppState 里做，避免每帧重建）。
  void _previewAppearance() {
    final systemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    AppState.I
        .setAppearancePreview(appearanceDarkness(_appearancePos.value, systemDark: systemDark));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListenableBuilder(
        listenable: Listenable.merge([st, PluginRegistry.I]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('主题也是插件：可在「我的 → 插件管理」里查看它们的来源',
                      style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
                  const SizedBox(height: 4),
                  const ThemePickerList(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('深浅色', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('拖动时整个界面的配色会跟着在浅色与深色之间渐变，松手落到所选那档。',
                      style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
                  const SizedBox(height: 12),
                  GlassTabs(
                    labels: const ['跟随系统', '浅色', '深色'],
                    index: _appearanceIndex,
                    position: _appearancePos,
                    onChanged: (i) => st.setThemeMode(switch (i) {
                      1 => ThemeMode.light,
                      2 => ThemeMode.dark,
                      _ => ThemeMode.system,
                    }),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile(
                secondary: const Icon(Icons.swipe_outlined),
                title: const Text('界面实时跟着滑块切换'),
                subtitle: const Text(
                    '打开：拖动滑块（或左右滑页面）时下方界面跟着实时滑动，拖过一半就换；\n'
                    '关闭：松手落位后才切换（旧行为，少一点重绘）。',
                    style: TextStyle(fontSize: 12, height: 1.5)),
                isThreeLine: true,
                value: st.followSlider,
                onChanged: (v) => st.setFollowSlider(v),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile(
                secondary: const Icon(Icons.keyboard_backspace_rounded),
                title: const Text('预测式返回动画'),
                subtitle: const Text('返回手势跟手预览上一层页面，松手前可反悔',
                    style: TextStyle(fontSize: 12)),
                value: st.predictiveBack,
                onChanged: (v) => st.setPredictiveBack(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
