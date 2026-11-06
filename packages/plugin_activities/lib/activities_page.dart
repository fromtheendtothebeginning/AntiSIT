import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

enum _ActState { signing, upcoming, ended }

/// 报名按钮的不可报名状态：学校已明确给出原因（名额满 / 资格不符）。
enum SignupBlock { full, ineligible }

/// 学校报名失败文案 → 按钮状态。识别不出返回 null（保持原来的错误弹窗）。
SignupBlock? signupBlockOfError(String msg) {
  if (RegExp(r'名额|人数|已满|满员|人满').hasMatch(msg)) return SignupBlock.full;
  if (RegExp(r'条件|资格|不符|不满足').hasMatch(msg)) return SignupBlock.ineligible;
  return null;
}

/// 报名状态：按本机时间对 bm_start / bm_end 判断。
_ActState _stateOf(Map<String, dynamic> a) {
  DateTime? p(dynamic s) {
    final str = s?.toString() ?? '';
    return str.isEmpty ? null : DateTime.tryParse(str.replaceAll(' ', 'T'));
  }

  final now = DateTime.now();
  final bs = p(a['bm_start']);
  final be = p(a['bm_end']);
  if (bs != null && now.isBefore(bs)) return _ActState.upcoming;
  if (be != null && now.isAfter(be)) return _ActState.ended;
  return _ActState.signing;
}

String _stateText(_ActState s) => switch (s) {
      _ActState.signing => '报名中',
      _ActState.upcoming => '即将报名',
      _ActState.ended => '报名已结束',
    };

Color _stateColor(_ActState s) => switch (s) {
      _ActState.signing => SemColors.success,
      _ActState.upcoming => SemColors.accent,
      _ActState.ended => SemColors.textMuted,
    };

/// 校区胶囊文字；「未标注」（学校没写校区）返回空串，调用方据此不画胶囊。
String campusTagOf(Map a) {
  final c = '${a['campus'] ?? ''}'.trim();
  return c.isEmpty || c == '未标注' || c == 'null' ? '' : c;
}

/// 「大类 · 小类」：缺哪项就不显示哪项，两个都没有返回空串（不画这一行）。
String categoryTextOf(Map a) => [
      '${a['dlmc'] ?? ''}'.trim(),
      '${a['lbmc'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty && s != 'null').join(' · ');

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key});

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _list = [];
  String _query = '';
  int _filter = 0; // 0全部 1报名中 2即将报名 3已结束

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用）。
  bool _fromCache = false;
  bool _refreshFailed = false;

  // 左右滑动切换：0=活动广场，1=我的报名
  final PageController _tabs = PageController();
  int _tab = 0;
  bool _signedLoading = true;
  String? _signedErr;
  List<Map<String, dynamic>> _signed = [];
  bool _signedFromCache = false;
  bool _signedRefreshFailed = false;
  bool _signedLoaded = false; // 本次进入是否已经拉过（懒加载，切到该页才拉）
  bool _signedFetching = false;

  static const _cacheKey = 'activities';
  static const _signedCacheKey = 'activities.signed';

  @override
  void initState() {
    super.initState();
    _restore();
    _restoreSigned();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _switchTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    if (i == 1 && !_signedLoaded) _loadSigned();
  }

  /// 「我的报名」先读本机缓存；是否自动拉新同样看「工具页自动刷新」设置。
  Future<void> _restoreSigned() async {
    final cached = await ToolPageCache.read(_signedCacheKey);
    final list = ((cached?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (list.isNotEmpty) {
      setState(() {
        _signed = list;
        _signedLoading = false;
        _signedFromCache = true;
      });
    }
  }

  Future<void> _loadSigned() async {
    if (_signedFetching) return;
    _signedFetching = true;
    setState(() {
      _signedLoading = true;
      _signedRefreshFailed = false;
      if (_signed.isEmpty) _signedErr = null;
    });
    try {
      final r = await ApiClient.I.signedActivities();
      final list = ((r['activities'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _signed = list;
      _signedLoaded = true;
      _signedFromCache = false;
      await ToolPageCache.write(_signedCacheKey, {'items': list});
    } catch (e) {
      if (_signed.isEmpty) {
        _signedErr = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '我的报名加载失败');
      } else {
        _signedRefreshFailed = true;
      }
    } finally {
      _signedFetching = false;
      if (mounted) setState(() => _signedLoading = false);
    }
  }

  /// 先读本机缓存立即展示，再按「工具页自动刷新」设置决定是否后台拉新。
  Future<void> _restore() async {
    final cached = await ToolPageCache.read(_cacheKey);
    final list = ((((cached?['data'] as Map?)?['activities'] as List?) ?? const []))
        .cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (list.isNotEmpty) {
      setState(() {
        _list = list;
        _loading = false;
        _fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools && _list.isNotEmpty) return;
    await _load();
  }

  Future<void> _load() async {
    if (_loading && _list.isNotEmpty) return;
    setState(() {
      _loading = true;
      _refreshFailed = false;
      if (_list.isEmpty) _err = null;
    });
    try {
      final r = await ApiClient.I.activities();
      final data = r['data'] as Map?;
      _list = ((data?['activities'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _fromCache = false;
      await ToolPageCache.write(_cacheKey, {'data': data});
    } catch (e) {
      // 有缓存时保留旧列表、只在顶部提示失败，不弹窗打断。
      if (_list.isEmpty) {
        _err = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '活动加载失败');
      } else {
        _refreshFailed = true;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _list.where((a) {
      final st = _stateOf(a);
      if (_filter == 1 && st != _ActState.signing) return false;
      if (_filter == 2 && st != _ActState.upcoming) return false;
      if (_filter == 3 && st != _ActState.ended) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final hay = '${a['name']} ${a['host']} ${a['dlmc']} ${a['lbmc']}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final rank = switch (_stateOf(a)) {
          _ActState.signing => 0,
          _ActState.upcoming => 1,
          _ActState.ended => 2,
        };
        final rankB = switch (_stateOf(b)) {
          _ActState.signing => 0,
          _ActState.upcoming => 1,
          _ActState.ended => 2,
        };
        if (rank != rankB) return rank - rankB;
        if (rank == 0) {
          // 报名中按截止时间升序
          return ('${a['bm_end']}'.compareTo('${b['bm_end']}'));
        }
        return '${b['start']}'.compareTo('${a['start']}');
      });
    return list;
  }

  int _countOf(int filter) {
    var n = 0;
    for (final a in _list) {
      final st = switch (_stateOf(a)) {
        _ActState.signing => 1,
        _ActState.upcoming => 2,
        _ActState.ended => 3,
      };
      if (st == filter) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('第二课堂活动')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: GlassTabs(
                labels: const ['活动广场', '我的报名'],
                index: _tab,
                onChanged: (i) => _tabs.animateToPage(i,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic),
                height: 32,
                fontSize: 11.5,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _tabs,
                onPageChanged: _switchTab,
                children: [_marketView(), _signedView()],
              ),
            ),
          ],
        ),
      );

  Widget _marketView() {
    final list = _filtered;
    return PageStateView(
        loading: _loading && _list.isEmpty,
        error: _err,
        empty: !_loading && _err == null && _list.isEmpty,
        emptyText: '暂无活动',
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            children: [
              ToolRefreshBar(
                refreshing: _loading,
                fromCache: _fromCache,
                failed: _refreshFailed,
                onRefresh: _load,
              ),
              TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索活动名称 / 主办 / 类别…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              GlassTabs(
                labels: [
                  for (final (i, label) in const [(0, '全部'), (1, '报名中'), (2, '即将报名'), (3, '已结束')])
                    i == 0 ? label : '$label (${_countOf(i)})'
                ],
                index: _filter,
                onChanged: (i) => setState(() => _filter = i),
                height: 30,
                fontSize: 10.5,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('共 ${list.length} 个活动',
                    style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
              ),
              const SizedBox(height: 6),
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    radius: 10,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ActivityDetailPage(id: '${a['id']}', activity: a))),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Capsule(_stateText(_stateOf(a)), color: _stateColor(_stateOf(a))),
                            if (a['backfill'] as bool? ?? false)
                              Capsule('事后补录', color: SemColors.info),
                            // 没标校区的活动不显示「未标注」胶囊
                            if (campusTagOf(a).isNotEmpty) Capsule(campusTagOf(a)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${a['name']}',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: SemColors.textPrimary)),
                        const SizedBox(height: 4),
                        if (categoryTextOf(a).isNotEmpty)
                          Text(categoryTextOf(a),
                              style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
                        const SizedBox(height: 6),
                        _row('主办：${a['host']}  ·  名额：${a['quota'] ?? '—'}'),
                        const SizedBox(height: 2),
                        _row('活动时间：${_short(a['start'])} ~ ${_short(a['end'])}'),
                        _row('报名窗口：${_short(a['bm_start'])} ~ ${_short(a['bm_end'])}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  /// 「我的报名」：已报名的第二课堂活动（与活动广场左右滑动切换）。
  Widget _signedView() => PageStateView(
        loading: _signedLoading && _signed.isEmpty,
        error: _signedErr,
        empty: !_signedLoading && _signedErr == null && _signed.isEmpty,
        emptyText: '还没有报名活动',
        onRetry: _loadSigned,
        child: RefreshIndicator(
          onRefresh: _loadSigned,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              ToolRefreshBar(
                refreshing: _signedLoading,
                fromCache: _signedFromCache,
                failed: _signedRefreshFailed,
                onRefresh: _loadSigned,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('共 ${_signed.length} 个活动',
                    style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
              ),
              const SizedBox(height: 6),
              for (final a in _signed) _signedCard(a),
            ],
          ),
        ),
      );

  Widget _signedCard(Map<String, dynamic> a) {
    final status = '${a['status_text'] ?? ''}'.trim();
    final cat = categoryTextOf(a);
    final statusColor = switch (status) {
      '已报名' => SemColors.success,
      '报名已满' => SemColors.danger,
      '无需报名' => SemColors.textMuted,
      _ => SemColors.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        radius: 10,
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailPage(id: '${a['id']}', activity: {
                  'id': a['id'],
                  'name': a['name'],
                  'start': a['start'],
                  'end': a['end'],
                  'dlmc': a['dlmc'],
                  'lbmc': a['lbmc'],
                  'signed': true,
                }))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status.isNotEmpty) Capsule(status, color: statusColor),
                if (cat.isNotEmpty) Capsule(cat, color: SemColors.accent),
              ],
            ),
            const SizedBox(height: 8),
            Text('${a['name']}',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: SemColors.textPrimary)),
            const SizedBox(height: 6),
            _row('活动时间：${_short(a['start'])} ~ ${_short(a['end'])}'),
            if ('${a['place'] ?? ''}'.trim().isNotEmpty) _row('地点：${a['place']}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(fontSize: 12, color: SemColors.textMuted),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
      );

  String _short(Object? s) {
    final str = '$s';
    return str.length >= 16 ? str.substring(5, 16) : str;
  }
}

class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({super.key, required this.id, this.activity});

  final String id;

  /// 列表项数据：详情接口只返回 id/hdms/quota/signup，
  /// 名称、时间、校区等元信息从这里取。
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

  /// 已报名：学校详情接口的 signed（他人会话查回来的不透传 true）、列表项自带的
  /// signed，或本次会话刚报过。详情接口对「无需报名」的活动可能回 bm=0，
  /// 不能让合并后的 false 把列表已经确认的「已报名」擦掉。
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
    _data = widget.activity == null ? null : Map<String, dynamic>.from(widget.activity!);
    _load();
  }

  Future<void> _load() async {
    final hasBase = _data != null && _data!.isNotEmpty;
    setState(() {
      _loading = !hasBase;
      _err = null;
    });
    try {
      final r = await ApiClient.I.activityDetail(widget.id);
      // 详情接口结果（完整说明/名额/报名方式）覆盖列表数据；其余元信息保留列表项内容。
      _data = {...?_data, ...?r['data'] as Map<String, dynamic>?};
    } catch (e) {
      // 已有列表项数据时不必因详情拉取失败而整页报错，但要让用户知道失败的原因。
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已复制$label：$value'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ==================== 在线报名 ====================

  /// 报名内容全部由学校系统预填，用户无需填写任何东西；
  /// 写操作防误触，点一下确认直接提交。
  Future<void> _confirmSignup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('确认报名'),
        content: Text('「${_data?['name'] ?? ''}」\n\n报名信息由学校系统自动填写，'
            '提交后进入学校审批流。\n重复提交可能生成多条申请，请勿反复点击。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('确认报名')),
        ],
      ),
    );
    if (ok != true) return;
    final iid = await _submitSignup();
    if (iid != null) _showSignupResult(iid);
  }

  /// 提交报名。成功返回申请编号（学校没给时为空串），失败返回 null——错误提示
  /// （学校原文 / 结果不确定引导）已在这里弹给用户。
  /// 写操作防重：提交中按钮禁用；超时 / 网络错误结果不确定时，引导先确认再决定。
  Future<String?> _submitSignup() async {
    setState(() => _signingUp = true);
    try {
      final r = await ApiClient.I.activitySignup(widget.id);
      final iid = (((r['data'] as Map?)?['instance_id'] ?? '').toString());
      if (mounted) setState(() => _signedInstanceId = iid);
      return iid;
    } on ApiError catch (e) {
      if (!mounted) return null;
      // 学校明确说名额满了 / 条件不符：把原因记到按钮上，不用弹窗反复打扰。
      final block = signupBlockOfError(e.message);
      if (block != null) {
        setState(() => _blocked = block);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ));
        return null;
      }
      final uncertain = e.message.contains('超时') || e.message.contains('网络错误');
      if (uncertain) {
        // 请求可能已经到达学校：再提交一次可能生成重复申请，必须先人工确认。
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
                  onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('知道了')),
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
        content: Text(iid.isEmpty
            ? '申请已进入学校审批流。'
            : '申请已进入学校审批流。\n\n申请编号：$iid\n（可在学工系统的「我的申请」中查看进度）'),
        actions: [
          if (iid.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: iid));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('已复制申请编号'),
                  behavior: SnackBarBehavior.floating,
                ));
              },
              child: const Text('复制编号'),
            ),
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signup = (_data?['signup'] as Map<String, dynamic>?) ?? {};
    final a = _data;
    final state = a == null ? null : _stateOf(a);
    return Scaffold(
      appBar: AppBar(title: const Text('活动详情')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: _signupButton(state),
        ),
      ),
      body: PageStateView(
        loading: _loading,
        error: _err,
        onRetry: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
                        Capsule(_stateText(_stateOf(a)), color: _stateColor(_stateOf(a))),
                        if (_signed) Capsule('已报名', color: SemColors.success),
                        if (a['backfill'] as bool? ?? false) Capsule('事后补录', color: SemColors.info),
                        // 大类 / 小类没标注就不画空胶囊
                        if ('${a['dlmc'] ?? ''}'.trim().isNotEmpty)
                          Capsule('${a['dlmc']}', color: SemColors.accent),
                        if ('${a['lbmc'] ?? ''}'.trim().isNotEmpty)
                          Capsule('${a['lbmc']}', color: SemColors.accent),
                      ],
                    ),
                  if (a != null) const SizedBox(height: 10),
                  Text('${a?['name'] ?? ''}',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: SemColors.textPrimary)),
                  const Divider(height: 24),
                  _kv('活动时间', '${a?['start'] ?? '-'} ~ ${a?['end'] ?? '-'}'),
                  _kv('报名时间', '${a?['bm_start'] ?? '-'} ~ ${a?['bm_end'] ?? '-'}'),
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
                    const Text('报名方式', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final qq in ((signup['qq'] as List?) ?? const []))
                      _contact('QQ群：', '$qq'),
                    for (final ph in ((signup['phone'] as List?) ?? const []))
                      _contact('电话：', '$ph'),
                    for (final tips in ((signup['tips'] as List?) ?? const []))
                      _bullet('$tips'),
                    for (final line in ((signup['contact_lines'] as List?) ?? const []))
                      _bullet('$line'),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('活动说明', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    '${_data?['hdms'] ?? '暂无活动说明'}',
                    style: TextStyle(fontSize: 13, height: 1.7, color: SemColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(k, style: TextStyle(fontSize: 13, color: SemColors.textMuted)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  /// 底部报名按钮：只在报名窗口内可点；已报名 / 人满 / 条件不符 / 加载中禁用。
  Widget _signupButton(_ActState? state) {
    if (_signed) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle_rounded, size: 18),
        label: const Text('已报名'),
      );
    }
    // 只有在报名窗口内才谈得上「人满 / 条件不符」；窗口外仍显示未开始 / 已结束。
    final block = state == _ActState.signing ? _blockState : null;
    if (block != null) {
      return FilledButton.icon(
        onPressed: null,
        icon: Icon(
            block == SignupBlock.full ? Icons.group_off_rounded : Icons.block_rounded,
            size: 18),
        label: Text(block == SignupBlock.full ? '已人满' : '条件不符'),
      );
    }
    final enabled = state == _ActState.signing && !_loading && !_signingUp;
    return FilledButton.icon(
      onPressed: enabled ? _confirmSignup : null,
      icon: _signingUp
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.how_to_reg_rounded, size: 18),
      label: Text(_signingUp
          ? '提交中…'
          : switch (state) {
              _ActState.signing => '在线报名',
              _ActState.upcoming => '未开始报名',
              _ActState.ended => '报名已结束',
              null => '在线报名',
            }),
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
                child: Text(text,
                    style: TextStyle(fontSize: 12, color: SemColors.textSecondary))),
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
