import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../class_reminder_service.dart';
import '../timetable_store.dart';
import '../widgets/common.dart';

/// 课程表：周视图，复刻 anticraft.top 课程表的 Corporate Clean 排版
/// （11 节次网格 + 上午/下午/晚上色带 + 5 色相课程块 + 底部周切换悬浮条）。
/// 本地课表（手动课程 / 调休规则 / 考试日程）不依赖登录；教务导入需登录。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late String xnm;
  late String xqm;

  final PageController _pc = PageController();
  final PageController _dayPc = PageController();
  int _shownWeek = 1;
  int _shownDay = 0; // 0=周一
  DateTime? _lastNavTap; // 上次点击周次标题的时间：500ms 内点两次回今天
  bool _dayView = false;
  bool _booting = true;
  final Set<int> _loadingWeeks = {};
  List<Map<String, dynamic>>? _terms; // 成绩接口返回的学期列表（登录后）
  Timer? _tick;

  static const _maxZs = 40;
  static const _axisW = 30.0;
  static const _slotH = 56.0;
  static const _bandH = 20.0;
  static const _noonH = 12.0;
  static const _headerH = 44.0;

  /// 课程/日程的 slotStart/slotEnd = 小节序号（0 起，0-10），与网站渲染一致。
  /// 教务数据实测值域 0-7（含 4-6 这种三节连上），不能按「大节」理解。

  /// 与网站一致的 11 节上课时间（展示用）。
  static const _slotTimes = [
    '08:20', '09:10', '10:10', '11:00', '13:00', '13:50', '14:55', '15:45', '18:00', '18:50', '19:40',
  ];
  static const _slotEndTimes = [
    '09:05', '09:55', '10:55', '11:45', '13:45', '14:35', '15:40', '16:30', '18:45', '19:35', '20:25',
  ];

  SemesterTt get tt => TimetableStore.instance.semester(xnm, xqm);
  bool _isImported(TtCourse c) => c.id.startsWith('jw-');
  int get _weekCount => tt.weekCount.clamp(1, _maxZs);
  int? get _todayWeek => TimetableStore.locateToday(tt.startDate, tt.weekCount);

  /// 手动课程排在教务课程之后 → 渲染时在上层（同位置重叠时用户自己的课优先可见）。
  List<TtCourse> get _allCourses => [...TimetableStore.deriveImported(tt), ...tt.courses];

  @override
  void initState() {
    super.initState();
    final (a, b) = AppState.inferSemester(DateTime.now());
    xnm = a;
    xqm = b;
    // 60s 心跳：过点课程置灰（同网站）
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
    AppState.I.addListener(_onAppChange);
    _wasLoggedIn = AppState.I.loggedIn;
    _init();
  }

  bool _wasLoggedIn = false;

  void _onAppChange() {
    if (!mounted) return;
    final loggedIn = AppState.I.loggedIn;
    final changed = loggedIn != _wasLoggedIn;
    _wasLoggedIn = loggedIn;
    setState(() {});
    // 只在登录态变化时补拉本周；否则 saveLogin 的通知会引起 401→续期→再拉 的循环
    if (changed && loggedIn && !_booting) _ensureWeek(_shownWeek);
  }

  @override
  void dispose() {
    _tick?.cancel();
    AppState.I.removeListener(_onAppChange);
    _pc.dispose();
    _dayPc.dispose();
    super.dispose();
  }

  Future<void> _init({bool keepSemester = false}) async {
    if (mounted) setState(() => _booting = true);
    await TimetableStore.instance.load();
    final adopted = await TimetableStore.instance.syncCloud();
    if (adopted && !keepSemester) {
      // 云端数据覆盖本地后学期可能变化：重置到推断学期。
      // 显式切换学期（keepSemester）时不重置，否则切换会被弹回当前学期。
      final (a, b) = AppState.inferSemester(DateTime.now());
      xnm = a;
      xqm = b;
    }
    _fixWeekCount();
    final tw = _todayWeek;
    _shownWeek = tw ?? 1;
    _shownDay = DateTime.now().weekday - 1;
    if (mounted) setState(() => _booting = false);
    if (AppState.I.loggedIn) await _ensureWeek(_shownWeek);
    final tw2 = _todayWeek;
    if (tw2 != null) _shownWeek = tw2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpTo(_shownWeek, animate: false);
    });
  }

  void _fixWeekCount() {
    final maxZs = tt.jwxtWeeks.keys
        .map(int.tryParse)
        .whereType<int>()
        .fold(0, (a, b) => b > a ? b : a);
    if (maxZs > tt.weekCount) {
      tt.weekCount = maxZs.clamp(1, _maxZs);
      TimetableStore.instance.save();
    }
  }

  void _jumpTo(int zs, {bool animate = true}) {
    if (!_pc.hasClients) return;
    final target = zs.clamp(1, _weekCount) - 1;
    if (animate) {
      _pc.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    } else {
      _pc.jumpToPage(target);
    }
    _shownWeek = target + 1;
    if (mounted) setState(() {});
  }

  /// 拉取某周教务课表并入本地 store（登录后懒加载；未登录跳过）。
  Future<void> _ensureWeek(int zs, {bool force = false}) async {
    if (zs < 1 || zs > _maxZs) return;
    if (!AppState.I.loggedIn) return;
    if (!force && (tt.jwxtWeeks.containsKey('$zs') || _loadingWeeks.contains(zs))) return;
    _loadingWeeks.add(zs);
    if (mounted) setState(() {});
    try {
      final resp = await ApiClient.I.timetableWeek(xnm, xqm, zs);
      _storeWeek(zs, resp);
    } on ApiError catch (e) {
      if (!e.message.contains('没有课表') && mounted) showErr(context, e);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      _loadingWeeks.remove(zs);
      if (mounted) setState(() {});
    }
  }

  void _storeWeek(int zs, Map<String, dynamic> resp) {
    tt.jwxtWeeks['$zs'] = ((resp['courses'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TtCourse.fromJson)
        .toList();
    if (zs == 1 && tt.startDate.isEmpty) {
      for (final d in (resp['dates'] as List?) ?? const []) {
        if ('${(d as Map)['xqj']}' == '1') {
          tt.startDate = '${d['rq']}';
          break;
        }
      }
    }
    final nj = resp['nj'];
    if (nj is String && nj.isNotEmpty) {
      TimetableStore.instance.nj = nj; // 内部会 persist
    } else {
      TimetableStore.instance.save();
    }
    _fixWeekCount();
  }

  // ── 教务全量导入 ──

  Future<void> _importAll() async {
    if (!_checkLogin()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从教务导入课表'),
        content: Text(
            '将逐周拉取当前学期（$xnm 学年${xqm == '3' ? '第一' : '第二'}学期）的全部课表，覆盖本机教务数据。\n手动课程与调休规则会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始导入')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    tt.jwxtWeeks.clear();
    final progress = ValueNotifier('正在连接教务…');
    final popper = ValueNotifier(false);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ValueListenableBuilder(
          valueListenable: popper,
          builder: (ctx, done, _) => AlertDialog(
            title: Text(done ? '导入完成' : '正在导入'),
            content: ValueListenableBuilder(
              valueListenable: progress,
              builder: (ctx, msg, _) => Row(children: [
                if (!done) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                if (!done) const SizedBox(width: 12),
                Expanded(child: Text(msg, style: const TextStyle(fontSize: 13.5))),
              ]),
            ),
            actions: [
              if (done) FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
            ],
          ),
        ),
      ),
    ));

    var w = 1;
    var lastWeek = 0;
    String? error;
    while (w <= _maxZs) {
      progress.value = '正在导入 第 $w 周…';
      try {
        final resp = await ApiClient.I.timetableWeek(xnm, xqm, w);
        _storeWeek(w, resp);
        lastWeek = w;
        w++;
      } on ApiError catch (e) {
        if (!e.message.contains('没有课表')) error = e.message;
        break;
      } catch (e) {
        error = e.toString();
        break;
      }
    }
    if (lastWeek > 0) {
      tt.weekCount = math.max(tt.weekCount, lastWeek).clamp(1, _maxZs);
      await TimetableStore.instance.save();
    }
    if (mounted) setState(() {});
    popper.value = true;
    progress.value = lastWeek > 0
        ? (error == null ? '共导入 $lastWeek 周课表' : '导入到第 $lastWeek 周后中断：$error')
        : '导入失败：$error';
    if (lastWeek > 0) {
      final tw = _todayWeek;
      if (tw != null) _jumpTo(tw);
    }
  }

  // ── 考试导入（转日程事件）──

  Future<void> _importExams() async {
    if (!_checkLogin()) return;
    try {
      final r = await ApiClient.I.exams(xnm, xqm);
      final exams = ((r['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final added = TimetableStore.addExamEvents(tt, exams);
      await TimetableStore.instance.save();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added > 0 ? '已导入 $added 场考试（跳过 ${exams.length - added} 场）' : '没有新的考试可导入'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  bool _checkLogin() {
    if (AppState.I.loggedIn) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppState.I.direct
            ? '该功能需要先在「连接设置 → 直连模式」填写校园凭据'
            : '该功能需要先登录服务器账号'),
        behavior: SnackBarBehavior.floating));
    return false;
  }

  // ── 学期切换 ──

  Future<void> _pickSemester() async {
    if (AppState.I.loggedIn && _terms == null) {
      try {
        final r = await ApiClient.I.grades();
        _terms = ((r['data'] as Map?)?['terms'] as List?)?.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    final terms = _terms ?? const [];
    // 选项 = 成绩学期列表 + 推断的当前学期 + 本地已有数据的学期
    // （成绩列表里没有当前学期，否则切走后就回不来了）
    final opts = <(String xnm, String xqm, String label)>[];
    void addOpt(String xn, String xq, {String? label}) {
      if (xn.isEmpty || xq.isEmpty) return;
      if (opts.any((o) => o.$1 == xn && o.$2 == xq)) return;
      opts.add((xn, xq, label ?? '$xn-${int.tryParse(xn) != null ? int.parse(xn) + 1 : '?'}学年 ${xq == '3' ? '第一' : xq == '12' ? '第二' : '短'}学期'));
    }

    final inferred = AppState.inferSemester(DateTime.now());
    addOpt(inferred.$1, inferred.$2);
    for (final t in terms) {
      addOpt('${t['xnm']}', '${t['xqm']}', label: '${t['xnmmc']} ${t['xqmmc']}');
    }
    for (final k in TimetableStore.instance.semesters.keys) {
      final p = k.split('-');
      if (p.length == 2) addOpt(p[0], p[1]);
    }
    opts.sort((a, b) => '${b.$1}-${b.$2}'.compareTo('${a.$1}-${a.$2}')); // 新 → 旧

    if (!mounted) return;
    await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('选择学期', style: TextStyle(fontWeight: FontWeight.bold))),
              if (opts.isEmpty) _genericSemesterPicker(ctx),
              for (final o in opts)
                ListTile(
                  title: Text(o.$3),
                  trailing: (o.$1 == xnm && o.$2 == xqm)
                      ? Icon(Icons.check, color: SemColors.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, {'xnm': o.$1, 'xqm': o.$2}),
                ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: SemColors.accent),
                title: Text('新建学期', style: TextStyle(color: SemColors.accent)),
                subtitle: const Text('建一个空学期，手动排课或稍后从教务导入',
                    style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, const {'new': true}),
              ),
            ],
          ),
        ),
      ),
    ).then((t) {
      if (t is Map && t['new'] == true) {
        _newSemester();
        return;
      }
      String? nxnm, nxqm;
      if (t is Map<String, dynamic>) {
        nxnm = '${t['xnm']}';
        nxqm = '${t['xqm']}';
      } else if (t is List && t.length == 2) {
        nxnm = '${t[0]}';
        nxqm = '${t[1]}';
      }
      if (nxnm != null && nxqm != null && (nxnm != xnm || nxqm != xqm)) {
        setState(() {
          xnm = nxnm!;
          xqm = nxqm!;
        });
        _init(keepSemester: true);
      }
    });
  }

  /// 新建空学期：选学年 + 学期码 → 建档并切换 → 立刻打开「学期设置」。
  Future<void> _newSemester() async {
    final created = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('新建学期', style: TextStyle(fontWeight: FontWeight.bold))),
            _genericSemesterPicker(ctx, confirmLabel: '创建'),
          ],
        ),
      ),
    );
    if (!mounted || created == null || created.length != 2) return;
    final yn = created[0];
    final xq = created[1];
    if (yn.isEmpty || xq.isEmpty) return;
    if (yn != xnm || xq != xqm) {
      setState(() {
        xnm = yn;
        xqm = xq;
      });
      TimetableStore.instance.semester(yn, xq); // 建空学期
      await TimetableStore.instance.persist();
      await _init(keepSemester: true);
    }
    if (mounted) _semSettings(); // 新建后立刻到学期设置（设起点 / 周数）
  }

  /// 未登录（无学期列表）时的通用选择器：学年 + 学期码。
  Widget _genericSemesterPicker(BuildContext ctx, {String confirmLabel = '确定'}) {
    final now = DateTime.now().year;
    final years = [for (var y = now - 3; y <= now; y++) '$y'];
    var year = years.contains(xnm) ? xnm : years.last;
    var xq = xqm;
    return StatefulBuilder(
      builder: (ctx, setS) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: year,
                    decoration: const InputDecoration(labelText: '学年（起始年）', isDense: true),
                    items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y-${int.parse(y) + 1}学年'))],
                    onChanged: (v) => setS(() => year = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: xq,
                    decoration: const InputDecoration(labelText: '学期', isDense: true),
                    items: const [
                      DropdownMenuItem(value: '3', child: Text('第一学期')),
                      DropdownMenuItem(value: '12', child: Text('第二学期')),
                    ],
                    onChanged: (v) => setS(() => xq = v!),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, [year, xq]),
              child: Text(confirmLabel),
            ),
          ),
        ],
      ),
    );
  }

  // ── 学期设置 ──

  Future<void> _semSettings() async {
    var startDate = tt.startDate;
    var weekCount = tt.weekCount;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setS) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('学期设置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('学期起点（第 1 周周一）'),
                  subtitle: Text(startDate.isEmpty ? '未设置' : startDate),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final init = DateTime.tryParse(startDate) ?? DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: init,
                      firstDate: DateTime(init.year - 1),
                      lastDate: DateTime(init.year + 1),
                    );
                    if (picked != null) setS(() => startDate = TimetableStore.iso(picked));
                  },
                ),
                Row(
                  children: [
                    const Text('学期周数'),
                    Expanded(
                      child: Slider(
                        value: weekCount.toDouble(),
                        min: 1,
                        max: 40,
                        divisions: 39,
                        label: '$weekCount',
                        onChanged: (v) => setS(() => weekCount = v.round()),
                      ),
                    ),
                    SizedBox(width: 40, child: Text('$weekCount 周', textAlign: TextAlign.end)),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      tt.startDate = startDate;
                      tt.weekCount = weekCount.clamp(1, _maxZs);
                      TimetableStore.instance.save();
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 调休设置 ──

  Future<void> _adjustModal() async {
    DateTime? date;
    DateTime? endDate;
    var type = 'off';
    var day = 0;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              String desc(TtAdjust a) => a.type == 'off'
                  ? '放假（当天无课）'
                  : '按周${'一二三四五六日'[a.day]}的课表上课';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('调休设置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  if (tt.startDate.isEmpty)
                    Text('请先在「学期设置」里设定学期起点，调休规则才能对应到周次。',
                        style: TextStyle(fontSize: 12, color: SemColors.warning)),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (tt.adjustments.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('暂无调休规则', textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: SemColors.textMuted)),
                          ),
                        for (final a in tt.adjustments)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(desc(a), style: const TextStyle(fontSize: 14)),
                            subtitle: Text(a.date, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, size: 20, color: SemColors.textMuted),
                              onPressed: () {
                                setState(() => tt.adjustments.removeWhere((x) => x.date == a.date));
                                TimetableStore.instance.save();
                                setS(() {});
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx, initialDate: date ?? now,
                            firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
                          );
                          if (picked != null) setS(() => date = picked);
                        },
                        child: Text(date == null ? '选择日期' : TimetableStore.iso(date!)),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx, initialDate: endDate ?? date ?? now,
                            firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
                          );
                          if (picked != null) setS(() => endDate = picked);
                        },
                        child: Text(endDate == null ? '结束日期（可选）' : '~ ${TimetableStore.iso(endDate!)}'),
                      ),
                      GlassTabs(
                        labels: const ['放假', '调课'],
                        index: type == 'follow' ? 1 : 0,
                        onChanged: (i) => setS(() => type = i == 1 ? 'follow' : 'off'),
                      ),
                      if (type == 'follow')
                        DropdownButton<int>(
                          value: day,
                          items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text('周${'一二三四五六日'[i]}'))],
                          onChanged: (v) => setS(() => day = v!),
                        ),
                      FilledButton(
                        onPressed: date == null
                            ? null
                            : () {
                                final entries = TimetableStore.expandDateRange(
                                  TimetableStore.iso(date!),
                                  endDate == null ? null : TimetableStore.iso(endDate!),
                                ).map((d) => TtAdjust(date: TimetableStore.iso(d), type: type, day: day));
                                setState(() => tt.adjustments =
                                    TimetableStore.mergeAdjustments(tt.adjustments, entries.toList()));
                                TimetableStore.instance.save();
                                setS(() { date = null; endDate = null; });
                              },
                        child: const Text('添加规则'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('规则在渲染时生效：同一天只会命中一条；「调课」当天的课在原星期列照常显示。',
                      style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── 手动课程表单 ──

  Future<void> _courseForm({TtCourse? existing, bool imported = false}) async {
    final nameC = TextEditingController(text: existing?.name ?? '');
    final placeC = TextEditingController(text: existing?.place ?? '');
    final teachersC = TextEditingController(text: existing?.teachers ?? '');
    final wsC = TextEditingController(text: '${existing?.weekStart ?? 1}');
    final weC = TextEditingController(text: '${existing?.weekEnd ?? tt.weekCount}');
    var day = existing?.day ?? 0;
    var slotStart = existing?.slotStart ?? 0;
    var slotEnd = existing?.slotEnd ?? 1;
    var weekType = existing?.weekType ?? 'all';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(imported ? '编辑教务课程（保存后转为手动）' : existing == null ? '添加课程' : '编辑课程',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              TextField(controller: nameC, decoration: const InputDecoration(labelText: '课程名 *', isDense: true)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: placeC, decoration: const InputDecoration(labelText: '地点', isDense: true))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: teachersC, decoration: const InputDecoration(labelText: '教师', isDense: true))),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _dropdown<int>('星期', day, [for (var i = 0; i < 7; i++) (i, '周${'一二三四五六日'[i]}')], (v) => setS(() => day = v)),
                _dropdown<int>('开始', slotStart, [for (var i = 0; i < 11; i++) (i, '第${i + 1}节')], (v) => setS(() => slotStart = v)),
                _dropdown<int>('结束', slotEnd, [for (var i = 0; i < 11; i++) (i, '第${i + 1}节')], (v) => setS(() => slotEnd = v)),
                _dropdown<String>('周次', weekType, const [('all', '每周'), ('odd', '单周'), ('even', '双周')], (v) => setS(() => weekType = v)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: wsC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '开始周', isDense: true))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: weC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '结束周（共 $_weekCount 周）', isDense: true))),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    final name = nameC.text.trim();
                    final ws = int.tryParse(wsC.text.trim()) ?? 0;
                    final we = int.tryParse(weC.text.trim()) ?? 0;
                    if (name.isEmpty || slotStart > slotEnd || ws < 1 || we < ws || we > _weekCount) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('请检查：课程名必填、节次/周次范围有效'), behavior: SnackBarBehavior.floating));
                      return;
                    }
                    final data = TtCourse(
                      id: existing?.id ?? TimetableStore.genId(),
                      name: name,
                      place: placeC.text.trim(),
                      teachers: teachersC.text.trim(),
                      day: day,
                      slotStart: slotStart,
                      slotEnd: slotEnd,
                      weekType: weekType,
                      weekStart: ws,
                      weekEnd: we,
                    );
                    if (imported && existing != null) {
                      // 转手动：追加手动课程 + 从教务原始数据移除该段
                      tt.courses.add(data);
                      TimetableStore.removeImportedSegment(tt, existing);
                    } else if (existing != null) {
                      final i = tt.courses.indexWhere((c) => c.id == existing.id);
                      if (i >= 0) tt.courses[i] = data;
                    } else {
                      tt.courses.add(data);
                    }
                    TimetableStore.instance.save();
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Widget _dropdown<T>(String label, T value, List<(T, String)> items, ValueChanged<T> onChanged) =>
      DropdownButton<T>(
        value: value,
        items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text('$label $l', style: const TextStyle(fontSize: 13)))],
        onChanged: (v) { if (v != null) onChanged(v); },
        underline: const SizedBox(),
        isDense: true,
      );

  // ── 课程详情 / 删除 ──

  void _showCourseDetail(TtCourse c, int zs) {
    final imported = _isImported(c);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(c.name, style: Theme.of(ctx).textTheme.titleLarge)),
                if (imported) Capsule('教务课程', color: SemColors.info),
              ]),
              const SizedBox(height: 12),
              _detailRow('时间', '周${'一二三四五六日'[c.day]} 第${c.slotStart + 1}-${c.slotEnd + 1}节 · '
                  '${_weekTypeLabel(c.weekType)} ${c.weekStart}-${c.weekEnd} 周'),
              _detailRow('地点', c.place.isEmpty ? '-' : c.place),
              _detailRow('教师', c.teachers.isEmpty ? '-' : c.teachers),
              if (c.code.isNotEmpty) _detailRow('课程代码', c.code),
              if (c.clazz.isNotEmpty) _detailRow('教学班', c.clazz),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _courseForm(existing: c, imported: imported);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(imported ? '编辑（转手动）' : '编辑'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteCourse(c, zs);
                  },
                  icon: Icon(Icons.delete_outline, size: 18, color: SemColors.danger),
                  label: Text('删除', style: TextStyle(color: SemColors.danger)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  String _weekTypeLabel(String t) => switch (t) { 'odd' => '单周', 'even' => '双周', _ => '每周' };

  Future<void> _deleteCourse(TtCourse c, int zs) async {
    final imported = _isImported(c);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('删除方式', style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              title: Text('仅第 $zs 周这一次'),
              subtitle: imported ? null : const Text('自动拆分周次，其余周保留', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'week'),
            ),
            ListTile(
              title: Text(imported ? '所有周的该课程' : '全部场次（同名课程）'),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'week') {
      if (imported) {
        TimetableStore.removeImportedOccurrence(tt, c, all: false, week: zs);
      } else {
        // 拆分周次：原条目替换成前段 + 后段
        final parts = <TtCourse>[];
        if (c.weekStart < zs) {
          parts.add(TtCourse(
            id: TimetableStore.genId(), name: c.name, place: c.place, teachers: c.teachers,
            day: c.day, slotStart: c.slotStart, slotEnd: c.slotEnd, weekType: c.weekType,
            weekStart: c.weekStart, weekEnd: zs - 1,
          ));
        }
        if (zs < c.weekEnd) {
          parts.add(TtCourse(
            id: TimetableStore.genId(), name: c.name, place: c.place, teachers: c.teachers,
            day: c.day, slotStart: c.slotStart, slotEnd: c.slotEnd, weekType: c.weekType,
            weekStart: zs + 1, weekEnd: c.weekEnd,
          ));
        }
        tt.courses.removeWhere((x) => x.id == c.id);
        tt.courses.addAll(parts);
      }
    } else {
      if (imported) {
        TimetableStore.removeImportedOccurrence(tt, c, all: true);
      } else {
        tt.courses.removeWhere((x) => x.name == c.name);
      }
    }
    await TimetableStore.instance.save();
    if (mounted) setState(() {});
  }

  // ── 手动日程事件 ──

  Future<void> _eventForm({TtEvent? existing}) async {
    final nameC = TextEditingController(text: existing?.name ?? '');
    final placeC = TextEditingController(text: existing?.place ?? '');
    final noteC = TextEditingController(text: existing?.note ?? '');
    DateTime? date = existing == null || existing.date.isEmpty ? null : DateTime.tryParse(existing.date);
    var weekly = existing != null && existing.date.isEmpty;
    var day = existing?.day ?? 0;
    TimeOfDay start = _toTOD(existing?.start) ?? const TimeOfDay(hour: 19, minute: 0);
    TimeOfDay end = _toTOD(existing?.end) ?? const TimeOfDay(hour: 20, minute: 0);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(existing == null ? '添加日程' : '编辑日程',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              TextField(controller: nameC, decoration: const InputDecoration(labelText: '名称 *', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: placeC, decoration: const InputDecoration(labelText: '地点', isDense: true)),
              const SizedBox(height: 8),
              GlassTabs(
                labels: const ['单次（选日期）', '每周重复'],
                index: weekly ? 1 : 0,
                onChanged: (i) => setS(() => weekly = i == 1),
              ),
              const SizedBox(height: 8),
              Row(children: [
                if (weekly)
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: day,
                      decoration: const InputDecoration(labelText: '星期', isDense: true),
                      items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text('周${'一二三四五六日'[i]}'))],
                      onChanged: (v) => setS(() => day = v!),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx, initialDate: date ?? now,
                          firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) setS(() => date = picked);
                      },
                      child: Text(date == null ? '选择日期 *' : TimetableStore.iso(date!)),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: start);
                      if (t != null) setS(() => start = t);
                    },
                    child: Text('开始 ${start.format(ctx)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: end);
                      if (t != null) setS(() => end = t);
                    },
                    child: Text('结束 ${end.format(ctx)}'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: noteC, decoration: const InputDecoration(labelText: '备注', isDense: true)),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    final name = nameC.text.trim();
                    if (name.isEmpty || (!weekly && date == null)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('请填写名称，单次日程需选择日期'), behavior: SnackBarBehavior.floating));
                      return;
                    }
                    final ev = TtEvent(
                      id: existing?.id ?? TimetableStore.genId(),
                      name: name,
                      place: placeC.text.trim(),
                      date: weekly ? '' : TimetableStore.iso(date!),
                      day: weekly ? day : (date!.weekday - 1),
                      start: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                      end: '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                      note: noteC.text.trim(),
                    );
                    if (existing != null) {
                      final i = tt.events.indexWhere((x) => x.id == existing.id);
                      if (i >= 0) tt.events[i] = ev;
                    } else {
                      tt.events.add(ev);
                    }
                    TimetableStore.instance.save();
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  TimeOfDay? _toTOD(String? s) {
    final m = _hm(s ?? '');
    if (m < 0) return null;
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  void _showEventDetail(TtEvent e) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(e.name, style: Theme.of(ctx).textTheme.titleLarge)),
                if (e.kind == 'exam') Capsule('考试', color: SemColors.danger),
                if (e.date.isEmpty) Capsule('每周', color: SemColors.info),
              ]),
              const SizedBox(height: 12),
              _detailRow('时间', e.date.isEmpty
                  ? '每周 周${'一二三四五六日'[e.day]} ${e.start}~${e.end}'
                  : '${e.date} ${e.start}~${e.end}'),
              if (e.place.isNotEmpty) _detailRow('地点', e.place),
              if (e.seat.isNotEmpty) _detailRow('座位', e.seat),
              if (e.note.isNotEmpty) _detailRow('备注', e.note),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _eventForm(existing: e);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => tt.events.removeWhere((x) => x.id == e.id));
                    TimetableStore.instance.save();
                  },
                  icon: Icon(Icons.delete_outline, size: 18, color: SemColors.danger),
                  label: Text('删除', style: TextStyle(color: SemColors.danger)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── 渲染 ──

  /// 上课提醒开关：打开时申请通知权限（必要时再要精确闹钟权限），并按当前课表排期。
  Future<void> _onReminderToggle(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    String? tip;
    if (v) {
      tip = await ClassReminderService.I.enable();
    } else {
      await ClassReminderService.I.disable();
      tip = '已关闭上课提醒';
    }
    if (!mounted) return;
    if (tip != null) {
      messenger.showSnackBar(SnackBar(content: Text(tip), behavior: SnackBarBehavior.floating));
    }
  }

  /// 课表页 AppBar 的提醒图标：点击即开关（与「我的」页开关同一份状态）。
  Future<void> _toggleReminder() => _onReminderToggle(!ClassReminderService.I.enabled);

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_semesterTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () {
              if (!_dayView) {
                // 切到日视图：目标页 = 当前显示的周/日；跳转后显式同步状态，
                // 不依赖 onPageChanged（attach 到新 PageView 时可能不触发）
                final target = (_shownWeek - 1) * 7 + _shownDay;
                setState(() => _dayView = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_dayPc.hasClients) return;
                  _dayPc.jumpToPage(target);
                  setState(() {
                    _shownWeek = target ~/ 7 + 1;
                    _shownDay = target % 7;
                  });
                });
              } else {
                setState(() => _dayView = false);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _pc.hasClients) _pc.jumpToPage(_shownWeek - 1);
                });
              }
            },
            icon: Icon(_dayView ? Icons.calendar_view_week_rounded : Icons.calendar_view_day_rounded),
            tooltip: _dayView ? '周视图' : '日视图',
          ),
          ListenableBuilder(
            listenable: ClassReminderService.I,
            builder: (_, __) => IconButton(
              onPressed: _toggleReminder,
              icon: Icon(ClassReminderService.I.enabled
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined),
              tooltip: ClassReminderService.I.enabled
                  ? '上课提醒已开启（课前 ${ClassReminderService.leadMinutes} 分钟）'
                  : '开启上课提醒（课前 ${ClassReminderService.leadMinutes} 分钟）',
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              switch (v) {
                case 'addCourse':
                  _courseFormAdd();
                case 'addEvent':
                  _eventForm();
                case 'import':
                  _importAll();
                case 'exams':
                  _importExams();
                case 'adjust':
                  _adjustModal();
                case 'sem':
                  _semSettings();
                case 'switch':
                  _pickSemester();
                case 'refresh':
                  _ensureWeek(_shownWeek, force: true);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'addCourse', child: ListTile(leading: Icon(Icons.add), title: Text('添加课程'), contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'addEvent', child: ListTile(leading: Icon(Icons.schedule_rounded), title: Text('添加日程'), contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.cloud_download_outlined), title: Text('教务导入课表'), contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'exams', child: ListTile(leading: Icon(Icons.event_note_outlined), title: Text('导入考试安排'), contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'adjust', child: ListTile(leading: Icon(Icons.swap_horiz_rounded), title: Text('调休设置'), contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'sem', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('学期设置'), contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'switch', child: ListTile(leading: Icon(Icons.calendar_month_outlined), title: Text('切换学期'), contentPadding: EdgeInsets.zero, dense: true)),
              if (AppState.I.loggedIn)
                const PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text('刷新本周'), contentPadding: EdgeInsets.zero, dense: true)),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final loggedIn = AppState.I.loggedIn;
          return Stack(
            children: [
              Column(
                children: [
                  if (!loggedIn) _guestBanner(),
                  _todayCard(),
                  _examStrip(),
                  Expanded(
                    child: _dayView
                        ? PageView.builder(
                            controller: _dayPc,
                            itemCount: _weekCount * 7,
                            onPageChanged: (idx) {
                              setState(() {
                                _shownWeek = idx ~/ 7 + 1;
                                _shownDay = idx % 7;
                              });
                              _ensureWeek(_shownWeek);
                            },
                            itemBuilder: (context, idx) =>
                                _dayPage(idx ~/ 7 + 1, idx % 7),
                          )
                        : PageView.builder(
                            controller: _pc,
                            itemCount: _weekCount,
                            onPageChanged: (i) {
                              setState(() => _shownWeek = i + 1);
                              _ensureWeek(i + 1);
                            },
                            itemBuilder: (context, i) => _weekPage(i + 1),
                          ),
                  ),
                ],
              ),
              // 底部悬浮导航条：周视图切周 / 日视图切天
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: _dayView ? _dayNav() : _weekNav(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _courseFormAdd() => _courseForm();

  String get _semesterTitle {
    final label = TimetableStore.instance.semesterLabel('$xnm-$xqm');
    return label == null ? '课程表' : '课程表 · $label';
  }

  Widget _guestBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SemColors.infoSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SemColors.info.withValues(alpha: 0.3)),
        ),
        child: Text(
          AppState.I.direct
              ? '未填写校园凭据：手动编辑 / 调休等本地功能可正常使用，填写后可从教务导入课表与考试（需校园网）。'
              : '未登录：手动编辑 / 调休等本地功能可正常使用，登录后可从教务导入课表与考试。',
          style: TextStyle(fontSize: 12, color: SemColors.info, height: 1.5),
        ),
      );

  Widget _todayCard() {
    final now = DateTime.now();
    final tw = _todayWeek;
    final noStart = tt.startDate.isEmpty;
    // 调休规则同样作用于今天：off → 无课，follow → 按被借星期的课表
    final adj = tw == null ? null : _colAdjust(tw, now.weekday - 1);
    final effDay = adj == null
        ? now.weekday - 1
        : (adj.type == 'off' ? null : adj.day);
    List<TtCourse> courses = const [];
    if (tw != null && effDay != null) {
      courses = _coursesOf(tw).where((c) => c.day == effDay).toList()
        ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_rounded, size: 15, color: SemColors.accent),
                const SizedBox(width: 6),
                Text(
                  noStart
                      ? '未设置学期起点'
                      : tw == null
                          ? '假期中（学期外）'
                          : '今天 · 第$tw周',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                if (noStart)
                  GestureDetector(
                    onTap: _semSettings,
                    child: Text('去设置', style: TextStyle(fontSize: 12, color: SemColors.accent)),
                  )
                else
                  Text(
                      adj?.type == 'off'
                          ? '放假（调休）'
                          : (adj?.type == 'follow'
                              ? '按周${'一二三四五六日'[adj!.day]}上课 · ${courses.length} 节'
                              : (courses.isEmpty ? '今天没有课' : '${courses.length} 节课')),
                      style: TextStyle(
                          fontSize: 12,
                          color: adj?.type == 'off' ? SemColors.danger : SemColors.textMuted)),
              ],
            ),
            if (!noStart && tw != null && courses.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = courses[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _courseColor(c.name),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${c.name} ${c.slotStart + 1}-${c.slotEnd + 1}节 @${c.place.isEmpty ? '-' : c.place}',
                        style: TextStyle(fontSize: 12, color: SemColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
            Text(
              '现在时间 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: SemColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// 近期考试 / 日程提醒条（来自本地日程事件，考试导入后出现）。
  Widget _examStrip() {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final upcoming = <(TtEvent, int)>[];
    for (final e in tt.events) {
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      final diff = DateTime(d.year, d.month, d.day).difference(day0).inDays;
      if (diff >= 0 && diff <= 90) upcoming.add((e, diff));
    }
    if (upcoming.isEmpty) return const SizedBox.shrink();
    upcoming.sort((a, b) => a.$2.compareTo(b.$2));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(upcoming.first.$1.kind == 'exam' ? Icons.event_note_rounded : Icons.schedule_rounded,
                    size: 15, color: SemColors.danger),
                const SizedBox(width: 6),
                const Text('近期日程', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Text('${upcoming.length} 项', style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: math.min(5, upcoming.length),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final (e, diff) = upcoming[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${e.name} ${e.date.substring(5)} '
                      '${diff == 0 ? '今天' : diff == 1 ? '明天' : '还有$diff天'}',
                      style: TextStyle(fontSize: 12, color: SemColors.danger),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekNav() {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: SemColors.cardElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SemColors.borderStrong),
          boxShadow: [
            BoxShadow(color: SemColors.accent.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _navBtn(Icons.chevron_left, _shownWeek > 1 ? () => _jumpTo(_shownWeek - 1) : null),
            GestureDetector(
              onTap: () {
                if (_navTitleTappedTwice()) {
                  final tw = _todayWeek;
                  _jumpTo(tw ?? 1);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('第 $_shownWeek 周',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            _navBtn(Icons.chevron_right, _shownWeek < _weekCount ? () => _jumpTo(_shownWeek + 1) : null),
          ],
        ),
      ),
    );
  }

  /// 周次标题 500ms 内被点第二次 → 回到今天。
  bool _navTitleTappedTwice() {
    final now = DateTime.now();
    final twice =
        _lastNavTap != null && now.difference(_lastNavTap!) < const Duration(milliseconds: 500);
    _lastNavTap = twice ? null : now;
    return twice;
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) => SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 20, color: onTap == null ? SemColors.textMuted : SemColors.textSecondary),
        ),
      );

  // ── 日视图 ──

  void _goDay(int week, int day) {
    final idx = ((week - 1) * 7 + day).clamp(0, _weekCount * 7 - 1);
    _dayPc.animateToPage(idx, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  Widget _dayNav() {
    final idx = (_shownWeek - 1) * 7 + _shownDay;
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: SemColors.cardElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SemColors.borderStrong),
          boxShadow: [
            BoxShadow(color: SemColors.accent.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _navBtn(Icons.chevron_left, idx > 0 ? () => _goDay(idx ~/ 7, idx % 7 - 1) : null),
            GestureDetector(
              onTap: () {
                if (_navTitleTappedTwice()) {
                  final tw = _todayWeek;
                  _goDay(tw ?? 1, DateTime.now().weekday - 1);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('周${'一二三四五六日'[_shownDay]} · 第 $_shownWeek 周',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
            _navBtn(Icons.chevron_right, idx < _weekCount * 7 - 1 ? () => _goDay(idx ~/ 7 + (idx % 7 == 6 ? 1 : 0), (idx + 1) % 7) : null),
          ],
        ),
      ),
    );
  }

  Widget _dayPage(int week, int day) {
    final colISO = _colISO(week, day);
    final adj = _colAdjust(week, day);
    final eff = adj == null ? day : (adj.type == 'off' ? null : adj.day);
    final courses = (eff == null
            ? <TtCourse>[]
            : _allCourses.where((c) => c.day == eff && TimetableStore.coversWeek(c, week)).toList())
      ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
    final events = tt.events
        .where((e) => e.date.isEmpty ? (eff != null && e.day == eff) : e.date == colISO)
        .toList()
      ..sort((a, b) => _hm(a.start).compareTo(_hm(b.start)));

    final isToday = _todayWeek == week && day == DateTime.now().weekday - 1;
    final dateText = colISO.isEmpty
        ? '第 $week 周'
        : '${int.tryParse(colISO.substring(5, 7)) ?? ''}月${int.tryParse(colISO.substring(8)) ?? ''}日';

    final items = <(int, Widget)>[
      for (final c in courses) (_hm(_slotTimes[c.slotStart.clamp(0, 10)]), _dayCourseCard(c, week, colISO)),
      for (final e in events) (_hm(e.start) < 0 ? 0 : _hm(e.start), _dayEventCard(e, isToday)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
      children: [
        Row(
          children: [
            Text('$dateText 周${'一二三四五六日'[day]}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (isToday) Capsule('今天', color: SemColors.accent),
          ],
        ),
        if (adj != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: adj.type == 'off' ? SemColors.dangerSoft : SemColors.infoSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              adj.type == 'off' ? '放假（调休规则：当天无课）' : '按周${'一二三四五六日'[adj.day]}的课表上课（调休规则）',
              style: TextStyle(
                  fontSize: 12.5, color: adj.type == 'off' ? SemColors.danger : SemColors.info),
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined, size: 44, color: SemColors.textMuted),
                const SizedBox(height: 10),
                Text(adj?.type == 'off' ? '放假中，当天无课' : '当天没有安排',
                    style: TextStyle(color: SemColors.textMuted)),
              ],
            ),
          )
        else
          ...items.map((it) => it.$2),
      ],
    );
  }

  Widget _dayCourseCard(TtCourse c, int week, String colISO) {
    final past = _isPast(c, colISO);
    final rs = c.slotStart.clamp(0, 10);
    final re = c.slotEnd.clamp(0, 10);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: past ? 0.55 : 1,
        child: AppCard(
          onTap: () => _showCourseDetail(c, week),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _courseColor(c.name), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    Text(_slotTimes[rs], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(_slotEndTimes[re.clamp(0, 10)], style: TextStyle(fontSize: 10, color: SemColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('第${c.slotStart + 1}-${c.slotEnd + 1}节 · ${c.weekStart}-${c.weekEnd}周${_weekTypeLabel(c.weekType)}',
                        style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                    if (c.place.isNotEmpty || c.teachers.isNotEmpty)
                      Text([if (c.place.isNotEmpty) c.place, if (c.teachers.isNotEmpty) c.teachers].join(' · '),
                          style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayEventCard(TtEvent e, bool isToday) {
    final isExam = e.kind == 'exam';
    final now = DateTime.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final past = isToday && e.end.isNotEmpty && hhmm.compareTo(e.end) > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: past ? 0.55 : 1,
        child: AppCard(
          onTap: () => _showEventDetail(e),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isExam ? SemColors.dangerSoft : SemColors.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(e.start.isEmpty ? '—' : e.start,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: isExam ? SemColors.danger : SemColors.accent)),
                    if (e.end.isNotEmpty)
                      Text(e.end, style: TextStyle(fontSize: 10, color: SemColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(e.name,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: isExam ? SemColors.danger : SemColors.textPrimary)),
                      ),
                      if (e.date.isEmpty) Capsule('每周', color: SemColors.info),
                    ]),
                    if (e.place.isNotEmpty)
                      Text(e.place, style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
                    if (e.note.isNotEmpty)
                      Text(e.note, style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _rowY(int row) {
    if (row <= 3) return _bandH + row * _slotH;
    if (row <= 7) return _bandH + 4 * _slotH + _noonH + _bandH + (row - 4) * _slotH;
    return _bandH + 4 * _slotH + _noonH + _bandH + 4 * _slotH + _bandH + (row - 8) * _slotH;
  }

  double get _gridH => _rowY(10) + _slotH;

  /// 当周某列（0=周一）的日期 ISO；无学期起点返回空串。
  String _colISO(int zs, int di) {
    if (tt.startDate.isEmpty) return '';
    return TimetableStore.iso(TimetableStore.dateOfWeekDay(tt.startDate, zs, di));
  }

  TtAdjust? _colAdjust(int zs, int di) {
    final iso = _colISO(zs, di);
    if (iso.isEmpty) return null;
    for (final a in tt.adjustments) {
      if (a.date == iso) return a;
    }
    return null;
  }

  /// 该列实际按星期几的课表上课；off 放假返回 null。
  int? _colEffDay(int zs, int di) {
    final a = _colAdjust(zs, di);
    if (a == null) return di;
    return a.type == 'off' ? null : a.day;
  }

  List<TtCourse> _coursesOf(int zs) =>
      _allCourses.where((c) => TimetableStore.coversWeek(c, zs)).toList();

  List<String> _datesOf(int zs) {
    if (tt.startDate.isEmpty) return List.filled(7, '');
    return [for (var di = 0; di < 7; di++) _colISO(zs, di).substring(5).replaceAll('-', '/')];
  }

  Widget _weekPage(int zs) {
    final all = _allCourses;
    final dates = _datesOf(zs);
    final todayIdx = _todayWeek == zs ? DateTime.now().weekday - 1 : -1;
    final hasAny = all.isNotEmpty || tt.events.isNotEmpty;
    if (!hasAny && _loadingWeeks.contains(zs)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!hasAny && !AppState.I.loggedIn && zs == 1) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_calendar_outlined, size: 40, color: SemColors.textMuted),
            const SizedBox(height: 8),
            Text('还没有课程', style: TextStyle(color: SemColors.textMuted)),
            const SizedBox(height: 4),
            Text(
                AppState.I.direct
                    ? '点右上角 + 手动添加，或在连接设置填好凭据后从教务导入'
                    : '点右上角 + 手动添加，或登录后从教务导入',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            const SizedBox(height: 60),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 80),
            child: Container(
              decoration: BoxDecoration(
                color: SemColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SemColors.border),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                height: _headerH + _gridH + 8,
                child: Column(
                  children: [
                    _dayHeaders(zs, dates, todayIdx),
                    Expanded(
                      child: Stack(
                      children: [
                        // 中午细线（11:55）
                        Positioned(
                          top: _bandH + 4 * _slotH + _noonH / 2 - 0.5,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: _axisW,
                                child: Text('11:55',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 8, color: SemColors.textMuted)),
                              ),
                              Expanded(
                                child: Container(height: 1, color: SemColors.border),
                              ),
                            ],
                          ),
                        ),
                        // 节次轴
                        Positioned(
                          left: 0,
                          top: 0,
                          width: _axisW,
                          height: _gridH,
                          child: Column(
                            children: [
                              for (final group in const [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10]]) ...[
                                for (final row in group)
                                  SizedBox(
                                    width: _axisW,
                                    height: _slotH,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('${row + 1}',
                                              style: TextStyle(
                                                  fontSize: 11, fontWeight: FontWeight.w600,
                                                  color: SemColors.textMuted)),
                                          Text(_slotTimes[row],
                                              style: TextStyle(
                                                  fontSize: 7.5, color: SemColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (group != const [8, 9, 10]) SizedBox(width: _axisW, height: _bandH + (group == const [0, 1, 2, 3] ? _noonH : 0)),
                              ],
                            ],
                          ),
                        ),
                        // 7 天列（调休规则在渲染层生效）
                        Positioned(
                          left: _axisW,
                          right: 0,
                          top: 0,
                          height: _gridH,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(7, (di) {
                              final eff = _colEffDay(zs, di);
                              final dayCourses = eff == null
                                  ? const <TtCourse>[]
                                  : all.where((c) => c.day == eff && TimetableStore.coversWeek(c, zs)).toList();
                              final dayEvents = tt.events
                                  .where((e) => e.date.isEmpty
                                      ? (eff != null && e.day == eff)
                                      : e.date == _colISO(zs, di))
                                  .toList();
                              return Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: SemColors.border.withValues(alpha: 0.7),
                                        style: BorderStyle.solid,
                                      ),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      for (final c in dayCourses) _courseBlock(c, zs, _colISO(zs, di)),
                                      for (final e in dayEvents) ..._eventBlock(e),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        // 时段色带最后绘制：盖在天分隔竖线上方，且不进入左侧时间列
                        _band(0, '上午'),
                        _band(_bandH + 4 * _slotH + _noonH, '下午'),
                        _band(_bandH + 4 * _slotH + _noonH + _bandH + 4 * _slotH, '晚上'),
                      ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayHeaders(int zs, List<String> dates, int todayIdx) {
    final monthLabel = dates.isEmpty || dates.first.isEmpty ? '' : '${int.tryParse(dates.first.split('/')[0]) ?? ''}月';
    return SizedBox(
      height: _headerH,
      child: Row(
        children: [
          SizedBox(
            width: _axisW,
            child: Text(monthLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, color: SemColors.textMuted)),
          ),
          Expanded(
            child: Row(
              children: List.generate(7, (i) {
                final isToday = i == todayIdx;
                final adj = _colAdjust(zs, i);
                final wdColor = adj == null
                    ? (isToday ? SemColors.accent : SemColors.textPrimary)
                    : (adj.type == 'off' ? SemColors.danger : SemColors.info);
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: isToday ? SemColors.accentStrong : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('周${'一二三四五六日'[i]}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: wdColor)),
                        Text(
                          dates.isEmpty ? '-' : (dates[i].isEmpty ? '-' : dates[i]),
                          style: TextStyle(
                              fontSize: 10,
                              color: isToday
                                  ? SemColors.accent
                                  : SemColors.textMuted.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _band(double top, String label) => Positioned(
        top: top,
        left: _axisW, // 不进入最左时间列
        right: 0,
        height: _bandH,
        child: Container(
          color: SemColors.stripe,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(fontSize: 9, letterSpacing: 2, color: SemColors.textMuted),
          ),
        ),
      );

  /// 这节课是否已上完（置灰依据）：该列**当天日期 + 实际下课时刻**已过。
  /// 不能只看「今天那一列」——本周周一~周三的课在周四看时早已上完，也该置灰（同网站 lessonPassed）。
  bool _isPast(TtCourse c, String colISO) =>
      TimetableStore.lessonPassed(colISO, _slotEndTimes[c.slotEnd.clamp(0, 10)]);

  Widget _courseBlock(TtCourse c, int zs, String colISO) {
    final name = c.name;
    final past = _isPast(c, colISO);
    // slotStart/slotEnd = 小节序号，直接定位到行
    final rowStart = c.slotStart.clamp(0, 10);
    final rowEnd = c.slotEnd.clamp(0, 10) + 1; // 半开区间
    final top = _rowY(rowStart);
    final height = (rowEnd - rowStart) * _slotH - 4;
    return Positioned(
      top: top + 2,
      height: height,
      left: 2,
      right: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showCourseDetail(c, zs),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: past ? SemColors.neutralSoft : _courseColor(name),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_slotTimes[rowStart.clamp(0, 10)],
                    style: TextStyle(
                        fontSize: 9,
                        color: past ? SemColors.textMuted : SemColors.textSecondary)),
                Text(name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: past ? SemColors.textMuted : SemColors.textPrimary)),
                const Spacer(),
                Text(c.place.isEmpty ? '' : c.place,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        height: 1.15,
                        color: past ? SemColors.textMuted : SemColors.textSecondary)),
                if (c.teachers.isNotEmpty)
                  Text(c.teachers,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: SemColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 日程 / 考试块：按时间覆盖的小节行定位（同网站考试卡规则）。
  List<Widget> _eventBlock(TtEvent e) {
    final sm = _hm(e.start);
    final em = _hm(e.end);
    if (sm < 0 || em < 0) return const [];
    var first = -1;
    var last = -1;
    for (var s = 0; s <= 10; s++) {
      final bMin = _hm(_slotTimes[s]);
      final eMin = _hm(_slotEndTimes[s]);
      if (em > bMin && sm < eMin) {
        if (first < 0) first = s;
        last = s;
      }
    }
    if (first < 0) return const [];
    final rowStart = first;
    final rowEnd = last + 1;
    final top = _rowY(rowStart);
    final height = (rowEnd - rowStart) * _slotH - 4;
    final isExam = e.kind == 'exam';
    return [
      Positioned(
        top: top + 2,
        height: height,
        left: 2,
        right: 2,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isExam ? SemColors.dangerSoft : SemColors.accentSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (isExam ? SemColors.danger : SemColors.accent).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.start}${e.end.isNotEmpty ? '~${e.end}' : ''}',
                  style: TextStyle(fontSize: 9, color: isExam ? SemColors.danger : SemColors.accent)),
              Text(e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: isExam ? SemColors.danger : SemColors.textPrimary)),
              const Spacer(),
              if (e.place.isNotEmpty)
                Text(e.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: SemColors.textSecondary)),
              if (e.seat.isNotEmpty)
                Text('座位 ${e.seat}',
                    style: TextStyle(fontSize: 9, color: SemColors.textSecondary)),
            ],
          ),
        ),
      ),
    ];
  }

  static int _hm(String s) {
    final p = s.split(':');
    if (p.length != 2) return -1;
    return (int.tryParse(p[0]) ?? -1) * 60 + (int.tryParse(p[1]) ?? -1);
  }

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(k, style: TextStyle(color: SemColors.textSecondary)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  /// 与网站一致：课名哈希 → 5 色相（蓝紫/青绿/橙/绿/粉），16% 透明度底色。
  static const _hues = [258.0, 174.0, 25.0, 145.0, 335.0];

  Color _courseColor(String name) {
    var h = 0;
    for (final ch in name.codeUnits) {
      h = (h * 31 + ch) % 100000;
    }
    final hue = _hues[h % _hues.length];
    // 深色下提亮提饱和，玻璃底上保持课块色彩辨识度（文字仍为 textPrimary）
    return SemColors.isDark
        ? HSLColor.fromAHSL(0.30, hue, 0.55, 0.68).toColor()
        : HSLColor.fromAHSL(0.16, hue, 0.70, 0.58).toColor();
  }
}
