import 'package:flutter/material.dart';

import 'app_state.dart';
import 'pages/home_page.dart';
import 'widgets/captcha_dialog.dart';
import 'widgets/common.dart';

void main() {
  // 直连模式的学校系统验证码输入弹窗（服务器模式用不到）
  installDirectCaptchaPrompt();
  runApp(const CampusApp());
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 与 anticraft.top 网站一致的 Corporate Clean 视觉令牌
    const accent = Color(0xFF2563eb); // --accent-1 blue-600
    const bg = Color(0xFFF8FAFC); // --bg-primary slate-50
    final scheme = ColorScheme.fromSeed(seedColor: accent).copyWith(
      primary: accent,
      secondary: const Color(0xFF0284C7), // --accent-2 sky-600
      error: const Color(0xFFDC2626), // --danger
      surface: Colors.white,
    );
    return MaterialApp(
      title: 'AntiSIT',
      navigatorKey: navKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE5E7EB)), // --border-color
          ),
          margin: const EdgeInsets.only(bottom: 16),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          scrolledUnderElevation: 0,
          centerTitle: true,
          foregroundColor: Color(0xFF111827), // --text-primary
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: accent.withValues(alpha: 0.10),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE5E7EB), thickness: 1, space: 1),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF4B5563),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
      ),
      home: const BootPage(),
    );
  }
}

/// 启动流：不强制登录——加载本地设置后直接进主页。
/// 有 token 直接用（401 时请求层自动 refresh/重登）；未登录由各页面的门控引导。
class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await AppState.I.load();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text('AntiSIT', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
