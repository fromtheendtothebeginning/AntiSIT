import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ai/ai_tasks.dart';
import '../ai/ai_vision.dart';
import '../api_client.dart';
import '../direct/campus_direct.dart';
import 'common.dart';

/// 弹窗串行队列：教务与学工可能同时要求登录，排队保证同一时刻只有一个弹窗，
/// 否则先弹的那个会被后弹的盖住，用户看着像「验证码弹窗停不下来」。
Future<void> _dialogQueue = Future.value();

Future<T> _serial<T>(Future<T> Function() task) {
  final r = _dialogQueue.then((_) => task());
  _dialogQueue = r.then((_) {}, onError: (_) {});
  return r;
}

/// 注入验证码输入弹窗（App 启动时调用一次）：直连模式本机登录学校系统用；
/// 服务器模式在自动识码走不通（未配识图模型等）回 need_captcha 时也用同一只弹窗。
/// 配了「AI 设置」时先让 AI 读图（首次弹出、且上次没有报错时才试），
/// 识别失败或有错误提示时回退手输——AI 只是省一步，永远不挡路。
void installDirectCaptchaPrompt() {
  CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) =>
      _serial(() => _aiThenManual(image, hint, refresh, error));
  ApiClient.I.captchaPrompt = (image, hint, refresh, {error}) =>
      _serial(() => _aiThenManual(image, hint, refresh, error));
}

Future<String?> _aiThenManual(
  Uint8List image,
  String hint,
  Future<Uint8List> Function() refresh,
  String? error,
) async {
  await AiVision.I.load();
  // 上一次已提示错误（多半是验证码错）时不再重复调 AI，直接让用户重输
  final firstTry = error == null || error.isEmpty;
  if (firstTry && AiVision.I.available) {
    final text = await solveCaptcha(image);
    if (text != null && text.isNotEmpty) {
      debugPrint('[AI] 自动识别验证码（$hint）：$text');
      return text;
    }
  }
  return _showCaptcha(image, hint, refresh, error);
}

Future<String?> _showCaptcha(
  Uint8List image,
  String hint,
  Future<Uint8List> Function() refresh,
  String? error,
) {
  final ctx = navKey.currentContext;
  if (ctx == null) return Future.value(null);
  return showDialog<String>(
    context: ctx,
    barrierDismissible: false,
    builder: (_) => CaptchaDialog(image: image, hint: hint, onRefresh: refresh, error: error),
  );
}

/// 直连模式的验证码输入框：学校系统登录验证码由用户手动输入。
class CaptchaDialog extends StatefulWidget {
  const CaptchaDialog({
    super.key,
    required this.image,
    required this.hint,
    required this.onRefresh,
    this.error,
  });

  final Uint8List image;
  final String hint;
  final Future<Uint8List> Function() onRefresh;

  /// 上一次提交失败的原因（如「验证码错误」），首次弹出为 null。
  final String? error;

  @override
  State<CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<CaptchaDialog> {
  final _ctrl = TextEditingController();
  late Uint8List _image = widget.image;
  bool _refreshing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final img = await widget.onRefresh();
      if (mounted) setState(() => _image = img);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.hint),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SemColors.dangerSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
              ),
              child: Text('上次提交失败：${widget.error}',
                  style: TextStyle(fontSize: 12.5, color: SemColors.danger, height: 1.5)),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                height: 52,
                constraints: const BoxConstraints(minWidth: 120),
                decoration: BoxDecoration(
                  color: SemColors.neutralSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SemColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_image, height: 52, fit: BoxFit.contain),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                tooltip: '换一张',
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlassField(
            label: '验证码',
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.verified_outlined),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          Text(
            '服务器模式配置识图模型后由 AI 自动识别；未配置或识别失败时，与直连模式一样需手动输入。',
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
