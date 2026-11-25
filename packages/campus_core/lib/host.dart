import 'package:flutter/widgets.dart';

/// 宿主导航壳构建器：core 不能 import 宿主页面，只能由宿主在 `main()` 里注入。
Widget Function() hostShellBuilder = () => const SizedBox.shrink();

/// 「插件管理」页构建器：宿主注入，供风险提醒等插件页跳转过去。
Widget Function() hostPluginManagerBuilder = () => const SizedBox.shrink();
