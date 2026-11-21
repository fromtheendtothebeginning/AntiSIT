import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_api.dart';
import 'evaluate_batch.dart';
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
class EvaluatePage extends StatefulWidget {
  const EvaluatePage({super.key});

  @override
  State<EvaluatePage> createState() => _EvaluatePageState();
}

class _EvaluatePageState extends State<EvaluatePage> {
  late EvaluateSession _session;
  late EvaluateApi _api;

  bool _booting = true;
  String? _error;
  String _log = '';
  List<EvalTarget> _targets = const [];
  EvalSummary _summary = const EvalSummary();

  @override
  void initState() {
    super.initState();
    _session = EvaluateSession(fallbackBase: AppState.I.school.jwxtBase);
    _api = _buildApi();
    unawaited(_boot());
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

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _error = null;
    });
    if (AppState.I.demo) {
      setState(() {
        _booting = false;
        _error = '演示模式没有真实教务数据';
      });
      return;
    }
    // 服务器模式：先要到校园隧道代理，否则设备根本到不了教务
    if (!AppState.I.direct) {
      setState(() => _log = '正在连接校园隧道…');
      _serverProxyUrl = await _resolveProxy();
      if (!mounted) return;
      if (_serverProxyUrl.isEmpty) {
        setState(() {
          _booting = false;
          _error = '服务器模式要经校园隧道访问教务：先到「我的 → 校园服务」连接校园网，'
              '或切到直连模式再进来';
        });
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
      debugPrint('[学生评教] 取校园隧道代理失败：' + e.toString());
      return '';
    }
  }

  /// 取 App 已登录的教务会话（与成绩 / 课表同一条路），灌进 [EvaluateSession]。
  Future<void> _adoptSharedSession() async {
    final web = await ApiClient.I.jwxtWebSession();
    _session.adopt(web);
  }

  Future<void> _loadTargets() async {
    setState(() {
      _booting = true;
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
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _summary = summary;
        _booting = false;
      });
    } on EvaluateError catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e is ApiError ? e.message : e.toString();
      });
    }
  }

  void _openConnectionSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ConnectPage(),
    ));
  }

  Future<void> _fillAllTargets() async {
    final pending = _targets.where((t) => !t.submitted).toList();
    if (pending.isEmpty) {
      showErr(context, '本轮没有可打分的条目（都已提交）', title: '无需操作');
      return;
    }
    var score = 95.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('全部打分'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('把分数写进 ' + pending.length.toString() + ' 位老师的每一道题，并保存（不提交）。',
                  style: const TextStyle(fontSize: 13, height: 1.7)),
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
                    child: Text(score.toInt().toString(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: SemColors.accent)),
                  ),
                ],
              ),
              Text('提交仍需你逐条确认——提交之后不能修改。',
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.textMuted)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始')),
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
          if (mounted) setState(() => _log = '正在处理 ' + m);
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

  Future<void> _submitAll() async {
    final pending = _targets.where((t) => !t.submitted).toList();
    if (pending.isEmpty) {
      showErr(context, '本轮没有可提交的条目', title: '无需操作');
      return;
    }
    var score = 95.0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('提交全部评教？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将对 ' + pending.length.toString() + ' 条评教按下面的分数提交。',
                  style: const TextStyle(fontSize: 13, height: 1.7)),
              const SizedBox(height: 10),
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
                    child: Text(score.toInt().toString(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: SemColors.accent)),
                  ),
                ],
              ),
              Text('提交之后不能修改，也不能撤销。评教是匿名的：教师看不到具体打分。',
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.danger)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再想想')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认提交')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _booting = true);
    try {
      final result = await submitAllTargets(
        api: _api,
        targets: _targets,
        score: score,
        onProgress: (m) {
          if (mounted) setState(() => _log = '正在提交 ' + m);
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

  Future<void> _showBatchResult(BatchResult result, {required bool submitted}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((submitted ? '已提交 ' : '已保存 ') + result.done.toString() + ' 条'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.skipped > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('已提交的 ' + result.skipped.toString() + ' 条已跳过。',
                    style: const TextStyle(fontSize: 12.5, height: 1.6)),
              ),
            if (result.failures.isEmpty)
              Text(submitted ? '全部提交完成，列表里可以看到状态变成「已提交」。' : '全部保存成功，点开每一条确认无误后提交。')
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Text(result.failures.join('\n\n'),
                      style: const TextStyle(fontSize: 12.5, height: 1.6)),
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _openTarget(EvalTarget target, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EvaluateFormPage(
        api: _api,
        target: target,
        onChanged: _loadTargets,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学生评教'),
        actions: [
          IconButton(
            onPressed: _booting ? null : _loadTargets,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _booting
          ? _loadingView()
          : (_error != null ? _errorView(_error!) : _listView()),
    );
  }

  Widget _loadingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(height: 14),
            Text('正在读取评教列表…',
                style: TextStyle(fontSize: 12.5, color: SemColors.textMuted)),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_log, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
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
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.7, color: SemColors.textSecondary)),
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

  Widget _listView() => EvaluateListView(
        targets: _targets,
        summary: _summary,
        connectionLabel: AppState.I.direct ? '直连' : '校园隧道',
        onTapTarget: _openTarget,
        onRefresh: _loadTargets,
        onFillAll: _fillAllTargets,
        onSubmitAll: _submitAll,
      );
}