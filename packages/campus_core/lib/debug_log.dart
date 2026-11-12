import 'package:flutter/foundation.dart';

/// 诊断日志：只在 debug 构建输出。
///
/// `debugPrint` 本身在 release 里不会被剥离（只是节流），登录失败页片段、验证码识别结果
/// 这类内容不该进生产 logcat。统一走这里后，`kDebugMode` 是编译期常量，release 的
/// AOT 会把整段调用折叠掉。
void debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}
