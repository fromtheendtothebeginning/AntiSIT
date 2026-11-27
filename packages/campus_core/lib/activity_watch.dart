import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_state.dart';
import 'secure_store.dart';

/// 第二课堂活动提醒的规则：只按分类筛选（大类 / 小类，空集合 = 不限）。
@immutable
class ActivityWatchRule {
  const ActivityWatchRule({
    this.enabled = false,
    this.dl = const {},
    this.lb = const {},
  });

  final bool enabled;

  /// 一级类别（活动里的 `dlmc`），空集合 = 不限。
  final Set<String> dl;

  /// 二级类别（活动里的 `lbmc`），空集合 = 不限。
  final Set<String> lb;

  /// 选中了几个分类条件（0 = 还没选，等于不筛）。
  int get categoryCount => dl.length + lb.length;

  /// 已经打开开关但一个分类都没选：界面提示「先选分类」。
  bool get needsCategories => enabled && categoryCount == 0;

  ActivityWatchRule copyWith({
    bool? enabled,
    Set<String>? dl,
    Set<String>? lb,
  }) => ActivityWatchRule(
    enabled: enabled ?? this.enabled,
    dl: dl ?? this.dl,
    lb: lb ?? this.lb,
  );

  /// 活动是否命中规则：只勾了大类就按大类，只勾了小类就按小类，两个都勾要同时满足。
  bool matches(Map<String, dynamic> a) {
    final d = '${a['dlmc'] ?? ''}'.trim();
    final l = '${a['lbmc'] ?? ''}'.trim();
    if (dl.isNotEmpty && !dl.contains(d)) return false;
    if (lb.isNotEmpty && !lb.contains(l)) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'dl': dl.toList(),
    'lb': lb.toList(),
  };

  static ActivityWatchRule fromJson(Map<String, dynamic>? j) =>
      ActivityWatchRule(
        enabled: j?['enabled'] == true,
        dl: {for (final e in (j?['dl'] as List?) ?? const []) '$e'.trim()}
          ..removeWhere((s) => s.isEmpty),
        lb: {for (final e in (j?['lb'] as List?) ?? const []) '$e'.trim()}
          ..removeWhere((s) => s.isEmpty),
      );

  @override
  bool operator ==(Object other) =>
      other is ActivityWatchRule &&
      other.enabled == enabled &&
      setEquals(other.dl, dl) &&
      setEquals(other.lb, lb);

  @override
  int get hashCode =>
      Object.hash(enabled, Object.hashAll(dl), Object.hashAll(lb));
}

/// 一次检查的结果。
@immutable
class ActivityWatchResult {
  const ActivityWatchResult({
    this.fetched = 0,
    this.matched = const [],
    this.firstRun = false,
    this.error,
  });

  /// 本次从服务器拉到的活动数。
  final int fetched;

  /// 命中规则、且此前没见过的活动（新活动）。
  final List<Map<String, dynamic>> matched;

  /// 第一次检查（只建基线，不提醒）。
  final bool firstRun;

  /// 拉取失败原因（有缓存/上次结论时不清空）。
  final String? error;
}

/// 第二课堂新活动提醒：每小时检查一次活动看板，命中用户选的分类就弹通知。
///
/// 检查逻辑放在 campus_core（而不是活动插件）里，是因为它要在**后台 isolate** 里跑：
/// 宿主注册的定时任务直接调这里，不需要拉起整套插件注册表。
class ActivityWatchService extends ChangeNotifier {
  ActivityWatchService._();
  static final ActivityWatchService I = ActivityWatchService._();

  static const String _kRule = 'activities.watch_rule';
  static const String _kSeen = 'activities.watch_seen';
  static const String _channelId = 'activity_watch';
  static const String _channelName = '第二课堂新活动';
  static const String _channelDesc = '选中分类出现新活动时提醒';

  /// 通知 id 高位：避开上课提醒（< 2^30）与拓展通知（0x40000000）的区间。
  static const int notifyId = 0x60000001;

  /// 记住多少个活动 id（够覆盖一学期的新活动）。
  static const int maxSeen = 800;

  ActivityWatchRule rule = const ActivityWatchRule();
  bool loaded = false;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;

  /// 上次检查时间与结果（设置页显示用）。
  DateTime? lastCheck;
  int lastFetched = 0;
  int lastMatched = 0;
  String? lastError;

  bool get enabled => rule.enabled;

  /// 读规则并确保通知渠道就绪。
  Future<void> load() async {
    if (loaded) return;
    final sp = await SharedPreferences.getInstance();
    rule = ActivityWatchRule.fromJson(_decode(sp.getString(_kRule)));
    loaded = true;
    notifyListeners();
  }

  /// 保存规则（开关 / 分类变化后立刻生效，后台任务按它筛）。
  Future<void> setRule(ActivityWatchRule next) async {
    if (next == rule) return;
    rule = next;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kRule, jsonEncode(next.toJson()));
    notifyListeners();
  }

  Future<void> setEnabled(bool v) => setRule(rule.copyWith(enabled: v));

  Future<void> toggleDl(String name) {
    final next = Set<String>.from(rule.dl);
    next.contains(name) ? next.remove(name) : next.add(name);
    return setRule(rule.copyWith(dl: next));
  }

  Future<void> toggleLb(String name) {
    final next = Set<String>.from(rule.lb);
    next.contains(name) ? next.remove(name) : next.add(name);
    return setRule(rule.copyWith(lb: next));
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// 已见过的活动 id（新活动的判据）。
  Future<Set<String>> seenIds() async {
    final sp = await SharedPreferences.getInstance();
    return {
      ...?(_decode(sp.getString(_kSeen))?['ids'] as List?)?.map((e) => '$e'),
    };
  }

  /// 把见过的 id 写回去，只留最近 [maxSeen] 个。
  Future<void> _saveSeen(Iterable<String> ids) async {
    final list = ids.toList();
    final trimmed = list.length > maxSeen
        ? list.sublist(list.length - maxSeen)
        : list;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSeen, jsonEncode({'ids': trimmed}));
  }

  /// 检查一次：拉活动列表 → 找出「第一次见 + 命中分类」的活动 → 可选弹通知。
  ///
  /// * 第一次检查（没有任何基线）只记账不提醒：否则首次开启就被全部历史活动轰炸一遍；
  /// * 没开开关 / 没选分类时不联网，直接返回（省一次隧道请求）。
  Future<ActivityWatchResult> check({bool notify = true}) async {
    await load();
    if (!enabled || rule.categoryCount == 0) {
      return const ActivityWatchResult();
    }
    List<Map<String, dynamic>> list;
    try {
      final r = await ApiClient.I.activities();
      list = ((r['data'] as Map?)?['activities'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (e) {
      lastError = e is ApiError ? e.message : e.toString();
      notifyListeners();
      return ActivityWatchResult(error: lastError);
    }
    final seen = await seenIds();
    final firstRun = seen.isEmpty;
    final matched = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final a in list) {
      final id = '${a['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      ids.add(id);
      if (!firstRun && !seen.contains(id) && rule.matches(a)) matched.add(a);
    }
    // 见过的集合只增不减地并入本轮 id：活动下线后 id 还在，重新上线不会再报一次。
    seen.addAll(ids);
    await _saveSeen(seen);
    lastCheck = DateTime.now();
    lastFetched = list.length;
    lastMatched = matched.length;
    lastError = null;
    notifyListeners();
    if (notify && matched.isNotEmpty) await _notify(matched);
    return ActivityWatchResult(
      fetched: list.length,
      matched: matched,
      firstRun: firstRun,
    );
  }

  Future<void> _notify(List<Map<String, dynamic>> matched) async {
    await initPlugin();
    if (!_pluginReady) {
      debugPrint('[二课提醒] 通知插件未就绪，跳过弹窗');
      return;
    }
    final names = matched
        .take(3)
        .map((a) => '${a['name'] ?? ''}'.trim())
        .toList();
    final extra = matched.length > 3 ? ' 等 ${matched.length} 个活动' : '';
    try {
      await _plugin.show(
        notifyId,
        '第二课堂有新活动',
        '${names.where((n) => n.isNotEmpty).join('、')}$extra',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[二课提醒] 弹通知失败：$e');
    }
  }

  /// 初始化通知插件与渠道（幂等；主 isolate 与后台 isolate 各一份实例）。
  Future<void> initPlugin() async {
    if (_pluginReady) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDesc,
              importance: Importance.high,
            ),
          );
      _pluginReady = true;
    } catch (e) {
      debugPrint('[二课提醒] 通知初始化失败：$e');
    }
  }
}

/// 后台 isolate 的入口：宿主定时任务调到它（见 lib/background_tasks.dart）。
///
/// 后台进程里没有跑过 `main()`，所以这里自己把安全存储、设置与登录态装好，
/// 再用与前台完全同一套 [ActivityWatchService.check] 逻辑。
Future<String> runActivityWatchInBackground() async {
  SecureStore.I = FlutterSecureStore();
  await AppState.I.load();
  final r = await ActivityWatchService.I.check();
  if (r.error != null) return 'error: ${r.error}';
  return 'checked ${r.fetched}, new ${r.matched.length}';
}

/// 是否在 Android / iOS 上（后台定时任务只在移动端有意义）。
bool get activityWatchSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
