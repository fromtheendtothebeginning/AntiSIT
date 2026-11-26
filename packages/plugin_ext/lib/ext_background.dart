/// 拓展后台保活：前台服务 + 常驻通知，让插件页退到后台后继续跑自己的定时器（只支持 Android）。
///
/// 它不执行隐藏页面、不代替插件发请求；关掉拓展页或点通知回 App 即可停止。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExtBackgroundKeepAlive {
  static const MethodChannel _channel = MethodChannel('antisit/ext_background');

  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> start({
    required String title,
    required String text,
  }) async {
    if (!supported) {
      throw UnsupportedError('后台保活目前只支持 Android');
    }
    final ok = await _channel.invokeMethod<bool>('start', {
      'title': title,
      'text': text,
    });
    return ok ?? false;
  }

  static Future<void> stop() async {
    if (!supported) return;
    await _channel.invokeMethod<bool>('stop');
  }
}
