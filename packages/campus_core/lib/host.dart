import 'package:flutter/widgets.dart';

/// 宿主（App 包）注入给 core 的回调。
///
/// core 不能 import 宿主的页面（会形成包依赖环），所以「往上跳」的导航只能反向注入：
/// 宿主在 `main()` 里赋值，core 里的页面（登录页）只管调用。
Widget Function() hostShellBuilder = () => const SizedBox.shrink();
