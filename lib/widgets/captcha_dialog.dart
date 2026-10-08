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
/// 配了「AI 设置」时先让 AI 读图；识别失败、或上一次是「验证码错」（多半是 AI 认错字，
/// 换了新码值得再试一次）时继续让 AI 试，直到 [maxAiTries] 次；仍不行就弹手输框。
/// AI 只是省一步，永远不挡路。
void installDirectCaptchaPrompt() {
  CampusDirect.I.captchaPrompt = (image, hint, refresh, {error}) =>
      _serial(() => _aiThenManual(image, hint, refresh, error));
  ApiClient.I.captchaPrompt = (image, hint, refresh, {error}) =>
      _serial(() => _aiThenManual(image, hint, refresh, error));
}

/// 一次登录流程里最多让 AI 试几次（含首次）。AI 认错字时会换新码重来，
/// 给一次补救机会能把「认错就立刻要手输」的体验救回来；但不无限试——用户可能就想手输。
const int maxAiTries = 2;
int _aiTries = 0;

Future<String?> _aiThenManual(
  Uint8List image,
  String hint,
  Future<Uint8List> Function() refresh,
  String? error,
) async {
  await AiVision.I.load();
  final noError = error == null || error.isEmpty;
  if (noError) {
    _aiTries = 0; // 新的一轮登录：重新计数
  }
  // 上次是密码类错误说明验证码本来就是对的，别再折腾 AI；验证码错则值得再试（换了新码）
  final captchaWrong = error != null && error.contains('验证码');
  if (AiVision.I.available && _aiTries < maxAiTries && (noError || captchaWrong)) {
    _aiTries++;
    final text = await solveCaptcha(image);
    if (text != null && text.isNotEmpty) {
      debugPrint('[AI] 自动识别验证码（$hint，第 $_aiTries 次）：$text');
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
