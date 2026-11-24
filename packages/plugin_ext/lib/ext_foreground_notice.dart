/// 拓展通知的「前台兜底」：App 开着的时候，用页面内的横幅保证提醒看得见。
///
/// 为什么非做不可：Android 会**压掉应用自己在前台时发的横幅通知**（heads-up）——
/// 通知照样进通知栏，但屏幕上不弹。于是就成了「退到后台能收到、正看着 App 却什么都
/// 看不到」，用户报的正是这个。
///
/// 分工：**前台 App 内横幅**（这里）、**后台 / 退出靠系统通知**（[ExtNotificationService]）。
/// 系统通知在前台也照发（静音），通知栏里留一条档，用户回头还能翻到。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 拓展提醒的前台横幅：全局只有一份，同一条（扩展 id + key）覆盖而不是叠一摞。
class ExtForegroundNotice with WidgetsBindingObserver {
  ExtForegroundNotice._();

  static final ExtForegroundNotice I = ExtForegroundNotice._();

  /// 横幅默认停留多久（到点自己收起；点一下也会收起）。
  static const Duration defaultDuration = Duration(seconds: 6);

  /// 同时最多挂几条（插件一次弹一堆时只留最新的几条，别把屏幕糊满）。
  static const int maxVisible = 3;

  AppLifecycleState _state = AppLifecycleState.resumed;
  bool _attached = false;

  /// 正在显示的横幅，**按弹出的先后**（先进先出，超量时先撤最早的）。
  final List<_BannerHandle> _live = <_BannerHandle>[];

  /// 去重表：同一条（拓展 id + key）再弹时覆盖，而不是叠一摞。
  final Map<String, _BannerHandle> _byKey = <String, _BannerHandle>{};

  /// 接上生命周期。**首次用到时才挂**，不给启动加负担。
  void attach() {
    if (_attached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _state = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
      _attached = true;
    } catch (_) {
      // 测试 / 没有 binding：当作前台，行为退化但不会崩
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
    // 退到后台：页面上挂着横幅没有意义（用户也看不见），收掉交给系统通知
    if (state != AppLifecycleState.resumed) dismissAll();
  }

  /// App 是否在前台（横幅只在此时有意义）。
  bool get inForeground => _state == AppLifecycleState.resumed;

  /// 弹一条横幅。返回 false = 现在弹不了（不在前台 / 没有可用的 overlay），
  /// 调用方应该走系统通知那条路。
  bool show({
    required String extId,
    required String title,
    String? body,
    String? key,
    String? source,
    Duration duration = defaultDuration,
  }) {
    attach();
    if (!inForeground) return false;
    final overlay = navKey.currentState?.overlay;
    if (overlay == null) return false;

    final dedupe = (key == null || key.isEmpty) ? null : '$extId|$key';
    if (dedupe != null) {
      final previous = _byKey.remove(dedupe);
      if (previous != null) {
        _live.remove(previous);
        previous.close();
      }
    }
    _trimToLimit();

    final handle = _BannerHandle._(this, overlay, dedupe, duration);
    _live.add(handle);
    if (dedupe != null) _byKey[dedupe] = handle;
    handle._present(_BannerContent(
      title: title,
      body: body,
      source: source,
      onTap: handle.close,
    ));
    return true;
  }

  /// 收掉全部横幅（退到后台时用）。
  ///
  /// 这里**不走收起动画**：App 已经不在前台，动画 ticker 会被系统一起停掉，
  /// 等动画结束等于把 OverlayEntry 永久挂在树上（回到前台时又突然冒出来一条）。
  void dismissAll() {
    for (final handle in _live.reversed.toList()) {
      handle.close(animated: false);
    }
    _live.clear();
    _byKey.clear();
  }

  /// 超过 [maxVisible] 时先撤最早的那条。
  ///
  /// 必须先**同步**从列表里摘掉再 close：close 的移除动作在微任务里做，
  /// 在这里等它会把 while 变成死循环（列表长度一直不变）。
  void _trimToLimit() {
    while (_live.length >= maxVisible) {
      final oldest = _live.first;
      _detach(oldest);
      oldest.close();
    }
  }

  /// 从登记表里摘掉（同步）。之后再走 close 的动画移除，两边互不依赖。
  void _detach(_BannerHandle handle) {
    _live.remove(handle);
    final key = handle.dedupeKey;
    if (key != null && identical(_byKey[key], handle)) _byKey.remove(key);
  }

  void _forget(_BannerHandle handle) => _detach(handle);

  /// 测试用：把生命周期状态复位到前台。
  @visibleForTesting
  void debugReset() {
    _state = AppLifecycleState.resumed;
    dismissAll();
  }
}

/// 一条横幅的句柄：管 OverlayEntry 的插入 / 动画收起 / 到点自删。
class _BannerHandle {
  _BannerHandle._(this._owner, this._overlay, this.dedupeKey, this.duration);

  final ExtForegroundNotice _owner;
  final OverlayState _overlay;
  final String? dedupeKey;
  final Duration duration;

  final GlobalKey<_BannerShellState> _key = GlobalKey<_BannerShellState>();
  OverlayEntry? _entry;
  Timer? _timer;
  bool _closing = false;

  void _present(Widget content) {
    final entry = OverlayEntry(
      builder: (_) => _BannerShell(key: _key, child: content),
    );
    _entry = entry;
    _overlay.insert(entry);
    _timer = Timer(duration, close);
  }

  /// [animated] = false 直接摘掉（退到后台 / 页面销毁时用，等不到动画）。
  void close({bool animated = true}) {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _timer = null;
    if (!animated) {
      _remove();
      return;
    }
    final state = _key.currentState;
    unawaited(() async {
      try {
        if (state != null) await state.hide();
      } catch (_) {
        // 动画被打断（页面销毁）也照样删掉，别留一个透明壳子盖在屏幕上
      }
      _remove();
    }());
  }

  void _remove() {
    try {
      _entry?.remove();
    } catch (_) {
      // overlay 已经销毁
    }
    _entry = null;
    _owner._forget(this);
  }
}

/// 横幅外壳：从顶部滑入 / 淡出。
class _BannerShell extends StatefulWidget {
  const _BannerShell({super.key, required this.child});

  final Widget child;

  @override
  State<_BannerShell> createState() => _BannerShellState();
}

class _BannerShellState extends State<_BannerShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  /// 收起（等动画走完再删 OverlayEntry）。
  Future<void> hide() => _c.reverse();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_c.value).clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -16),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// 横幅内容：图标 + 标题 + 正文，点一下收起。
class _BannerContent extends StatelessWidget {
  const _BannerContent({
    required this.title,
    required this.body,
    required this.onTap,
    this.source,
  });

  final String title;
  final String? body;

  /// 谁发的（拓展名）：小字标一下，多个插件都会弹的时候分得清。
  final String? source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = (body ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: SemColors.menuBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SemColors.borderStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active_outlined,
                  size: 20, color: SemColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SemColors.textPrimary,
                      ),
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: SemColors.textSecondary,
                        ),
                      ),
                    ],
                    if ((source ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        source!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: SemColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.close_rounded, size: 16, color: SemColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
