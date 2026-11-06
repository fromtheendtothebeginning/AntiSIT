import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 抢课：正方教务 9.0「学生选课」。
///
/// 流程：选课轮次 → 课程列表（可搜索）→ 展开教学班 → 点击「抢课」后按 1.5 秒
/// 间隔自动提交，直到成功 / 手动停止 / 名额以外需要人工处理的错误。
///
/// 选课是写操作，暂只支持直连模式；服务器模式的开放接口没有选课端点。
class CourseSelectPage extends StatefulWidget {
  const CourseSelectPage({super.key});

  @override
  State<CourseSelectPage> createState() => _CourseSelectPageState();
}

class _CourseSelectPageState extends State<CourseSelectPage> {
  bool _loadingScopes = true;
  String? _scopesErr;
  List<CourseScope> _scopes = [];
  int _scopeIndex = 0;

  final TextEditingController _search = TextEditingController();
  String _keyword = '';
  List<CourseOffer> _offers = [];
  bool _loadingOffers = false;
  String? _offersErr;
  bool _hasMore = false;
  int _offersSeq = 0;

  final Map<String, List<CourseSection>> _sections = {};
  final Set<String> _loadingSections = {};
  final Map<String, String> _sectionErrors = {};
  String? _expanded;

  Timer? _grabTimer;
  CourseOffer? _grabOffer;
  CourseSection? _grabSection;
  int _grabAttempt = 0;
  bool _grabActive = false;
  bool _grabBusy = false;
  String _grabText = '';

  static const int _grabIntervalMs = 1500;
  static const int _grabMaxAttempts = 120;

  CourseScope? get _scope =>
      _scopes.isEmpty || _scopeIndex >= _scopes.length ? null : _scopes[_scopeIndex];

  bool get _isDirect => AppState.I.direct && !AppState.I.demo;

  @override
  void initState() {
    super.initState();
    _loadScopes();
  }

  @override
  void dispose() {
    _grabTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _loadScopes() async {
    if (!_isDirect) {
      setState(() => _loadingScopes = false);
      return;
    }
    _stopGrab(silent: true);
    setState(() {
      _loadingScopes = true;
      _scopesErr = null;
    });
    try {
      final scopes = await ApiClient.I.courseScopes();
      if (!mounted) return;
      setState(() {
        _scopes = scopes;
        _scopeIndex = 0;
        _loadingScopes = false;
        _offers = [];
        _offersErr = null;
        _hasMore = false;
        _sections.clear();
        _sectionErrors.clear();
        _expanded = null;
      });
      if (scopes.isEmpty) return;
      await _loadOffers(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scopesErr = e is ApiError ? e.message : e.toString();
        _loadingScopes = false;
      });
    }
  }

  Future<void> _loadOffers({bool reset = false, bool more = false}) async {
    final scope = _scope;
    if (scope == null || _loadingOffers) return;
    final seq = ++_offersSeq;
    setState(() {
      _loadingOffers = true;
      _offersErr = null;
      if (reset) {
        _offers = [];
        _hasMore = false;
        _sections.clear();
        _sectionErrors.clear();
        _expanded = null;
      }
    });
    try {
      final start = reset ? 0 : _offers.length;
      final list = await ApiClient.I.courseOffers(scope, keyword: _keyword, start: start);
      if (!mounted || seq != _offersSeq) return;
      setState(() {
        _offers = reset ? list : [..._offers, ...list];
        _hasMore = list.length >= 50;
      });
    } catch (e) {
      if (!mounted || seq != _offersSeq) return;
      setState(() => _offersErr = e is ApiError ? e.message : e.toString());
    } finally {
      if (mounted && seq == _offersSeq) {
        setState(() => _loadingOffers = false);
      }
    }
  }

  Future<void> _loadSections(CourseOffer offer, {bool force = false}) async {
    final key = _keyOf(offer);
    if (!force && _sections.containsKey(key)) return;
    if (_loadingSections.contains(key)) return;
    setState(() {
      _loadingSections.add(key);
      _sectionErrors.remove(key);
    });
    try {
      final list = await ApiClient.I.courseSections(offer);
      if (!mounted) return;
      setState(() => _sections[key] = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sectionErrors[key] = e is ApiError ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _loadingSections.remove(key));
    }
  }

  String _keyOf(CourseOffer offer) => '${offer.scopeId}|${offer.id}';

  void _switchScope(int index) {
    if (index == _scopeIndex) return;
    _stopGrab(silent: true);
    setState(() {
      _scopeIndex = index;
      _offers = [];
      _offersErr = null;
      _hasMore = false;
      _sections.clear();
      _sectionErrors.clear();
      _expanded = null;
    });
    _loadOffers(reset: true);
  }

  void _searchNow() {
    _keyword = _search.text.trim();
    _loadOffers(reset: true);
  }

  // ==================== 抢课 ====================

  Future<void> _confirmGrab(CourseOffer offer, CourseSection section) async {
    if (_grabActive) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认抢课'),
        content: Text(
          '课程：${offer.name}\n'
          '教学班：${section.name.isEmpty ? '默认教学班' : section.name}\n\n'
          '将每 ${_grabIntervalMs ~/ 1000} 秒向教务提交一次选课请求，'
          '名额满时会继续等待，直到成功或你手动停止。\n\n'
          '选课是写操作：若出现网络超时等结果不确定的情况，会立即停止并提示你到'
          '「已选课程」确认，不会盲目重试。',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('开始抢课')),
        ],
      ),
    );
    if (ok == true && mounted) _startGrab(offer, section);
  }

  void _startGrab(CourseOffer offer, CourseSection section) {
    _stopGrab(silent: true);
    setState(() {
      _grabOffer = offer;
      _grabSection = section;
      _grabAttempt = 0;
      _grabActive = true;
      _grabBusy = false;
      _grabText = '准备抢课…';
    });
    _grabTimer = Timer.periodic(
      const Duration(milliseconds: _grabIntervalMs),
      (_) => _grabTick(),
    );
    _grabTick();
  }

  Future<void> _grabTick() async {
    final offer = _grabOffer;
    final section = _grabSection;
    if (!_grabActive || _grabBusy || offer == null || section == null) return;
    if (_grabAttempt >= _grabMaxAttempts) {
      _stopGrab(
        message: '已尝试 $_grabMaxAttempts 次，先停下来；稍后可以重新开始',
        success: false,
      );
      return;
    }
    setState(() {
      _grabBusy = true;
      _grabAttempt++;
      _grabText = '第 $_grabAttempt 次提交中…';
    });
    try {
      final result = await ApiClient.I.selectCourse(offer, section);
      if (!mounted || !_grabActive) return;
      switch (result.status) {
        case CourseSelectStatus.success:
        case CourseSelectStatus.alreadySelected:
          _stopGrab(
            message: result.message.isEmpty ? '选课成功' : result.message,
            success: true,
          );
          _loadSections(offer, force: true);
          _loadOffers(reset: true);
        case CourseSelectStatus.noCapacity:
          setState(() => _grabText =
              '第 $_grabAttempt 次 · 名额已满，继续等待…${result.message.isEmpty ? '' : '\n${result.message}'}');
        case CourseSelectStatus.roundClosed:
          _stopGrab(message: result.message.isEmpty ? '当前不属于选课阶段' : result.message);
        case CourseSelectStatus.needCaptcha:
          _stopGrab(message: result.message.isEmpty ? '教务要求验证码，请重新登录后再试' : result.message);
        case CourseSelectStatus.sessionExpired:
          _stopGrab(message: '教务登录已失效，请返回重新进入后重试');
        case CourseSelectStatus.conflict:
        case CourseSelectStatus.creditLimit:
          _stopGrab(message: result.message.isEmpty ? '选课被学校拒绝' : result.message);
        case CourseSelectStatus.networkRetryable:
        case CourseSelectStatus.unknown:
          _stopGrab(
            message: '提交结果不确定，已停止自动重试。请到「已选课程」确认是否已选上'
                '${result.message.isEmpty ? '' : '\n${result.message}'}',
          );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiError ? e.message : e.toString();
      final uncertain = RegExp(r'超时|网络|连接|Socket|timed out', caseSensitive: false)
          .hasMatch(msg);
      _stopGrab(
        message: uncertain
            ? '请求结果不确定，已停止自动重试。请到「已选课程」确认是否已选上\n$msg'
            : msg,
      );
    } finally {
      if (mounted && _grabActive) setState(() => _grabBusy = false);
    }
  }

  void _stopGrab({String? message, bool success = false, bool silent = false}) {
    _grabTimer?.cancel();
    _grabTimer = null;
    final wasActive = _grabActive;
    if (mounted) {
      setState(() {
        _grabActive = false;
        _grabBusy = false;
        _grabOffer = null;
        _grabSection = null;
        _grabText = '';
      });
    } else {
      _grabActive = false;
      _grabBusy = false;
      _grabOffer = null;
      _grabSection = null;
      _grabText = '';
    }
    if (!silent && wasActive && message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? SemColors.success : null,
        duration: Duration(seconds: success ? 3 : 5),
      ));
    }
  }

  Future<void> _showSelected() async {
    final scope = _scope;
    if (scope == null) return;
    try {
      final list = await ApiClient.I.selectedCourses(scope);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已选课程 · ${scope.name}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: SemColors.textPrimary)),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('暂无已选课程',
                            style: TextStyle(color: SemColors.textMuted)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1, color: SemColors.border),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: c.teacher.isEmpty ? null : Text(c.teacher),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErr(context, e, title: '已选课程加载失败');
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('抢课'),
        actions: [
          IconButton(
            tooltip: '已选课程',
            onPressed: _scope == null ? null : _showSelected,
            icon: const Icon(Icons.playlist_add_check_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _scope == null ? null : () => _loadOffers(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !_isDirect
          ? _modeGate()
          : PageStateView(
              loading: _loadingScopes,
              error: _scopesErr,
              empty: !_loadingScopes && _scopesErr == null && _scopes.isEmpty,
              emptyText: '当前没有开放的选课轮次',
              onRetry: _loadScopes,
              child: RefreshIndicator(
                onRefresh: () => _loadOffers(reset: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    if (_scopes.length > 1) _scopeChips(),
                    _searchBar(),
                    if (_grabActive) _grabBanner(),
                    if (_loadingOffers && _offers.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_offersErr != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _offersErr!,
                          style: TextStyle(fontSize: 12.5, color: SemColors.danger),
                        ),
                      ),
                    if (!_loadingOffers && _offers.isEmpty && _offersErr == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            _keyword.isEmpty ? '这个轮次暂时没有课程' : '没有匹配的课程',
                            style: TextStyle(color: SemColors.textMuted),
                          ),
                        ),
                      ),
                    for (final offer in _offers) _offerCard(offer),
                    if (_hasMore)
                      Center(
                        child: TextButton(
                          onPressed: _loadingOffers ? null : () => _loadOffers(more: true),
                          child: const Text('加载更多'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _modeGate() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 44, color: SemColors.textMuted),
              const SizedBox(height: 12),
              Text(
                '抢课需要在直连模式下使用：\n请到「我的 → 连接设置」切换到直连模式，'
                '并确认设备已连接校园网 / 校内 VPN。',
                textAlign: TextAlign.center,
                style: TextStyle(color: SemColors.textMuted, height: 1.7),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectPage()),
                ),
                child: const Text('去连接设置'),
              ),
            ],
          ),
        ),
      );

  Widget _scopeChips() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (var i = 0; i < _scopes.length; i++)
              ChoiceChip(
                label: Text(_scopes[i].name),
                selected: i == _scopeIndex,
                onSelected: (_) => _switchScope(i),
                labelStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      );

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _searchNow(),
                decoration: InputDecoration(
                  hintText: '搜索课程名 / 教师…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _loadingOffers ? null : _searchNow,
              child: const Text('搜索'),
            ),
          ],
        ),
      );

  Widget _grabBanner() {
    final offer = _grabOffer;
    final section = _grabSection;
    if (offer == null || section == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在抢：${offer.name}'
                    '${section.name.isEmpty ? '' : ' · ${section.name}'}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SemColors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(_grabText,
                      style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _stopGrab(message: '已停止抢课'),
              child: const Text('停止'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offerCard(CourseOffer offer) {
    final key = _keyOf(offer);
    final expanded = _expanded == key;
    final sections = _sections[key];
    final loading = _loadingSections.contains(key);
    final sectionErr = _sectionErrors[key];
    final rows = <Widget>[
      if (offer.teacher.isNotEmpty) _row('教师：${offer.teacher}'),
      if (offer.time.isNotEmpty) _row('时间：${offer.time}'),
      if (offer.location.isNotEmpty) _row('地点：${offer.location}'),
      if (offer.credit.isNotEmpty) _row('学分：${offer.credit}'),
    ];
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        setState(() => _expanded = expanded ? null : key);
        if (!expanded) _loadSections(offer);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  offer.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: SemColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              _capacityCapsule(offer.capacity, offer.selected),
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20,
                color: SemColors.textMuted,
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final row in rows) row,
          ],
          if (expanded) ...[
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (sectionErr != null)
              Text(sectionErr,
                  style: TextStyle(fontSize: 12, color: SemColors.danger))
            else if (sections == null || sections.isEmpty)
              Text('暂无教学班数据',
                  style: TextStyle(fontSize: 12, color: SemColors.textMuted))
            else
              for (final section in sections) _sectionRow(offer, section),
          ],
        ],
      ),
    );
  }

  Widget _sectionRow(CourseOffer offer, CourseSection section) {
    final detail = <String>[
      if (section.teacher.isNotEmpty) section.teacher,
      if (section.time.isNotEmpty) section.time,
      if (section.location.isNotEmpty) section.location,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: SemColors.neutralSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        section.name.isEmpty ? '教学班' : section.name,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: SemColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _capacityCapsule(section.capacity, section.selected),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail,
                      style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _grabActive ? null : () => _confirmGrab(offer, section),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('抢课', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _capacityCapsule(int? capacity, int? selected) {
    if (capacity == null && selected == null) return const SizedBox.shrink();
    final full = capacity != null &&
        selected != null &&
        capacity > 0 &&
        selected >= capacity;
    final String text;
    if (full) {
      text = '已满';
    } else if (capacity != null && selected != null) {
      text = '余 ${capacity - selected}';
    } else if (capacity != null) {
      text = '名额 $capacity';
    } else {
      text = '已选 $selected';
    }
    return Capsule(text, color: full ? SemColors.danger : SemColors.success);
  }

  Widget _row(String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: SemColors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
