import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'activities_cards.dart';
import 'activities_detail_page.dart';
import 'activities_state.dart';

/// 二课活动页：活动广场与我的报名两页，可左右滑动切换。
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

  /// 类别筛选：一级（大类）→ 二级（类别）级联；'' = 全部。
  String _dl = '';
  String _lb = '';

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用）。
  bool _fromCache = false;
  bool _refreshFailed = false;

  /// 左右滑动切换：0=活动广场，1=我的报名。
  int _tab = 0;

  /// 连续位置（单位 = 页），由滑块与横滑手势共同写入。
  final ValueNotifier<double> _pos = ValueNotifier<double>(0);

  /// 页面横滑时驱动切换器滑块的位置；null = 交还滑块自己的弹簧。
  final ValueNotifier<double?> _dragPos = ValueNotifier<double?>(null);
  double _dragFrom = 0;
  double _screenW = 1;
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
    _pos.dispose();
    _dragPos.dispose();
    super.dispose();
  }

  /// 页面横滑开始：记下起点与屏宽。
  void _onPageDragStart(DragStartDetails _) {
    final w = MediaQuery.sizeOf(context).width;
    _screenW = w <= 0 ? 1 : w;
    _dragFrom = _pos.value;
    _dragPos.value = _dragFrom;
  }

  /// 页面横滑中：只更新位置，不切页（不 setState）。
  void _onPageDragUpdate(DragUpdateDetails d) {
    const last = 1.0; // 两页：0..1
    final raw = (_dragPos.value ?? _dragFrom) - d.delta.dx / _screenW;
    final next = raw.isFinite ? raw.clamp(0.0, last) : _dragFrom;
    _dragPos.value = next;
    if (AppState.I.followSlider) {
      _pos.value = next;
    }
  }

  /// 页面横滑结束：慢拖就近落位，快速甩动借动量多滑一格。
  void _onPageDragEnd(DragEndDetails d) {
    const last = 1;
    final v = _dragPos.value ?? _tab.toDouble();
    final speed = (-d.velocity.pixelsPerSecond.dx / _screenW).clamp(-8.0, 8.0);
    var target = v.round().clamp(0, last);
    final next = target + (speed > 0 ? 1 : -1);
    if (speed.abs() >= 5.0 && next >= 0 && next <= last) target = next;
    _dragPos.value = null; // 交还弹簧
    if (target != _tab) HapticFeedback.selectionClick();
    _setTab(target);
  }

  /// 切换器点选 / 拖动落位都走这里。
  void _onTabChanged(int i) {
    _setTab(i);
  }

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    if (i == 1 && !_signedLoaded) _loadSigned();
  }

  /// 「我的报名」先读本机缓存。
  Future<void> _restoreSigned() async {
    final cached = await ToolPageCache.read(_signedCacheKey);
    final list = ((cached?['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (list.isNotEmpty) {
      setState(() {
        _signed = list;
        _signedLoading = false;
        _signedFromCache = true;
      });
    }
  }

  /// 拉「我的报名」列表并写缓存。
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
      final list = ((r['activities'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
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
    final list =
        ((((cached?['data'] as Map?)?['activities'] as List?) ?? const []))
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

  /// 拉活动广场列表并写缓存；有缓存时失败只在顶部提示。
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
      _list = ((data?['activities'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      _fromCache = false;
      await ToolPageCache.write(_cacheKey, {'data': data});
    } catch (e) {
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

  /// 按状态 / 类别 / 关键词过滤，报名中在前、同组按时间排序。
  List<Map<String, dynamic>> get _filtered {
    var list = _list.where((a) {
      final st = activityStateOf(a);
      if (_filter == 1 && st != ActivityState.signing) return false;
      if (_filter == 2 && st != ActivityState.upcoming) return false;
      if (_filter == 3 && st != ActivityState.ended) return false;
      if (_dl.isNotEmpty && '${a['dlmc'] ?? ''}'.trim() != _dl) return false;
      if (_lb.isNotEmpty && '${a['lbmc'] ?? ''}'.trim() != _lb) return false;
      return true;
    }).toList();
    // 搜索支持拼音：活动名 / 主办 / 类别都能用全拼或首字母命中
    list = filterByPinyin(
      list,
      (a) => '${a['name']} ${a['host']} ${a['dlmc']} ${a['lbmc']}',
      _query,
    );
    list.sort((a, b) {
      final rank = switch (activityStateOf(a)) {
        ActivityState.signing => 0,
        ActivityState.upcoming => 1,
        ActivityState.ended => 2,
      };
      final rankB = switch (activityStateOf(b)) {
        ActivityState.signing => 0,
        ActivityState.upcoming => 1,
        ActivityState.ended => 2,
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

  /// 活动里出现过的一级类别（保序去重）。
  List<String> get _dlOptions {
    final seen = <String>{};
    final out = <String>[];
    for (final a in _list) {
      final d = '${a['dlmc'] ?? ''}'.trim();
      if (d.isNotEmpty && seen.add(d)) out.add(d);
    }
    return out;
  }

  /// 二级类别选项：选了一级就只列该大类下的（级联）。
  List<String> get _lbOptions {
    final seen = <String>{};
    final out = <String>[];
    for (final a in _list) {
      if (_dl.isNotEmpty && '${a['dlmc'] ?? ''}'.trim() != _dl) continue;
      final l = '${a['lbmc'] ?? ''}'.trim();
      if (l.isNotEmpty && seen.add(l)) out.add(l);
    }
    return out;
  }

  void _setDl(String d) {
    setState(() {
      _dl = d;
      // 换一级类别后，已选的二级若不再属于它就清掉
      if (d.isNotEmpty && _lb.isNotEmpty && !_lbOptions.contains(_lb)) _lb = '';
    });
  }

  int _countOf(int filter) {
    var n = 0;
    for (final a in _list) {
      final st = switch (activityStateOf(a)) {
        ActivityState.signing => 1,
        ActivityState.upcoming => 2,
        ActivityState.ended => 3,
      };
      if (st == filter) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final scan = PluginRegistry.I.capability<ScanCapability>(PluginIds.scan);
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final topInset = glassTopInset(context);
        final pages = <Widget>[_marketView(topInset), _signedView(topInset)];
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('第二课堂活动'),
            actions: [
              // 扫一扫：扫一扫插件在就显示（按能力取用，不 import 它的包）
              if (scan != null)
                IconButton(
                  tooltip: '扫一扫',
                  onPressed: () => scan.open(context),
                  icon: const Icon(Icons.qr_code_scanner_outlined),
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
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onPageDragStart,
                onHorizontalDragUpdate: _onPageDragUpdate,
                onHorizontalDragEnd: _onPageDragEnd,
                onHorizontalDragCancel: () => _dragPos.value = null,
                child: ValueListenableBuilder<double>(
                  valueListenable: _pos,
                  builder: (context, rawPos, _) {
                    // 位置兜底：NaN 回落到落位页；跟随滑块时只钳到安全范围，
                    // 不夹到 0..1（弹簧本身带过冲，页面跟着它一起回弹）。
                    final safePos = rawPos.isFinite ? rawPos : _tab.toDouble();
                    final pos = AppState.I.followSlider
                        ? safePos.clamp(-0.25, 1.25)
                        : _tab.toDouble();
                    final w = MediaQuery.sizeOf(context).width;
                    return Stack(
                      children: [
                        for (var k = 0; k < pages.length; k++)
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
    flat: true,
    position: _pos,
    dragPosition: _dragPos,
    labels: const ['活动广场', '我的报名'],
    index: _tab,
    onChanged: _onTabChanged,
    height: 32,
    fontSize: 11.5,
  );

  /// 活动广场：搜索 + 状态 / 类别筛选 + 活动卡片。
  Widget _marketView(double topInset) {
    final list = _filtered;
    return PageStateView(
      loading: _loading && _list.isEmpty,
      error: _err,
      empty: !_loading && _err == null && _list.isEmpty,
      emptyText: '暂无活动',
      onRetry: _load,
      child: RefreshIndicator(
        // 刷新圈落在悬浮切换器下面，别贴着屏幕最上沿（issue #14）
        edgeOffset: topInset + _tabsRowHeight,
        onRefresh: _load,
        child: ListView(
          key: const PageStorageKey<String>('activities_market'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            12,
            4 + topInset + _tabsRowHeight,
            12,
            20,
          ),
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
                hintText: '搜索活动名称 / 主办 / 类别，支持拼音…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),
            GlassTabs(
              labels: [
                for (final (i, label) in const [
                  (0, '全部'),
                  (1, '报名中'),
                  (2, '即将报名'),
                  (3, '已结束'),
                ])
                  i == 0 ? label : '$label (${_countOf(i)})',
              ],
              index: _filter,
              onChanged: (i) => setState(() => _filter = i),
              height: 30,
              fontSize: 10.5,
            ),
            const SizedBox(height: 8),
            TagFilterRow(
              title: '一级类别',
              labels: _dlOptions,
              selected: _dl,
              onSelected: _setDl,
            ),
            const SizedBox(height: 4),
            TagFilterRow(
              title: '二级类别',
              labels: _lbOptions,
              selected: _lb,
              onSelected: (v) => setState(() => _lb = v),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${list.length} 个活动',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted),
              ),
            ),
            const SizedBox(height: 6),
            if (list.isEmpty && _list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    '没有符合条件的活动',
                    style: TextStyle(fontSize: 13, color: SemColors.textMuted),
                  ),
                ),
              ),
            for (final a in list)
              ActivityMarketCard(
                activity: a,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ActivityDetailPage(id: '${a['id']}', activity: a),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 「我的报名」：已报名的第二课堂活动（与活动广场左右滑动切换）。
  Widget _signedView(double topInset) => PageStateView(
    loading: _signedLoading && _signed.isEmpty,
    error: _signedErr,
    empty: !_signedLoading && _signedErr == null && _signed.isEmpty,
    emptyText: '还没有报名活动',
    onRetry: _loadSigned,
    child: RefreshIndicator(
      // 刷新圈落在悬浮切换器下面，别贴着屏幕最上沿（issue #14）
      edgeOffset: topInset + _tabsRowHeight,
      onRefresh: _loadSigned,
      child: ListView(
        key: const PageStorageKey<String>('activities_signed'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 8 + topInset + _tabsRowHeight, 12, 20),
        children: [
          ToolRefreshBar(
            refreshing: _signedLoading,
            fromCache: _signedFromCache,
            failed: _signedRefreshFailed,
            onRefresh: _loadSigned,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '共 ${_signed.length} 个活动',
              style: TextStyle(fontSize: 12, color: SemColors.textMuted),
            ),
          ),
          const SizedBox(height: 6),
          for (final a in _signed)
            SignedActivityCard(
              activity: a,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActivityDetailPage(
                    id: '${a['id']}',
                    activity: {
                      'id': a['id'],
                      'name': a['name'],
                      'start': a['start'],
                      'end': a['end'],
                      'dlmc': a['dlmc'],
                      'lbmc': a['lbmc'],
                      'signed': true,
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
