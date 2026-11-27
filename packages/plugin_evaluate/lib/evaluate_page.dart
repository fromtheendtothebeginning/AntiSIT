import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_api.dart';
import 'evaluate_batch.dart';
import 'evaluate_batch_dialogs.dart';
import 'evaluate_cache.dart';
import 'evaluate_model.dart';
import 'evaluate_form_page.dart';
import 'evaluate_session.dart';
import 'evaluate_views.dart';

/// 学生评教列表页：复用 App 已登录的教务会话（不自己登录、不单独配代理）。
/// 提交不可撤销，必须二次确认；「全部提交」交的是**已保存的那套分**（见 [canSubmitAll]）。
class EvaluatePage extends StatefulWidget {
  const EvaluatePage({super.key});

  @override
  State<EvaluatePage> createState() => _EvaluatePageState();
}

class _EvaluatePageState extends State<EvaluatePage> {
  late EvaluateSession _session;
  late EvaluateApi _api;

  /// 还没有任何内容可显示（首屏转圈）；有缓存时不再置 true，否则会盖住缓存。
  bool _booting = true;

  /// 正在联网刷新（顶部刷新条转圈；页面继续显示缓存）。
  bool _refreshing = false;

  String? _error;
  String _log = '';

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用）。
  bool _fromCache = false;
  bool _refreshFailed = false;
  List<EvalTarget> _targets = const [];
  EvalSummary _summary = const EvalSummary();

  /// 服务器模式要用的校园隧道代理地址（`http://host:port`）；直连模式恒为空。
  String _serverProxyUrl = '';

  @override
  void initState() {
    super.initState();
    _session = EvaluateSession(fallbackBase: AppState.I.school.jwxtBase);
    _api = _buildApi();
    unawaited(_restore());
  }

  EvaluateApi _buildApi() => EvaluateApi(
    session: _session,
    // 直连模式为空（设备自己在校园网里）；服务器模式走服务器给的校园隧道
    proxyUrl: AppState.I.direct ? '' : _serverProxyUrl,
    onLog: (line) {
      if (!mounted) return;
      setState(() => _log = line);
    },
  );

  /// 先读本机缓存立即展示，再按「工具页自动刷新」设置决定是否联网拉新。
  Future<void> _restore() async {
    final cached = await EvaluationCache.read();
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _targets = cached.targets;
        _summary = cached.summary;
        _booting = false;
        _fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools && cached != null) return;
    await _boot();
  }

  /// 首次进入：演示数据 / 校园隧道 / 拉列表。
  Future<void> _boot() async {
    setState(() {
      // 已经有缓存时不整页转圈，只让顶部刷新条转（避免闪空态）
      _booting = _targets.isEmpty;
      _refreshing = true;
      _error = null;
      _refreshFailed = false;
    });
    if (AppState.I.demo) {
      // 演示模式：本地假数据走一遍真实 UI，不发网络请求；提交 / 保存仍会被拦截。
      final demoTargets = [
        for (var i = 0; i < 6; i++)
          EvalTarget(
            jxbId: 'DEMO_JXB_',
            kchId: 'DEMO_KC_',
            jghId: 'DEMO_JGH_',
            sfcjlrjs: '1',
            tjzt: i == 0 ? '0' : '-1',
            course: [
              '高等数学(下)',
              '数据结构',
              '大学物理(二)',
              '线性代数',
              '大学英语(三)',
              '体育(四)',
            ][i],
            teacher: ['王建国', '陈强', '孙丽', '吴敏', '李芳', '张伟'][i],
            className: '计科2501',
            college: '计算机学院',
            time: '周一 3-4 节',
            place: '一教 A20',
          ),
      ];
      setState(() {
        _targets = demoTargets;
        _summary = EvalSummary(pending: 5, saved: 1, submitted: 0);
        _booting = false;
        _refreshing = false;
        _fromCache = false;
      });
      return;
    }
    // 服务器模式：先要到校园隧道代理，否则设备根本到不了教务。
    // 隧道可能还在建（服务器回 202 的那段时间），所以这里带重试，而不是一次拿不到就报错。
    if (!AppState.I.direct) {
      setState(() => _log = '正在连接校园隧道…');
      final proxy = await _ensureProxy();
      if (!mounted) return;
      if (proxy.isEmpty) {
        setState(
          () => _fail(
            '连不上校园隧道：请先到「我的 → 校园服务」连接校园网，'
            '或切到直连模式再进来',
          ),
        );
        return;
      }
    }
    _api = _buildApi();
    await _loadTargets();
  }

  /// 拿到（必要时等出来）服务器模式的校园隧道代理地址。
  ///
  /// 服务器侧隧道建立是**按需**的：只有隧道类请求收到 202 才会开始建，建好之前
  /// `/status` 里没有 `http_port`，代理地址就是空串。以前这里只探一次，隧道还没
  /// 建好就报「先连接校园网」，看起来像评教在服务器模式下坏了。现在探不到就先发
  /// 一个轻量隧道请求把建隧道流程推起来，然后按 3 秒一轮等最多 90 秒。
  Future<String> _ensureProxy({bool force = false}) async {
    if (AppState.I.direct) return '';
    // 没填服务器地址：等再久也不会有隧道，直接返回空（由调用方给出配置引导）。
    if (AppState.I.serverUrl.isEmpty) return '';
    if (!force && _serverProxyUrl.isNotEmpty) return _serverProxyUrl;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    var attempt = 0;
    var warmupStarted = false;
    while (mounted && DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        final proxy = await ApiClient.I.serverWebProxy();
        if (proxy.isNotEmpty) {
          _serverProxyUrl = proxy;
          return proxy;
        }
      } catch (e) {
        debugPrint('[学生评教] 取校园隧道代理失败（第 $attempt 次）：$e');
      }
      // 第一次探测失败：顺手发一个轻量隧道请求，让服务器开始建隧道
      if (!warmupStarted) {
        warmupStarted = true;
        unawaited(
          ApiClient.I.score().catchError((Object _) => <String, dynamic>{}),
        );
      }
      if (!mounted) return '';
      setState(() => _log = '正在连接校园隧道…（第 $attempt 次探测）');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return _serverProxyUrl;
  }

  /// 取 App 已登录的教务会话（与成绩 / 课表同一条路），灌进 [EvaluateSession]。
  Future<void> _adoptSharedSession() async {
    final web = await ApiClient.I.jwxtWebSession();
    _session.adopt(web);
  }

  /// 刷新失败时的统一收尾：有缓存就不切错误页，只在顶部刷新条上提示。
  void _fail(String message) {
    _booting = false;
    _refreshing = false;
    if (_targets.isEmpty) {
      _error = message;
    } else {
      _refreshFailed = true;
    }
  }

  /// 拉待评列表与汇总，并写本机缓存。
  Future<void> _loadTargets() async {
    setState(() {
      // 只有「手上什么都没有」才整页转圈；有缓存就继续显示缓存。
      _booting = _targets.isEmpty;
      _refreshing = true;
      _error = null;
    });
    try {
      // 服务器模式：每轮都确认隧道代理还在（服务器重连后端口可能变）。
      if (!AppState.I.direct) {
        final proxy = await _ensureProxy();
        if (proxy.isEmpty) {
          throw const EvaluateError('连不上校园隧道：先到「我的 → 校园服务」连接校园网后再试');
        }
        if (proxy != _serverProxyUrl) {
          _serverProxyUrl = proxy;
          _api = _buildApi();
        }
      }
      await _adoptSharedSession();
      if (!_session.hasCookies) {
        throw const EvaluateError('教务还没登录：先到「我的 → 连接设置」登录一次教务，再回来评教');
      }
      if (!await _api.checkSession()) {
        // 会话半失效：重新向 App 要一次（直连模式会走一遍验证码登录，服务器模式让服务器重连）
        await _adoptSharedSession();
        if (!await _api.checkSession()) {
          throw const EvaluateError('教务会话已失效：到「我的 → 连接设置」重新登录后再进来');
        }
      }
      // 服务器模式：隧道代理可能中途重连（端口变了 / 会话掉了），写操作前重建一次 API
      if (!AppState.I.direct) {
        final proxy = await _ensureProxy();
        if (proxy.isNotEmpty && proxy != _serverProxyUrl) {
          _serverProxyUrl = proxy;
          _api = _buildApi();
        }
      }
      await _api.acknowledgeNotice();
      final targets = await _api.fetchTargets();
      final summary = await _api.fetchSummary();
      await EvaluationCache.write(targets, summary);
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _summary = summary;
        _booting = false;
        _refreshing = false;
        _fromCache = false;
      });
    } on EvaluateError catch (e) {
      if (!mounted) return;
      setState(() => _fail(e.message));
    } catch (e) {
      if (!mounted) return;
      setState(() => _fail(e is ApiError ? e.message : e.toString()));
    }
  }

  void _openConnectionSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ConnectPage()));
  }

  /// 「全部打分」的默认分数：取本机记住的最近一条分数的中位数，一条都没有才回到 95。
  /// 「全部提交」不用它——那个按钮交的是已保存的分。
  Future<double> _defaultBatchScore(List<EvalTarget> targets) async {
    for (final t in targets) {
      final saved = await EvaluationLocalScores.read(t);
      if (saved == null || saved.isEmpty) continue;
      final values = saved.values.toList();
      values.sort();
      return values[values.length ~/ 2]; // 取中位数：逐项微调过的分数用它更贴近原样
    }
    return 95;
  }

  /// 「全部打分」：统一分数写进每条并保存（不提交）。
  Future<void> _fillAllTargets() async {
    final pending = _targets.where((t) => !t.submitted).toList();
    if (pending.isEmpty) {
      showErr(context, '本轮没有可打分的条目（都已提交）', title: '无需操作');
      return;
    }
    final score = await _defaultBatchScore(pending);
    if (!mounted) return;
    final picked = await showFillAllDialog(
      context,
      count: pending.length,
      score: score,
    );
    if (picked == null) return;
    setState(() => _booting = true);
    try {
      final result = await fillAllTargets(
        api: _api,
        targets: _targets,
        score: picked,
        onProgress: (m) {
          if (mounted) setState(() => _log = '正在处理 $m');
        },
      );
      await _loadTargets();
      if (!mounted) return;
      await showBatchResultDialog(context, result: result, submitted: false);
    } catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '批量打分失败');
      }
    } finally {
      if (mounted && _booting) setState(() => _booting = false);
    }
  }

  /// 「全部提交」：交的是已保存好的那套分，前提是每一条都保存过（[canSubmitAll]）。
  Future<void> _submitAll() async {
    if (!canSubmitAll(_targets)) {
      _tellNotSaved();
      return;
    }
    final count = _targets.where((t) => !t.submitted).length;
    final confirmed = await showSubmitAllConfirm(context, count: count);
    if (!confirmed) return;
    setState(() => _booting = true);
    try {
      final result = await submitAllTargets(
        api: _api,
        targets: _targets,
        onProgress: (m) {
          if (mounted) setState(() => _log = '正在提交 $m');
        },
      );
      await _loadTargets();
      if (!mounted) return;
      await showBatchResultDialog(context, result: result, submitted: true);
    } catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '批量提交失败');
      }
    } finally {
      if (mounted && _booting) setState(() => _booting = false);
    }
  }

  /// 「还不能全部提交」的统一提示：点明是哪几条还没保存。
  void _tellNotSaved() {
    final missing = _targets.where((t) => !t.submitted && !t.saved).toList();
    if (missing.isEmpty) {
      showErr(context, '本轮没有可提交的条目（都已提交）', title: '无需操作');
      return;
    }
    final names = missing.take(3).map((t) => t.teacher).join('、');
    final more = missing.length > 3 ? ' 等 ${missing.length} 条' : '';
    showErr(
      context,
      '还有 ${missing.length} 条没保存（$names$more）。全部提交交的是已保存的内容，'
      '先把它们保存好，按钮才会亮。',
      title: '还不能全部提交',
    );
  }

  void _openTarget(EvalTarget target, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EvaluateFormPage(
          api: _api,
          target: target,
          onChanged: _loadTargets,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('学生评教'),
            actions: [
              IconButton(
                onPressed: _booting ? null : _loadTargets,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新',
              ),
            ],
          ),
          // 主体是整块内容（加载 / 出错 / 列表三态），用 Padding 统一顶出顶栏这一截
          body: GlassFadedBody(
            barHeight: topInset,
            child: _booting
                ? Padding(
                    padding: EdgeInsets.only(top: topInset),
                    child: _loadingView(),
                  )
                : (_error != null
                      ? Padding(
                          padding: EdgeInsets.only(top: topInset),
                          child: _errorView(_error!),
                        )
                      : _listView(topInset)),
          ),
        );
      },
    );
  }

  Widget _loadingView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: 14),
        Text(
          '正在读取评教列表…',
          style: TextStyle(fontSize: 12.5, color: SemColors.textMuted),
        ),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _log,
            style: TextStyle(fontSize: 11, color: SemColors.textMuted),
          ),
        ],
      ],
    ),
  );

  Widget _errorView(String message) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 44, color: SemColors.textMuted),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: SemColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _loadTargets, child: const Text('重试')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _openConnectionSettings,
            child: const Text('去连接设置'),
          ),
        ],
      ),
    ),
  );

  // 刷新条放进列表内容里：跟内容一起滚，不再钉在顶部
  Widget _listView(double topInset) => EvaluateListView(
    targets: _targets,
    summary: _summary,
    topPadding: topInset,
    header: ToolRefreshBar(
      refreshing: _refreshing,
      fromCache: _fromCache,
      failed: _refreshFailed,
      onRefresh: _loadTargets,
    ),
    connectionLabel: AppState.I.direct ? '直连' : '校园隧道',
    onTapTarget: _openTarget,
    onRefresh: _loadTargets,
    onFillAll: _fillAllTargets,
    onSubmitAll: _submitAll,
  );
}
