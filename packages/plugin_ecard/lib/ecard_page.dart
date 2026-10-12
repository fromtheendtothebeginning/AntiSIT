import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:campus_core/campus_core.dart';

/// 校园码刷新间隔的上限（秒）：服务端 `refresh` 标的是**码的有效期**（现在回 55），
/// 照它倒计时意味着屏幕上的码最长 52 秒才换一张——扫码慢一点、截图转发就可能扫到
/// 快过期的码。客户端最多 [ecardMaxRefreshSeconds] 秒就重取一次。
const int ecardMaxRefreshSeconds = 30;

/// 校园码的刷新倒计时（秒）：取 `min(服务端 refresh, 30)`——仍然尊重「有效期更短」的
/// 服务端（比如某校只给 20 秒），再提前 3 秒换码，免得扫码那一刻手里那张正好过期。
int ecardCountdownSeconds(int? fromServer) {
  final refresh = math.min(fromServer ?? ecardMaxRefreshSeconds, ecardMaxRefreshSeconds);
  final left = refresh - 3;
  return left < 5 ? 5 : left;
}

/// 校园码：复刻网站「校园卡动态码」排版
/// （绿徽章 + 220px 二维码 + 余额/倒计时/立即刷新 + 防转发提示），亮码期间屏幕常亮。
class EcardPage extends StatefulWidget {
  const EcardPage({super.key, this.activeTab, this.myTab = 1});

  /// 主页当前 Tab（IndexStack 常驻，仅在本页可见时才自动刷新）。
  final ValueListenable<int>? activeTab;
  final int myTab;

  @override
  State<EcardPage> createState() => _EcardPageState();
}

class _EcardPageState extends State<EcardPage> {
  Map<String, dynamic>? _data;
  String? _err;
  bool _loading = false;
  int _countdown = 0;
  Timer? _ticker;
  bool _active = true;

  /// 风险提醒（默认开启）拦在付款码前面：开着就**不请求**、不显示码，原位给引导
  /// （引导里可跳插件管理关掉它）。没装 / 被停用时取不到能力 = 没有这道闸。
  RiskNoticeCapability? get _risk =>
      PluginRegistry.I.capability<RiskNoticeCapability>(PluginIds.risk);
  bool get _blocked => _risk != null;

  /// 上一次看到的拦截状态：注册表一变就回调，只在「拦 ↔ 放行」翻转时动手。
  bool _blockedSeen = false;

  @override
  void initState() {
    super.initState();
    widget.activeTab?.addListener(_onTabChanged);
    PluginRegistry.I.addListener(_onRegistryChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _active = (widget.activeTab?.value ?? widget.myTab) == widget.myTab;
    _blockedSeen = _blocked;
    if (AppState.I.loggedIn && _active && !_blocked) {
      WakelockPlus.enable();
      _fetch();
    }
  }

  /// 风险提醒被关掉 / 开回来：立刻恢复取码或停下刷新（用户从管理页关完返回就该生效）。
  void _onRegistryChanged() {
    if (!mounted || _blocked == _blockedSeen) return;
    _blockedSeen = _blocked;
    if (_blocked) {
      WakelockPlus.disable(); // 不再亮着屏等一张不会显示的码
    } else if (_active && !_loading) {
      _fetch();
    }
    setState(() {});
  }

  void _onTabChanged() {
    final v = widget.activeTab?.value ?? widget.myTab;
    _active = v == widget.myTab;
    if (_active && !_blocked && _countdown <= 0 && !_loading) _fetch();
    if (mounted) setState(() {});
  }

  void _tick() {
    if (_blocked || !_active || _loading) return;
    if (_countdown > 0) {
      if (mounted) setState(() => _countdown--);
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    if (_loading) return;
    _loading = true;
    await WakelockPlus.enable();
    if (mounted) setState(() {});
    try {
      final r = await ApiClient.I.ecard();
      _data = r['data'] as Map<String, dynamic>?;
      _err = null;
      _countdown = ecardCountdownSeconds(asInt(_data?['refresh']));
    } catch (e) {
      _err = e is ApiError ? e.message : '加载失败';
      _countdown = 10;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.activeTab?.removeListener(_onTabChanged);
    PluginRegistry.I.removeListener(_onRegistryChanged);
    _ticker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  /// 风险提醒开着时的卡片：二维码区域换成引导，这一页**不请求**任何付款码数据。
  Widget _blockedCard() => AppCard(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Capsule('校园卡动态码', color: SemColors.textMuted),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 220,
              height: 220,
              child: Center(child: _risk!.blockedNotice(context, feature: '校园码付款码')),
            ),
            const SizedBox(height: 10),
            Text(
              '关闭「风险提醒」后自动恢复；此期间本页不会请求付款码。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: SemColors.textMuted),
            ),
          ],
        ),
      );

  Widget _qr() {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final img = d['image'] as String?;
    final code = (d['code'] as String?) ?? '';
    if (img != null && img.isNotEmpty) {
      try {
        // 兼容 dataURI 前缀（data:image/png;base64,xxx）
        final b64 = img.contains(',') ? img.split(',').last : img;
        final bytes = base64Decode(b64);
        if (bytes.length > 64) {
          return Image.memory(bytes, gaplessPlayback: true, fit: BoxFit.contain);
        }
      } catch (_) {}
    }
    if (code.isNotEmpty) {
      // 透明底落在下方 _qrPlate 上（深色主题才需要白底，浅色直接压在浅色卡面上）
      return QrImageView(data: code, size: 220, backgroundColor: Colors.transparent);
    }
    return const SizedBox(width: 220, height: 220, child: Center(child: Text('二维码获取失败')));
  }

  /// 二维码底板：浅色主题**不画白底**（否则玻璃卡上会露出一块白色方块），
  /// 深色主题才给一块圆角白底——深色卡面上深色模块无法辨认，必须垫亮底才能扫。
  Widget _qrPlate(Widget child) => QrPlate(child: child);

  @override
  Widget build(BuildContext context) {
    final balance = asDouble(_data?['card_balance']);
    return Scaffold(
      appBar: AppBar(title: const Text('校园码')),
      body: LoginGate(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                if (_blocked)
                  _blockedCard()
                else if (_err != null && _data == null) ...[
                  Icon(Icons.error_outline, size: 44, color: SemColors.danger),
                  const SizedBox(height: 10),
                  Text(_err!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.tonal(onPressed: _fetch, child: const Text('重试')),
                ] else
                  AppCard(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: Capsule('校园卡动态码', color: SemColors.success),
                        ),
                        const SizedBox(height: 14),
                        if (_data == null)
                          const SizedBox(
                            width: 220,
                            height: 220,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          _qrPlate(_qr()),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('卡余额 ', style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
                            Text(
                              balance == null ? '—' : '¥${balance.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600, color: SemColors.textPrimary),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              _loading ? '刷新中…' : '$_countdown 秒后自动刷新',
                              style: TextStyle(fontSize: 12, color: SemColors.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _loading ? null : _fetch,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(color: SemColors.border),
                            foregroundColor: SemColors.textSecondary,
                          ),
                          child: Text(_loading ? '刷新中…' : '立即刷新'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '动态码仅供本人付款使用，请勿截图转发',
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
