import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'score_credits_view.dart';
import 'score_overview_view.dart';
import 'score_target_settings_page.dart';

/// 第二课堂分：分数概览与加分明细两页，左右滑动切换（复刻网站单面板排版）。
class ScorePage extends StatefulWidget {
  const ScorePage({super.key});

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _data;

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用）。
  bool _fromCache = false;
  bool _refreshFailed = false;

  /// 达标线按入学年级（nj）取：远端配置 / 本机自定义优先，未配置时用默认规则。
  ScoreTargetPolicy _policy = const ScoreTargetPolicy();

  /// 当前生效的入学年：教务返回优先，直连模式手填兜底。
  String _cohort = '';

  int _tab = 0; // 0=分数概览，1=加分明细

  /// 连续位置（单位 = 页）：滑块自己的弹簧、用户拖滑块都会写到这里，页面据此实时平移。
  final ValueNotifier<double> _pos = ValueNotifier<double>(0);

  /// 页面横滑时驱动切换器滑块的位置（默认行为）；null = 交还滑块自己的弹簧。
  final ValueNotifier<double?> _dragPos = ValueNotifier<double?>(null);
  double _dragFrom = 0;
  double _screenW = 1;
  bool _creditsLoading = true;
  String? _creditsErr;
  List<Map<String, dynamic>> _credits = [];
  bool _creditsFromCache = false;
  bool _creditsRefreshFailed = false;
  bool _creditsLoaded = false;
  bool _creditsFetching = false;

  // 加分明细的筛选：搜索（支持拼音）+ 大类 / 类别标签（类别选项随大类级联收窄）。
  String _creditsQuery = '';
  String _creditDl = '';
  String _creditLb = '';

  static const _cacheKey = 'score';
  static const _creditsCacheKey = 'score.credits';

  @override
  void initState() {
    super.initState();
    _restore();
    _restoreCredits();
  }

  @override
  void dispose() {
    _pos.dispose();
    _dragPos.dispose();
    super.dispose();
  }

  /// 页面横滑：驱动切换器滑块；「界面实时跟着滑块切换」打开时页面也跟手指走。
  void _onPageDragStart(DragStartDetails _) {
    final w = MediaQuery.sizeOf(context).width;
    _screenW = w <= 0 ? 1 : w;
    _dragFrom = _pos.value;
    _dragPos.value = _dragFrom;
  }

  void _onPageDragUpdate(DragUpdateDetails d) {
    const last = 1.0; // 两页：0..1
    final raw = (_dragPos.value ?? _dragFrom) - d.delta.dx / _screenW;
    final next = raw.isFinite ? raw.clamp(0.0, last) : _dragFrom;
    _dragPos.value = next;
    // 拖动中只动位置、不 setState：跟手视觉由 _pos 驱动，落位在松手时一次定。
    if (AppState.I.followSlider) {
      _pos.value = next;
    }
  }

  void _onPageDragEnd(DragEndDetails d) {
    const last = 1;
    final v = _dragPos.value ?? _tab.toDouble();
    // 与首页底栏同一套：慢拖就近落位，快速甩动借动量多滑一格
    final speed = (-d.velocity.pixelsPerSecond.dx / _screenW).clamp(-8.0, 8.0);
    var target = v.round().clamp(0, last);
    final next = target + (speed > 0 ? 1 : -1);
    if (speed.abs() >= 5.0 && next >= 0 && next <= last) target = next;
    _dragPos.value = null; // 交还弹簧：滑块从当前位置弹到落点（页面跟着同一条弹簧回弹）
    if (target != _tab) HapticFeedback.selectionClick();
    _setTab(target);
  }

  /// 切换器点选 / 拖动落位都走这里。
  void _onTabChanged(int i) => _setTab(i);

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    if (i == 1 && !_creditsLoaded) _loadCredits();
  }

  /// 「加分明细」先读本机缓存立即展示。
  Future<void> _restoreCredits() async {
    final cached = await ToolPageCache.read(_creditsCacheKey);
    final list = ((cached?['records'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (list.isNotEmpty) {
      setState(() {
        _credits = _sortCreditsNewestFirst(list);
        _creditsLoading = false;
        _creditsFromCache = true;
      });
    }
  }

  /// 加分明细按时间**从最新开始**排：优先活动开始时间（start），没有就用记录时间（date），
  /// 都没有的排最后；两类时间都是 `yyyy-MM-dd HH:mm:ss`，字典序即时间序。
  static List<Map<String, dynamic>> _sortCreditsNewestFirst(
    List<Map<String, dynamic>> list,
  ) {
    String key(Map<String, dynamic> r) =>
        '${(r['start'] ?? '').toString().trim().isNotEmpty ? r['start'] : r['date'] ?? ''}'
            .trim();
    final sorted = [...list]..sort((a, b) {
        final ka = key(a);
        final kb = key(b);
        if (ka == kb) return 0;
        if (ka.isEmpty) return 1; // 没有时间的排最后
        if (kb.isEmpty) return -1;
        return kb.compareTo(ka); // 降序 = 最新在前
      });
    return sorted;
  }

  Future<void> _loadCredits() async {
    if (_creditsFetching) return;
    _creditsFetching = true;
    setState(() {
      _creditsLoading = true;
      _creditsRefreshFailed = false;
      if (_credits.isEmpty) _creditsErr = null;
    });
    try {
      final r = await ApiClient.I.creditRecords();
      final list = ((r['records'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      _credits = _sortCreditsNewestFirst(list);
      _creditsLoaded = true;
      _creditsFromCache = false;
      await ToolPageCache.write(_creditsCacheKey, {'records': list});
    } catch (e) {
      if (_credits.isEmpty) {
        _creditsErr = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '加分明细加载失败');
      } else {
        _creditsRefreshFailed = true;
      }
    } finally {
      _creditsFetching = false;
      if (mounted) setState(() => _creditsLoading = false);
    }
  }

  /// 先读本机缓存立即展示，再按「工具页自动刷新」设置决定是否拉新。
  Future<void> _restore() async {
    final cached = await ToolPageCache.read(_cacheKey);
    final data = (cached?['data'] as Map?)?.cast<String, dynamic>();
    if (!mounted) return;
    if (data != null) {
      // 分数先出来，达标线胶囊随后补（读本地规则很快，远端配置最长 3 秒）。
      setState(() {
        _data = data;
        _loading = false;
        _fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools) {
      if (data == null) {
        await _load();
      } else {
        final targets = await ScoreTargets.load();
        if (!mounted) return;
        setState(() => _applyCohort(targets, data));
      }
      return;
    }
    await _load();
  }

  /// 达标线策略与当前年级：直连手填的年级优先，其次教务返回的年级。
  void _applyCohort(ScoreTargets targets, Map<String, dynamic>? data) {
    final student = data?['student'];
    final apiNj = student is Map ? '${student['nj'] ?? ''}'.trim() : '';
    final manual = AppState.I.direct ? AppState.I.creds.grade.trim() : '';
    _cohort = manual.isNotEmpty ? manual : apiNj;
    _policy = targets.forCohort(_cohort);
  }

  Future<void> _load() async {
    if (_loading && _data != null) return;
    setState(() {
      _loading = true;
      _refreshFailed = false;
      if (_data == null) _err = null;
    });
    try {
      // 达标线配置和分数并发拉：配置走公网、分数走校园链路，互不拖慢。
      final targetsFuture = ScoreTargets.load();
      final r = await ApiClient.I.score();
      final targets = await targetsFuture;
      _data = r['data'] as Map<String, dynamic>?;
      _applyCohort(targets, _data);
      _fromCache = false;
      ToolCache.score = ToolCache.scoreOf(_data);
      AppState.I.studentInfo = ToolCache.score?.student;
      await ToolPageCache.write(_cacheKey, {'data': _data});
    } catch (e) {
      // 有缓存时保留旧数据、只在顶部提示失败，不弹窗打断。
      if (_data == null) {
        _err = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '成绩加载失败');
      } else {
        _refreshFailed = true;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 三级页面：调整本机达标线；返回后重拉分数与策略。
  Future<void> _openTargetSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ScoreTargetSettingsPage(cohort: _cohort.isEmpty ? null : _cohort),
      ),
    );
    if (mounted) _load();
  }

  /// 换大类后，已选的类别若不再属于它就清掉。
  void _setCreditDl(String d) {
    setState(() {
      _creditDl = d;
      if (d.isNotEmpty &&
          _creditLb.isNotEmpty &&
          !creditLbOptions(_credits, d).contains(_creditLb)) {
        _creditLb = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 整页监听 AppState：悬浮玻璃顶栏开关改完要连 Scaffold 一起重建
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已被扣掉状态栏）
        final topInset = glassTopInset(context);
        // 两页 Widget 只在本页 build 时建一次：拖动中每帧只挪 Positioned，不重复构建两整页。
        final pages = <Widget>[
          buildScoreOverview(
            topInset: topInset,
            tabsRowHeight: _tabsRowHeight,
            data: _data,
            policy: _policy,
            loading: _loading,
            error: _err,
            fromCache: _fromCache,
            refreshFailed: _refreshFailed,
            onRefresh: _load,
          ),
          buildScoreCredits(
            topInset: topInset,
            tabsRowHeight: _tabsRowHeight,
            credits: _credits,
            loading: _creditsLoading,
            error: _creditsErr,
            fromCache: _creditsFromCache,
            refreshFailed: _creditsRefreshFailed,
            query: _creditsQuery,
            dl: _creditDl,
            lb: _creditLb,
            onQueryChanged: (v) => setState(() => _creditsQuery = v),
            onDlChanged: _setCreditDl,
            onLbChanged: (v) => setState(() => _creditLb = v),
            onRefresh: _loadCredits,
          ),
        ];
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('第二课堂分'),
            actions: [
              IconButton(
                tooltip: '达标线设置',
                icon: const Icon(Icons.tune_rounded),
                onPressed: _openTargetSettings,
              ),
            ],
          ),
          body: GlassFadedBody(
            barHeight: topInset,
            // 分段切换器悬浮在顶栏下方：下划收起、上滑展开（见 FloatingTabsHeader）
            child: FloatingTabsHeader(
              topInset: topInset,
              header: _tabsRow(),
              dragPosition: _dragPos,
              // 不用 PageView：它和切换器滑块互相抢手势 / 回弹。一个连续位置 _pos 驱动两页平移。
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onPageDragStart,
                onHorizontalDragUpdate: _onPageDragUpdate,
                onHorizontalDragEnd: _onPageDragEnd,
                onHorizontalDragCancel: () => _dragPos.value = null,
                child: ValueListenableBuilder<double>(
                  valueListenable: _pos,
                  builder: (context, rawPos, _) {
                    // 位置兜底：NaN / 越界钳回安全范围；不夹到 0..1，保留弹簧过冲的手感。
                    final safePos = rawPos.isFinite ? rawPos : _tab.toDouble();
                    final pos = AppState.I.followSlider
                        ? safePos.clamp(-0.25, 1.25)
                        : _tab.toDouble();
                    final w = MediaQuery.sizeOf(context).width;
                    return Stack(
                      children: [
                        for (var k = 0; k < pages.length; k++)
                          // 用 Positioned 摆位而不是 Transform：少一层合成层，与毛玻璃顶栏叠着更稳。
                          Positioned(
                            left: (k - pos) * w,
                            top: 0,
                            bottom: 0,
                            width: w,
                            child: Offstage(
                              offstage: (k - pos).abs() >= 0.999,
                              // 隐藏的那页别跑动画（转圈、弹簧都不该在后台空转）
                              child: TickerMode(
                                enabled: (k - pos).abs() < 0.999,
                                child: pages[k],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 悬浮切换器占的高度（列表顶部要让出这么多，内容才不会被它压住）。
  static const double _tabsRowHeight = 50;

  Widget _tabsRow() => GlassTabs(
    // 外层玻璃胶囊由 FloatingTabsHeader 提供，自己不再画一层底 / 描边
    flat: true,
    // 滑块位置写出去（拖动 / 弹簧都会写）：页面据此实时跟手
    position: _pos,
    // 页面横滑时驱动滑块（默认行为）
    dragPosition: _dragPos,
    labels: const ['分数概览', '加分明细'],
    index: _tab,
    onChanged: _onTabChanged,
    height: 32,
    fontSize: 11.5,
  );
}
