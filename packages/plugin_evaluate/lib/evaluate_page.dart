import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_api.dart';
import 'evaluate_batch.dart';
import 'evaluate_cache.dart';
import 'evaluate_model.dart';
import 'evaluate_form_page.dart';
import 'evaluate_session.dart';
import 'evaluate_views.dart';

/// 学生评教：**原生界面**（不再内嵌网页），连接方式与其它教务功能完全一致。
///
/// 不自己登录、不单独配代理：直接复用 App 已登录的教务会话
/// （[ApiClient.jwxtWebSession]，直连模式是本机 Cookie、服务器模式是服务器代连的会话）。
/// 会话没了就去「连接设置」重新登录一次，回来这里照样能用。
///
/// 提交是不可撤销的写操作，所有提交都要经过二次确认；保存可以重复覆盖。
/// 「全部提交」交的是**已保存的那套分**（页面不再另设分数），
/// 所以只有每一条都保存过时才可用——见 [canSubmitAll]。
class EvaluatePage extends StatefulWidget {
  const EvaluatePage({super.key});

  @override
  State<EvaluatePage> createState() => _EvaluatePageState();
}

class _EvaluatePageState extends State<EvaluatePage> {
  late EvaluateSession _session;
  late EvaluateApi _api;

  /// 还没有任何内容可显示（首屏转圈）。**有缓存时不再置 true**，
  /// 否则整页 loading 会把刚读出来的缓存盖住。
  bool _booting = true;

  /// 正在联网刷新（顶部刷新条转圈；页面继续显示缓存）。
  bool _refreshing = false;

  String? _error;
  String _log = '';

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用，与其它工具页一致）。
  bool _fromCache = false;
  bool _refreshFailed = false;
  List<EvalTarget> _targets = const [];
  EvalSummary _summary = const EvalSummary();

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

  /// 服务器模式要用的校园隧道代理（http://host:port）；直连模式恒为空。
  String _serverProxyUrl = '';

  /// 先读本机缓存立即展示，再按「工具页自动刷新」设置决定是否联网拉新。
  /// 与成绩 / 二课等工具页同一套行为：有缓存时不闪空态，失败也保留旧数据。
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

  Future<void> _boot() async {
    setState(() {
      // 已经有缓存时不整页转圈，只让顶部刷新条转（避免闪空态）
      _booting = _targets.isEmpty;
      _refreshing = true;
      _error = null;
      _refreshFailed = false;
    });
    if (AppState.I.demo) {
      setState(() => _fail('演示模式没有真实教务数据'));
      return;
    }
    // 服务器模式：先要到校园隧道代理，否则设备根本到不了教务
    if (!AppState.I.direct) {
      setState(() => _log = '正在连接校园隧道…');
      _serverProxyUrl = await _resolveProxy();
      if (!mounted) return;
      if (_serverProxyUrl.isEmpty) {
        setState(
          () => _fail(
            '服务器模式要经校园隧道访问教务：先到「我的 → 校园服务」连接校园网，'
            '或切到直连模式再进来',
          ),
        );
        return;
      }
    }
    _api = _buildApi();
    await _loadTargets();
  }

  Future<String> _resolveProxy() async {
    if (AppState.I.direct) return '';
    try {
      return await ApiClient.I.serverWebProxy();
    } catch (e) {
      debugPrint('[学生评教] 取校园隧道代理失败：$e');
      return '';
    }
  }

  /// 取 App 已登录的教务会话（与成绩 / 课表同一条路），灌进 [EvaluateSession]。
  Future<void> _adoptSharedSession() async {
    final web = await ApiClient.I.jwxtWebSession();
    _session.adopt(web);
  }

  /// 刷新失败时的统一收尾：**有缓存就不切错误页**，只在顶部刷新条上提示。
  ///
  /// 否则网络一断，用户明明有上次的列表可看，却被一个错误页挡住。
  void _fail(String message) {
    _booting = false;
    _refreshing = false;
    if (_targets.isEmpty) {
      _error = message;
    } else {
      _refreshFailed = true;
    }
  }

  Future<void> _loadTargets() async {
    setState(() {
      // 关键：只有「手上什么都没有」才整页转圈。有缓存就继续显示缓存，
      // 让顶部刷新条表达「正在刷新」，两者同时存在。
      _booting = _targets.isEmpty;
      _refreshing = true;
      _error = null;
    });
    try {
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

  /// 「全部打分」的默认分数：取本机记住的最近一条分数（原来打多少就还是多少），
  /// 一条都没有才回到 95 分。
  ///
  /// 「全部提交」不用它——那个按钮交的是已保存的分，页面不再另设分数。
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

  Future<void> _fillAllTargets() async {
    final pending = _targets.where((t) => !t.submitted).toList();
    if (pending.isEmpty) {
      showErr(context, '本轮没有可打分的条目（都已提交）', title: '无需操作');
      return;
    }
    // 默认分：优先用本机记下的上次分数（同一条已保存/已提交的评教），没有才是 95
    var score = await _defaultBatchScore(pending);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('全部打分'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '把分数写进 ${pending.length} 位老师的每一道题，并保存（不提交）。',
                style: const TextStyle(fontSize: 13, height: 1.7),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: score,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: score.toInt().toString(),
                      onChanged: (v) => setLocal(() => score = v),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      score.toInt().toString(),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: SemColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '保存好之后，「全部提交」交的就是这套分——不会另设分数。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: SemColors.textMuted,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _booting = true);
    try {
      final result = await fillAllTargets(
        api: _api,
        targets: _targets,
        score: score,
        onProgress: (m) {
          if (mounted) setState(() => _log = '正在处理 $m');
        },
      );
      await _loadTargets();
      if (!mounted) return;
      await _showBatchResult(result, submitted: false);
    } catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '批量打分失败');
      }
    } finally {
      if (mounted && _booting) setState(() => _booting = false);
    }
  }

  /// 「全部提交」：交的是**已经保存好的那套分**，这里不再给分数。
  ///
  /// 前提是每一条都保存过（[canSubmitAll]），按钮只有在这种时候才亮；
  /// 万一还是进来了（缓存/列表刚好变了），先挡回去并说清是哪一条没保存。
  Future<void> _submitAll() async {
    if (!canSubmitAll(_targets)) {
      _tellNotSaved();
      return;
    }
    final count = _targets.where((t) => !t.submitted).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提交全部评教？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '把已保存的 $count 条评教原样提交（分数是你保存时打的那套）。',
              style: const TextStyle(fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 8),
            const Text(
              '提交之后不能修改，也不能撤销。评教是匿名的：教师看不到你的具体打分。',
              style: TextStyle(fontSize: 11.5, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
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
      await _showBatchResult(result, submitted: true);
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

  Future<void> _showBatchResult(
    BatchResult result, {
    required bool submitted,
  }) async {
    // 失败与「回了成功但复查没变」分开列，后者不是没做，只是没确认
    final problems = [
      ...result.failures,
      for (final u in result.unconfirmed) '$u（教务回了成功，但复查没看到变化）',
    ];
    final String headline;
    if (!result.checked) {
      headline = '已发出 ${result.done} 条，但复查时没连上教务：'
          '请下拉刷新列表确认状态，别当成没提交又点一次。';
    } else if (submitted) {
      headline = problems.isEmpty
          ? '全部提交完成，列表里可以看到状态变成「已提交」。'
          : '已提交 ${result.done} 条，还有 ${problems.length} 条没成功。';
    } else {
      headline = problems.isEmpty
          ? '全部保存成功，现在可以点「全部提交」了。'
          : '已保存 ${result.done} 条，还有 ${problems.length} 条没成功。';
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${submitted ? '已提交 ' : '已保存 '}${result.done} 条'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.skipped > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '已提交的 ${result.skipped} 条已跳过。',
                  style: const TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ),
            if (problems.isEmpty)
              Text(
                headline,
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: const TextStyle(fontSize: 12.5, height: 1.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        problems.join('\n\n'),
                        style: const TextStyle(fontSize: 12.5, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
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
    // 整页监听 AppState：悬浮玻璃顶栏开关改完要连 Scaffold 一起重建
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已扣掉状态栏）
        final topInset = glassTopInset(context);
        return Scaffold(
          // 顶栏是悬浮玻璃条：内容从它底下穿过去，渐变模糊才有东西可糊
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
          body: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: _booting
                ? _loadingView()
                : (_error != null ? _errorView(_error!) : _listView()),
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
              Icon(Icons.cloud_off_outlined,
                  size: 44, color: SemColors.textMuted),
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

  Widget _listView() => Column(
        children: [
          // 与其它工具页一致的刷新条：转圈时继续展示旧数据，失败也只在这里提示
          ToolRefreshBar(
            refreshing: _refreshing,
            fromCache: _fromCache,
            failed: _refreshFailed,
            onRefresh: _loadTargets,
          ),
          Expanded(
            child: EvaluateListView(
              targets: _targets,
              summary: _summary,
              connectionLabel: AppState.I.direct ? '直连' : '校园隧道',
              onTapTarget: _openTarget,
              onRefresh: _loadTargets,
              onFillAll: _fillAllTargets,
              onSubmitAll: _submitAll,
            ),
          ),
        ],
      );
}
