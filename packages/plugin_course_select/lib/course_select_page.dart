import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

part 'course_select_service.dart';

/// 抢课：正方教务 9.0「学生选课」——选课轮次 → 课程列表（可搜索）→ 展开教学班 → 自动提交抢课。
/// 选课是写操作，只支持直连模式；服务器模式的开放接口没有选课端点。
class CourseSelectPage extends StatefulWidget {
  const CourseSelectPage({super.key});

  @override
  State<CourseSelectPage> createState() => _CourseSelectPageState();
}

class _CourseSelectPageState extends State<CourseSelectPage>
    with _CourseSelectService {
  @override
  CourseScope? get _scope => _scopes.isEmpty || _scopeIndex >= _scopes.length
      ? null
      : _scopes[_scopeIndex];

  /// 能拿选课数据：直连模式，或演示模式（演示走本地假数据）。
  @override
  bool get _isDirect => AppState.I.direct || AppState.I.demo;

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

  /// 查看本轮的已选课程（底部弹层）。
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
                  Text(
                    '已选课程 · ${scope.name}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SemColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '暂无已选课程',
                          style: TextStyle(color: SemColors.textMuted),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: SemColors.border),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle:
                                c.teacher.isEmpty ? null : Text(c.teacher),
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

  @override
  Widget build(BuildContext context) {
    // 整页监听 AppState：顶栏样式开关改完要连 Scaffold 一起重建。
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 先算顶栏留白：body 里的 MediaQuery 已扣掉状态栏。
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('抢课'),
            actions: [
              IconButton(
                tooltip: '已选课程',
                onPressed: _scope == null ? null : _showSelected,
                icon: const Icon(Icons.playlist_add_check_rounded),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed:
                    _scope == null ? null : () => _loadOffers(reset: true),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: GlassFadedBody(
            barHeight: topInset,
            child: !_isDirect
              // 非直连时整块提示：用 Padding 顶出悬浮顶栏。
              ? Padding(
                  padding: EdgeInsets.only(top: topInset),
                  child: _modeGate(),
                )
              : PageStateView(
                  loading: _loadingScopes,
                  error: _scopesErr,
                  empty:
                      !_loadingScopes && _scopesErr == null && _scopes.isEmpty,
                  emptyText: '当前没有开放的选课轮次',
                  onRetry: _loadScopes,
                  child: RefreshIndicator(
                    // 下拉刷新圈从悬浮顶栏底边开始，不贴着屏幕最上沿。
                    edgeOffset: topInset,
                    onRefresh: () => _loadOffers(reset: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 24),
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
                              style: TextStyle(
                                fontSize: 12.5,
                                color: SemColors.danger,
                              ),
                            ),
                          ),
                        if (!_loadingOffers &&
                            _offers.isEmpty &&
                            _offersErr == null)
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
                              onPressed: _loadingOffers
                                  ? null
                                  : () => _loadOffers(more: true),
                              child: const Text('加载更多'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
          ),
        );
      },
    );
  }

  /// 非直连模式的说明与跳转。
  Widget _modeGate() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 44,
                color: SemColors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                '抢课需要在直连模式下使用：\n请到「我的 → 连接设置」切换到直连模式，'
                '并确认设备已连接校园网 / 校内 VPN。',
                textAlign: TextAlign.center,
                style: TextStyle(color: SemColors.textMuted, height: 1.7),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ConnectPage())),
                child: const Text('去连接设置'),
              ),
            ],
          ),
        ),
      );

  /// 选课轮次切换条。
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

  /// 课程搜索框。
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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

  /// 抢课进行中的横幅：进度文案 + 停止按钮。
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
                      color: SemColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _grabText,
                    style: TextStyle(
                      fontSize: 12,
                      color: SemColors.textSecondary,
                    ),
                  ),
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

  /// 课程卡片：点开加载教学班并展开。
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
                    color: SemColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _capacityCapsule(offer.capacity, offer.selected),
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
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
              Text(
                sectionErr,
                style: TextStyle(fontSize: 12, color: SemColors.danger),
              )
            else if (sections == null || sections.isEmpty)
              Text(
                '暂无教学班数据',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted),
              )
            else
              for (final section in sections) _sectionRow(offer, section),
          ],
        ],
      ),
    );
  }

  /// 教学班一行：教师 / 时间 / 地点 + 名额 + 抢课按钮。
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
                          color: SemColors.textPrimary,
                        ),
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
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SemColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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

  /// 名额胶囊：已满标红，否则显示余量。
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

  /// 课程卡片里的一行元信息。
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
