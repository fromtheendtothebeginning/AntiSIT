import 'package:flutter/services.dart';

/// 系统语音识别（`antisit/voice`）的 Dart 侧封装。
///
/// 为什么用系统识别而不是接一家云转写：录音不落盘、不出本机（系统识别器多半
/// 在本机跑），也不额外产生费用与隐私条款。代价是不适合长段口述（系统限制约
/// 一分钟），所以只做「输入框旁边的麦克风」。
///
/// 原生侧是 `VoiceInputBridge.kt`：Dart 只发 start / stop / cancel / available，
/// 识别结果是原生主动回传的（异步流式，没法用一个请求-响应拿回整段文本）。
///
/// **同一时刻只有一个识别在跑**：通道的 method handler 是进程级的，所以用
/// [_owner] 记住是谁点开的，原生回调只回给它（两个拓展页同时开着时不会串台）。
class ExtVoiceChannelImpl {
  static const _channel = MethodChannel('antisit/voice');

  /// 谁在录（进程级唯一）。
  static ExtVoiceChannelImpl? _owner;
  static bool _handlerReady = false;

  void Function(String text, bool isFinal)? _onResult;
  void Function(String message)? _onError;
  bool _listening = false;

  bool get listening => _listening;

  /// 宿主有没有可用的识别服务（没有的话网页干脆不显示麦克风）。
  static Future<bool> probe() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<Object?> _dispatch(MethodCall call) async {
    // 只回给发起的那一个：别的页面即使还挂着监听也不该收到。
    final owner = _owner;
    if (owner == null) return null;
    return owner._handleNative(call);
  }

  static void _ensureHandler() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler(_dispatch);
  }

  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
  }) async {
    _ensureHandler();
    // 上一次还没停就再点：先取消，别让两轮抢同一个识别器
    if (_owner != null && _owner != this) {
      await _owner!.cancel();
    }
    _owner = this;
    _onResult = onResult;
    _onError = onError;
    try {
      final ok = await _channel.invokeMethod<bool>('start');
      _listening = ok ?? false;
      if (!_listening) {
        _onResult = null;
        _onError = null;
        if (_owner == this) _owner = null;
      }
      return _listening;
    } on PlatformException catch (e) {
      _clear();
      onError?.call(e.message ?? '语音识别启动失败');
      return false;
    } on MissingPluginException {
      _clear();
      onError?.call('当前平台不支持语音输入');
      return false;
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> cancel() async {
    if (this == _owner) _owner = null;
    _clear();
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  void _clear() {
    _listening = false;
    _onResult = null;
    _onError = null;
  }

  Future<Object?> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'result':
        final args = call.arguments is Map ? call.arguments as Map : const {};
        final text = '${args['text'] ?? ''}';
        final isFinal = args['isFinal'] == true;
        if (isFinal) {
          _listening = false;
          if (_owner == this) _owner = null;
        }
        _onResult?.call(text, isFinal);
        return true;
      case 'error':
        _listening = false;
        if (_owner == this) _owner = null;
        _onError?.call('${call.arguments ?? '语音识别出错'}');
        return true;
      case 'end':
        _listening = false;
        if (_owner == this) _owner = null;
        return true;
    }
    return null;
  }
}
