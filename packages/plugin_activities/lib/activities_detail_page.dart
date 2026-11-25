import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'activities_state.dart';

/// 活动详情页：展示学校元信息与报名方式，并提交在线报名。
class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({super.key, required this.id, this.activity});

  final String id;

  /// 列表项数据：详情接口只返回 id/hdms/quota/signup，其余元信息从这里取。
  final Map<String, dynamic>? activity;

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _data;
  bool _signingUp = false;

  /// 报名成功后的工作流实例 ID（学校侧审批记录，可凭它追溯进度）。
  String? _signedInstanceId;

  /// 报名被学校明确拒绝后记住原因（名额满 / 条件不符），按钮直接显示对应状态。
  SignupBlock? _blocked;

  /// 已报名：本次会话报过、学校详情 signed、或列表项 signed 三者之一。
  bool get _signed =>
      _signedInstanceId != null ||
      _data?['signed'] == true ||
      widget.activity?['signed'] == true;

  /// 不可报名状态：本次提交被拒的原因优先，其次看学校数据里的人数 / 状态原文。
  SignupBlock? get _blockState {
    if (_blocked != null) return _blocked;
    final a = _data;
    if (a == null) return null;
    if (isIneligibleSignup(a)) return SignupBlock.ineligible;
    if (isFullSignup(a)) return SignupBlock.full;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _data = widget.activity == null
        ? null
        : Map<String, dynamic>.from(widget.activity!);
    _load();
  }

  /// 拉详情并与列表项数据合并（详情覆盖同名键）。
  Future<void> _load() async {
    final hasBase = _data != null && _data!.isNotEmpty;
    setState(() {
      _loading = !hasBase;
      _err = null;
    });
    try {
      final r = await ApiClient.I.activityDetail(widget.id);
      _data = {...?_data, ...?r['data'] as Map<String, dynamic>?};
    } catch (e) {
      if (_data == null || _data!.isEmpty) {
        _err = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '活动详情加载失败');
      } else if (mounted) {
        showErr(context, e, title: '刷新失败');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label：$value'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 报名信息由学校系统预填，点一下确认直接提交。
  Future<void> _confirmSignup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('确认报名'),
        content: Text(
          '「${_data?['name'] ?? ''}」\n\n报名信息由学校系统自动填写，'
          '提交后进入学校审批流。\n重复提交可能生成多条申请，请勿反复点击。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('确认报名'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final iid = await _submitSignup();
    if (iid != null) _showSignupResult(iid);
  }

  /// 提交报名：成功返回申请编号（学校没给时为空串），失败返回 null。
  /// 写操作防重：提交中按钮禁用；超时 / 网络错误结果不确定时必须人工确认后再重试。
  Future<String?> _submitSignup() async {
    setState(() => _signingUp = true);
    try {
      final r = await ApiClient.I.activitySignup(widget.id);
      final iid = (((r['data'] as Map?)?['instance_id'] ?? '').toString());
      if (mounted) setState(() => _signedInstanceId = iid);
      return iid;
    } on ApiError catch (e) {
      if (!mounted) return null;
      final block = signupBlockOfError(e.message);
      if (block != null) {
        setState(() => _blocked = block);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return null;
      }
      final uncertain = e.message.contains('超时') || e.message.contains('网络错误');
      if (uncertain) {
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('提交结果不确定'),
            content: Text(
              '${e.message}\n\n报名请求可能已提交成功。请先到学工系统「我的申请」确认是否已有'
              '该活动的申请记录，再决定是否重新提交（重复提交可能生成多条申请）。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      } else {
        showErr(context, e, title: '报名失败');
      }
      return null;
    } finally {
      if (mounted) setState(() => _signingUp = false);
    }
  }

  void _showSignupResult(String iid) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('报名已提交'),
        content: Text(
          iid.isEmpty
              ? '申请已进入学校审批流。'
              : '申请已进入学校审批流。\n\n申请编号：$iid\n（可在学工系统的「我的申请」中查看进度）',
        ),
        actions: [
          if (iid.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: iid));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制申请编号'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('复制编号'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signup = (_data?['signup'] as Map<String, dynamic>?) ?? {};
    final a = _data;
    final state = a == null ? null : activityStateOf(a);
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('活动详情')),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: _signupButton(state),
            ),
          ),
          body: GlassFadedBody(
            barHeight: topInset,
            child: PageStateView(
              loading: _loading,
              error: _err,
              onRetry: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 24),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a != null)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Capsule(
                                activityStateText(activityStateOf(a)),
                                color: activityStateColor(activityStateOf(a)),
                              ),
                              if (_signed)
                                Capsule('已报名', color: SemColors.success),
                              if (a['backfill'] as bool? ?? false)
                                Capsule('事后补录', color: SemColors.info),
                              if ('${a['dlmc'] ?? ''}'.trim().isNotEmpty)
                                Capsule(
                                  '${a['dlmc']}',
                                  color: SemColors.accent,
                                ),
                              if ('${a['lbmc'] ?? ''}'.trim().isNotEmpty)
                                Capsule(
                                  '${a['lbmc']}',
                                  color: SemColors.accent,
                                ),
                            ],
                          ),
                        if (a != null) const SizedBox(height: 10),
                        Text(
                          '${a?['name'] ?? ''}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: SemColors.textPrimary,
                          ),
                        ),
                        const Divider(height: 24),
                        _kv(
                          '活动时间',
                          '${a?['start'] ?? '-'} ~ ${a?['end'] ?? '-'}',
                        ),
                        _kv(
                          '报名时间',
                          '${a?['bm_start'] ?? '-'} ~ ${a?['bm_end'] ?? '-'}',
                        ),
                        _kv('名额', '${a?['quota'] ?? '-'}'),
                        _kv('校区', '${a?['campus'] ?? '-'}'),
                        _kv('主办方', '${a?['host'] ?? '-'}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (signup.isNotEmpty)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '报名方式',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          for (final qq
                              in ((signup['qq'] as List?) ?? const []))
                            _contact('QQ群：', '$qq'),
                          for (final ph
                              in ((signup['phone'] as List?) ?? const []))
                            _contact('电话：', '$ph'),
                          for (final tips
                              in ((signup['tips'] as List?) ?? const []))
                            _bullet('$tips'),
                          for (final line
                              in ((signup['contact_lines'] as List?) ??
                                  const []))
                            _bullet('$line'),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '活动说明',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${_data?['hdms'] ?? '暂无活动说明'}',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.7,
                            color: SemColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            k,
            style: TextStyle(fontSize: 13, color: SemColors.textMuted),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  /// 底部报名按钮：只在报名窗口内可点；已报名 / 人满 / 条件不符 / 加载中禁用。
  Widget _signupButton(ActivityState? state) {
    if (_signed) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle_rounded, size: 18),
        label: const Text('已报名'),
      );
    }
    final block = state == ActivityState.signing ? _blockState : null;
    if (block != null) {
      return FilledButton.icon(
        onPressed: null,
        icon: Icon(
          block == SignupBlock.full
              ? Icons.group_off_rounded
              : Icons.block_rounded,
          size: 18,
        ),
        label: Text(block == SignupBlock.full ? '人满，不可报名' : '条件不符'),
      );
    }
    final enabled = state == ActivityState.signing && !_loading && !_signingUp;
    return FilledButton.icon(
      onPressed: enabled ? _confirmSignup : null,
      icon: _signingUp
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.how_to_reg_rounded, size: 18),
      label: Text(
        _signingUp
            ? '提交中…'
            : switch (state) {
                ActivityState.signing => '在线报名',
                ActivityState.upcoming => '未开始报名',
                ActivityState.ended => '报名已结束',
                null => '在线报名',
              },
      ),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 4, color: SemColors.textMuted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: SemColors.textSecondary),
          ),
        ),
      ],
    ),
  );

  Widget _contact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => _copy(label, value),
          icon: Icon(Icons.copy_rounded, size: 16, color: SemColors.textMuted),
        ),
      ],
    ),
  );
}
