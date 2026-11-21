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
import 'evaluate_views.dart';

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
        // 直连模式这里为空（设备自己在校园网里）；服务器模式要经服务器给的校园隧道
        proxyUrl: AppState.I.direct ? '' : _serverProxyUrl,
        onLog: (line) {
          if (!mounted) return;
          setState(() => _log = line);
        },
      );

  /// 服务器模式要用的校园隧道代理（http://host:port）；直连模式恒为空。
  String _serverProxyUrl = '';

  Future<String> _resolveProxy() async {
    if (AppState.I.direct || AppState.I.demo) return '';
    try {
      return await ApiClient.I.serverWebProxy();
    } catch (e) {
      debugPrint('[学生评教] 取校园隧道代理失败：' + e.toString());
      return '';
    }
  }

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
    final conn = EvaluateSettings.I.connectivity();
    if (!conn.ok) {
      setState(() {
        _booting = false;
        _error = conn.reason;
      });
      return;
    }
    if (!AppState.I.direct) {
      // 服务器模式：先要到校园隧道代理，否则设备根本到不了教务
      setState(() => _log = '正在连接校园隧道…');
      _serverProxyUrl = await _resolveProxy();
      if (!mounted) return;
      if (_serverProxyUrl.isEmpty) {
        setState(() {
          _booting = false;
          _error = '服务器模式需要校园隧道才能打开教务：先到「我的 → 校园服务」连接校园网，'
              '或切到直连模式再进来';
        });
        return;
      }
    }
    _api = _buildApi();
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
              OutlinedButton(onPressed: _openSettings, child: const Text('评教设置')),
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