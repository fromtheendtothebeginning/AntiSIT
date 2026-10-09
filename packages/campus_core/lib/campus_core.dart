/// campus_core —— 宿主与插件包之间的唯一契约层。
///
/// 插件包只依赖这个包（`campus_core: {path: ../campus_core}`），
/// 需要的服务、组件、插件接口都从这里取：
///
/// ```dart
/// import 'package:campus_core/campus_core.dart';
/// ```
///
/// 反向是禁止的：core 不认识任何插件包（那样 pub 会报循环依赖），
/// 需要「往上跳」的地方（如登录成功回主壳）由宿主注入回调，见 [hostShellBuilder]。
library;

export 'ai/ai_settings.dart';
export 'ai/ai_tasks.dart';
export 'ai/ai_vision.dart';
export 'api_client.dart';
export 'api_error.dart';
export 'app_state.dart';
export 'class_reminder_service.dart';
export 'demo_data.dart';
export 'direct/activities_util.dart';
export 'direct/campus_direct.dart';
export 'direct/crypto.dart';
export 'direct/epay.dart';
export 'direct/http_session.dart';
export 'direct/jwxt.dart';
export 'direct/mock_campus_server.dart';
export 'direct/mock_captcha.dart';
export 'direct/school.dart';
export 'direct/sm4.dart';
export 'direct/xg.dart';
export 'host.dart';
export 'json_num.dart';
export 'pages/connect_page.dart';
export 'pages/login_page.dart';
export 'plugins/plugin.dart';
export 'plugins/registry.dart';
export 'timetable_store.dart';
export 'widgets/balance_chart.dart';
export 'widgets/captcha_dialog.dart';
export 'widgets/common.dart';
