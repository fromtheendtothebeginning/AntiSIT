import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_api.dart';
import 'evaluate_batch.dart';
import 'evaluate_model.dart';
import 'evaluate_form_page.dart';
import 'evaluate_session.dart';
import 'evaluate_settings.dart';
import 'evaluate_settings_page.dart';

/// 学生评教：**原生界面**（不再内嵌网页）。
///
/// 流程：校园代理 → 教务登录（复用已存 Cookie，必要时输验证码）→ 待评列表
/// → 逐个老师打开评分表（可一键给全部老师同分）→ 保存 / 提交。
///
/// 提交是不可撤销的写操作，所有提交都要经过二次确认；保存可以重复覆盖。
class EvaluatePage extends StatefulWidget {
  const EvaluatePage({super.key});

  @override
  State<EvaluatePage> createState() => _EvaluatePageState();
}

class _EvaluatePageState extends State<EvaluatePage> {
  final EvaluateSession _session = EvaluateSession();
  late EvaluateApi _api;

  bool _booting = true;
  String? _error;
  String _log = '';
  List<EvalTarget> _targets = const [];
  EvalSummary _summary = const EvalSummary();

  @override
  void initState() {
    super.initState();
    _api = _buildApi();
    unawaited(_boot());
  }

  EvaluateApi _buildApi() => EvaluateApi(
        base: AppState.I.school.jwxtBase.replaceAll(RegExp(r'/+$'), ''),
        session: _session,
        proxy: EvaluateSettings.I.proxy,
        onLog: (line) {
          if (!mounted) return;
          setState(() => _log = line);
        },
      );

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _error = null;
    });
    await EvaluateSettings.I.load();
    if (!mounted) return;
    if (!EvaluateSettings.I.loaded) {
      setState(() {
        _booting = false;
        _error = '设置没有加载成功，请重新进入';
      });
      return;
    }
    _api = _buildApi();
    if (!EvaluateSettings.I.proxy.isConfigured) {
      setState(() {
        _booting = false;
        _error = '还没配置校园代理：到「评教设置」里填上校内代理地址后再进来';
      });
      return;
    }
    await _session.load();
    await _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() {
      _booting = true;
      _error = null;
    });
    try {
      if (_session.hasCookies && await _api.checkSession()) {
        await _api.acknowledgeNotice();
      } else {
        await _ensureLogin();
        await _api.acknowledgeNotice();
      }
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
        _error = e.toString();
      });
    }
  }

  /// 走一次验证码登录（验证码弹窗复用直连模式的 [CaptchaDialog]）。
  Future<void> _ensureLogin() async {
    final settings = EvaluateSettings.I;
    if (!settings.hasCredential) {
      throw const EvaluateError('没有可用的学号 / 密码：到「评教设置」里填，或在「连接设置」里填 App 直连凭据');
    }
    String? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final image = await _api.prepareLogin(settings.effectiveStudentId, settings.effectivePassword);
      final text = await _askCaptcha(image, lastError);
      if (text == null) throw const EvaluateError('已取消验证码输入');
      try {
        await _api.completeLogin(text);
        return;
      } on EvaluateError catch (e) {
        lastError = e.message;
        if (!lastError.contains('验证码')) rethrow;
      }
    }
    throw EvaluateError('教务登录失败：' + (lastError ?? '请稍后重试'));
  }

  Future<String?> _askCaptcha(Uint8List image, String? error) {
    final ctx = navKey.currentContext;
    if (ctx == null) throw const EvaluateError('当前界面无法弹出验证码输入框');
    return showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => CaptchaDialog(
        image: image,
        hint: '教务系统验证码',
        error: error,
        onRefresh: () => _api.prepareLogin(
            EvaluateSettings.I.effectiveStudentId, EvaluateSettings.I.effectivePassword),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const EvaluateSettingsPage(),
    ));
    if (!mounted) return;
    await EvaluateSettings.I.load();
    _api = _buildApi();
    await _loadTargets();
  }

  /// 一键给本轮**全部老师**打同一分并保存（不提交：提交不可撤销，留给逐条确认）。
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
          title: const Text('一键给全部老师打分'),
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
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('已保存 ' + result.done.toString() + ' 条'),
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
                const Text('全部保存成功，点开每一条确认无误后提交。')
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
    } on EvaluateError catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '一键打分失败');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '一键打分失败');
      }
    } finally {
      if (mounted && _booting) setState(() => _booting = false);
    }
  }

  /// 全部提交：连续把本轮所有「未提交」条目提交掉。
  ///
  /// 提交不可撤销，所以这里要**两次**确认，并且把「会提交多少条」写清楚；
  /// 每条都用**同一个分数**重新打分后提交（学校提交时必须带上打分明细）。
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
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('已提交 ' + result.done.toString() + ' 条'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.failures.isEmpty)
                const Text('全部提交完成，刷新列表可以看到状态变成「已提交」。')
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
    } on EvaluateError catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '批量提交失败');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _booting = false);
        showErr(context, e, title: '批量提交失败');
      }
    } finally {
      if (mounted && _booting) setState(() => _booting = false);
    }
  }

  void _openTarget(EvalTarget target, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EvaluateFormPage(
        api: _api,
        target: target,
        targets: _targets,
        index: index,
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
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
            tooltip: '评教设置',
          ),
          IconButton(
            onPressed: _booting || _targets.isEmpty ? null : _fillAllTargets,
            icon: const Icon(Icons.bolt_rounded),
            tooltip: '一键给全部老师打分',
          ),
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
      floatingActionButton: _targets.isEmpty || _booting
          ? null
          : FloatingActionButton.extended(
              onPressed: _submitAll,
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('全部提交'),
            ),
    );
  }

  Widget _loadingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(height: 14),
            Text('正在经校园代理读取评教列表…',
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
              OutlinedButton(onPressed: _openSettings, child: const Text('评教设置')),
            ],
          ),
        ),
      );

  Widget _listView() => RefreshIndicator(
        onRefresh: _loadTargets,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _summaryCard(),
            const SizedBox(height: 4),
            for (var i = 0; i < _targets.length; i++) _targetCard(_targets[i], i),
            if (_targets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text('没有待评的教学班（本轮评教可能还没开始，或已全部完成）',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: SemColors.textMuted)),
              ),
          ],
        ),
      );

  Widget _summaryCard() {
    final s = _summary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('本轮评教',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SemColors.textPrimary)),
              const Spacer(),
              Capsule('代理 ' + EvaluateSettings.I.proxy.endpoint,
                  color: SemColors.accent),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              BigStat(
                  label: '未评',
                  value: s.pending.toString(),
                  color: s.pending > 0 ? SemColors.danger : SemColors.textPrimary),
              const SizedBox(width: 20),
              BigStat(
                  label: '已保存', value: s.saved.toString(), color: SemColors.accent),
              const SizedBox(width: 20),
              BigStat(
                  label: '已提交',
                  value: s.submitted.toString(),
                  color: s.submitted > 0 ? SemColors.success : SemColors.textPrimary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.allDone
                ? '本轮已全部提交，感谢参与评教。'
                : '共 ' +
                    s.total.toString() +
                    ' 门次；点开每一条即可打分，也可以在评分页里一键给全部老师同分。',
            style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _targetCard(EvalTarget t, int index) {
    final color = t.submitted
        ? SemColors.success
        : (t.saved ? SemColors.accent : SemColors.danger);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: SemColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openTarget(t, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(t.course,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: SemColors.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        Capsule(t.statusLabel, color: color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(t.teacher,
                        style: TextStyle(fontSize: 13, color: SemColors.textSecondary)),
                    if (t.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      ),
                    if (t.time.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t.time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: SemColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}