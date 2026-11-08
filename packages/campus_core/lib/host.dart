import 'package:flutter/widgets.dart';

/// 宿主（App 包）注入给 core 的回调。
///
/// core 不能 import 宿主的页面（会形成包依赖环），所以「往上跳」的导航只能反向注入：
/// 宿主在 `main()` 里赋值，core 里的页面（登录页）只管调用。
Widget Function() hostShellBuilder = () => const SizedBox.shrink();

/// 「插件管理」页的构建器（同样是宿主注入）：风险提醒拦下付款码 / 充值时，
/// 引导按钮要跳过去让用户关掉它，而那个页面在宿主包里——插件包只认识 campus_core。
Widget Function() hostPluginManagerBuilder = () => const SizedBox.shrink();
