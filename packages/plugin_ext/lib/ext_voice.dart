import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'ext_voice_channel.dart';

/// 语音输入通道（`voice.*`）：给拓展页一个「按一下说话、转成文字填进输入框」的能力。
///
/// 只回传文字：录音与识别都在系统识别服务里完成，**不落盘、不上传**，也不经过
/// App 的业务层。增量结果通过 `antiSIT.on('voice.result')` 推回网页。
class ExtVoiceChannel {
  ExtVoiceChannel({required this.events});

  /// 内核 → 网页的下行通道；页面关掉后返回 null。
  final WebBridgeEventSink? Function() events;

  final ExtVoiceChannelImpl _impl = ExtVoiceChannelImpl();

  /// `voice.start` → true 表示已开始录音识别；false = 没权限 / 没识别服务，
  /// 调用方自己提示（错误详情走 `voice.error` 事件）。
  Future<Object?> start(Object? args) async {
    final sink = events();
    if (sink == null) throw ArgumentError('voice.start 只能用在内核页面里');
    final ok = await _impl.start(
      onResult: (text, isFinal) => sink.emit('voice.result', {
        'text': text,
        'isFinal': isFinal,
      }),
      onError: (message) => sink.emit('voice.error', {'message': message}),
    );
    return ok;
  }

  Future<Object?> stop(Object? args) async {
    await _impl.stop();
    return true;
  }

  Future<Object?> cancel(Object? args) async {
    await _impl.cancel();
    return true;
  }

  /// 宿主是否支持语音输入（桌面 / 测试环境返回 false，网页据此隐藏麦克风）。
  Future<Object?> available(Object? args) async {
    try {
      return await ExtVoiceChannelImpl.probe();
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
