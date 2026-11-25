import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:campus_core/campus_core.dart';

/// 校园码刷新间隔上限（秒）；服务端 `refresh` 标的是码的有效期，客户端按配置间隔更频繁地重取。
const int ecardMaxRefreshSeconds = 30;

/// 刷新倒计时：取配置间隔与服务端有效期的较小值，服务端更短时再提前 3 秒换码。
int ecardCountdownSeconds(int? fromServer, {int interval = 10}) {
  final server = fromServer ?? interval;
  final base = math.min(interval, server);
  final left = server < interval ? base - 3 : base;
  return left < 5 ? 5 : left;
}

/// 校园码：复刻网站「校园卡动态码」排版，亮码期间屏幕常亮。
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

  /// 风险提醒（默认开启）拦在付款码前：开着就不请求、不显示码，原位给引导。
  RiskNoticeCapability? get _risk =>
      PluginRegistry.I.capability<RiskNoticeCapability>(PluginIds.risk);
  bool get _blocked => _risk != null;

  /// 上次看到的拦截状态，只在「拦 ↔ 放行」翻转时动手。
  bool _blockedSeen = false;

  @override
  void initState() {
    super.initState();
    widget.activeTab?.addListener(_onTabChanged);
    PluginRegistry.I.addListener(_onRegistryChanged);
    AppState.I.addListener(_onSettingsChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _active = (widget.activeTab?.value ?? widget.myTab) == widget.myTab;
    _blockedSeen = _blocked;
    if (AppState.I.loggedIn && _active && !_blocked) {
      WakelockPlus.enable();
      _fetch();
    }
  }

  /// 风险提醒被关掉 / 开回来：立刻恢复取码或停止刷新。
  void _onRegistryChanged() {
    if (!mounted || _blocked == _blockedSeen) return;
    _blockedSeen = _blocked;
    if (_blocked) {
      WakelockPlus.disable();
    } else if (_active && !_loading) {
      _fetch();
    }
    setState(() {});
  }

  /// 「配置」里改了换码间隔：倒计时立刻按新间隔收敛，不等下一轮取码。
  void _onSettingsChanged() {
    if (!mounted || _data == null || _loading) return;
    final interval = AppState.I.ecardRefreshSeconds;
    if (_countdown > interval) {
      setState(
        () => _countdown = ecardCountdownSeconds(
          asInt(_data?['refresh']),
          interval: interval,
        ),
      );
    }
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
      _countdown = ecardCountdownSeconds(
        asInt(_data?['refresh']),
        interval: AppState.I.ecardRefreshSeconds,
      );
      // 桌面卡片只同步余额，动态码不进桌面。
      final widget = PluginRegistry.I.capability<HomeWidgetCapability>(
        PluginIds.homeWidget,
      );
      final balance = asDouble(_data?['card_balance']);
      if (widget != null && balance != null) {
        unawaited(widget.syncEcard(balance: balance.toStringAsFixed(2)));
      }
    } catch (e) {
      _err = e is ApiError ? e.message : e.toString();
      _countdown = AppState.I.ecardRefreshSeconds;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.activeTab?.removeListener(_onTabChanged);
    PluginRegistry.I.removeListener(_onRegistryChanged);
    AppState.I.removeListener(_onSettingsChanged);
    _ticker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  /// 拦截态卡片：二维码区换成引导，本页不请求任何付款码数据。
  Widget _blockedCard() => AppCard(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Capsule('校园卡动态码', color: SemColors.textMuted),
            ),
            const SizedBox(height: 14),
            // 引导占二维码原位：至少 220×220，内容更高时让框长高，不裁不溢出。
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, minHeight: 220),
              child: Center(
                child: _risk!.blockedNotice(context, feature: '校园码付款码'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '本组件停用后，受拦截行为即行恢复；本组件启用期间，本应用不请求付款码。',
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
        // 兼容 dataURI 前缀（data:image/png;base64,xxx）。
        final b64 = img.contains(',') ? img.split(',').last : img;
        final bytes = base64Decode(b64);
        if (bytes.length > 64) {
          return Image.memory(
            bytes,
            gaplessPlayback: true,
            fit: BoxFit.contain,
          );
        }
      } catch (_) {}
    }
    if (code.isNotEmpty) {
      // 透明底交给下方 _qrPlate。
      return QrImageView(
        data: code,
        size: 220,
        backgroundColor: Colors.transparent,
      );
    }
    return const SizedBox(
      width: 220,
      height: 220,
      child: Center(child: Text('二维码获取失败')),
    );
  }

  /// 二维码底板：浅色不画白底，深色垫圆角白底（否则深色模块无法辨认）。
  Widget _qrPlate(Widget child) => QrPlate(child: child);

  @override
  Widget build(BuildContext context) {
    // 整页监听 AppState：悬浮玻璃顶栏开关改完要连 Scaffold 一起重建。
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 先算顶栏留白：body 里的 MediaQuery 已扣掉状态栏。
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('校园码')),
          body: GlassFadedBody(
            barHeight: topInset,
            child: LoginGate(
            child: Center(
              child: SingleChildScrollView(
                // 顶部让出悬浮顶栏，底部让出玻璃浮层底栏。
                padding: EdgeInsets.fromLTRB(
                  20,
                  20 + topInset,
                  20,
                  20 + MediaQuery.paddingOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      // 拦截 / 失败 / 正常三张卡片切换走统一高度过渡：顶部锚定，内容不上下漂移。
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _blocked
                            ? _blockedCard()
                            : (_err != null && _data == null
                                ? _errorCard()
                                : _codeCard()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  /// 正常态：动态码 + 余额 + 倒计时 + 立即刷新。
  Widget _codeCard() {
    final balance = asDouble(_data?['card_balance']);
    return AppCard(
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
              Text(
                '卡余额 ',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted),
              ),
              Text(
                balance == null ? '—' : '¥${balance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: SemColors.textPrimary,
                ),
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
    );
  }

  /// 取码失败且还没有任何数据时的兜底：错误提示 + 重试。
  Widget _errorCard() => Column(
        children: [
          Icon(Icons.error_outline, size: 44, color: SemColors.danger),
          const SizedBox(height: 10),
          Text(_err!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: _fetch, child: const Text('重试')),
        ],
      );
}
