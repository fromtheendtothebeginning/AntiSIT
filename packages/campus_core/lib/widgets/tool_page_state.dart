import 'package:flutter/widgets.dart';

import '../api_error.dart';
import '../app_state.dart';
import '../tool_page_cache.dart';
import 'common.dart';

/// 工具页（成绩 / 考试 / 学业 / 活动…）共用的「缓存先展示 → 后台刷新」状态机。
///
/// 各页原本各自抄一份 `_loading / _err / _fromCache / _refreshFailed` + try/catch/finally；
/// 这里收口成一套：子类只提供缓存键、缓存应用、数据是否有值、拉取逻辑与错误标题。
/// 进入页面先显示上次缓存，再按「工具页自动刷新」决定是否后台拉新；刷新失败时保留旧数据，
/// 只在顶部 `ToolRefreshBar` 提示，整页失败（且无缓存）才进错误态 + [showErr]。
abstract class ToolPageState<W extends StatefulWidget> extends State<W> {
  bool loading = true;
  String? error;
  bool fromCache = false;
  bool refreshFailed = false;

  /// 缓存键；带筛选条件的页面按当前筛选条件返回（切筛选先展示该条件上次的结果）。
  String get cacheKey;

  /// 无缓存且拉取失败时的弹窗标题。
  String get errorTitle;

  /// 当前页面是否已有可展示的数据（列表非空 / 对象非空）。
  bool get hasData;

  /// 把缓存里的值应用到页面字段；返回是否拿到了可用数据。
  bool applyCache(Map<String, dynamic>? cached);

  /// 拉数据并写缓存。返回 false = 本次结果作废（例如期间切了筛选条件），不覆盖缓存。
  /// 抛出的异常由基类统一处理。
  Future<bool> fetchData();

  /// 有缓存但「工具页自动刷新」关闭时的补充动作（如分数页读本地达标线）。
  Future<void> onCacheOnly() async {}

  @override
  void initState() {
    super.initState();
    restore();
  }

  /// 先读缓存立即展示，再按设置决定是否刷新。筛选条件变化后可再调一次。
  Future<void> restore() async {
    final cached = await ToolPageCache.read(cacheKey);
    if (!mounted) return;
    final applied = applyCache(cached);
    if (applied) {
      setState(() {
        loading = false;
        fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools && applied) {
      await onCacheOnly();
      return;
    }
    await refresh();
  }

  /// 刷新（下拉、重试、筛选切换都调它）。
  /// [force] = true 用于「写操作成功后必须重拉」：即使页面正显示 loading 也继续。
  Future<void> refresh({bool force = false}) async {
    if (!force && loading && hasData) return;
    setState(() {
      loading = true;
      refreshFailed = false;
      if (!hasData) error = null;
    });
    try {
      final applied = await fetchData();
      if (applied) fromCache = false;
    } catch (e) {
      // 有缓存时保留旧数据、只在顶部提示失败，不弹窗打断。
      if (!hasData) {
        error = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: errorTitle);
      } else {
        refreshFailed = true;
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
