import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;

import 'package:campus_core/campus_core.dart';

import 'timetable_background.dart';
import 'timetable_cards.dart';
import 'timetable_detail_sheets.dart';
import 'timetable_forms.dart';
import 'timetable_grid.dart';
import 'timetable_ics_page.dart';
import 'timetable_import.dart';
import 'timetable_nav.dart';
import 'timetable_semester_sheets.dart';
import 'timetable_settings_page.dart';
import 'timetable_shell.dart';

/// 课程表：周 / 日视图、教务与考试导入、调休规则、学期设置（底栏第 1 页）。
/// 本地课表（手动课程 / 调休规则 / 考试日程）不依赖登录；教务导入需登录。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  /// 今天下一个「下课」时刻——只看节次时间，与星期几无关；今天没有了返回 null。
  /// 抽成纯函数是为了不等到真的下课也能测。
  @visibleForTesting
  static DateTime? nextSlotEndAfter(DateTime now, List<String> slotEndTimes) {
    DateTime? next;
    for (final hhmm in slotEndTimes) {
      final parts = hhmm.split(':');
      final at = DateTime(
        now.year,
        now.month,
        now.day,
        int.tryParse(parts.first) ?? 0,
        int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      );
      if (at.isAfter(now) && (next == null || at.isBefore(next))) next = at;
    }
    return next;
  }

  /// 今天剩下还没上完的课（第一门即「最近的一节」）——实现在 TimetableStore.upcomingOn。
  /// [dayIndex] 要传**今天所在的列**（不是调休被借的星期），否则日期会算到别的天上去。
  static List<TtCourse> upcomingToday(
    List<TtCourse> courses, {
    required String startDate,
    required int week,
    required int dayIndex,
    DateTime? now,
  }) =>
      TimetableStore.upcomingOn(
        courses,
        startDate: startDate,
        week: week,
        dayIndex: dayIndex,
        endTimes: TimetableStore.slotEnds,
        now: now,
      );

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late String xnm;
  late String xqm;

  /// 两个分页控制器都挂 `onAttach`：PageView 一挂上就来消费「待跳页」。
  /// 这是「跳页不丢」的关键——冷启动 / 切周视图 / 切日视图时 PageView 都是后建的，
  /// 建好之前 `hasClients` 为 false，直接跳会静默丢失。
  ///
  /// ⚠️ `onAttach` 是在**布局阶段**回调的（ScrollPosition 正在 attach）：那里不能
  /// `setState`、也不该当时就 `jumpToPage`，一律排到帧末。
  late final PageController _pc = PageController(onAttach: (_) => _schedulePendingWeek());
  late final PageController _dayPc = PageController(onAttach: (_) => _schedulePendingDay());
  int _shownWeek = 1;
  int _shownDay = 0; // 0=周一
  DateTime? _lastNavTap; // 上次点击周次标题的时间：500ms 内点两次回今天
  bool _dayView = false;
  bool _booting = true;
  final Set<int> _loadingWeeks = {};
  List<Map<String, dynamic>>? _terms; // 成绩接口返回的学期列表（登录后）
  Timer? _tick;

  /// 待跳的周视图页码（null = 没有待办）：等 PageView 挂上后由 [_applyPendingWeek] 消费。
  int? _pendingWeekPage;

  /// 待跳时是否用动画（挂上就跳的那一刻才知道，所以和页码一起记）。
  bool _pendingWeekAnimate = false;

  /// 日视图待跳页码（同上，日报不可跨周：切回周视图时按当前周重算）。
  int? _pendingDayPage;

  /// 下课那一刻的精确重绘（见 [_scheduleFlip]）。
  Timer? _flip;

  /// 日视图分页高度：当周各天内容的最大高度（每天课数不同，量完才知道）。
  double _dayPagerH = 0;
  final List<GlobalKey> _dayProbeKeys = List.generate(7, (_) => GlobalKey());

  static const _maxZs = kMaxSemesterWeeks;

  // 课程 / 日程的 slotStart/slotEnd = 小节序号（0 起，0-10），不是「大节」；
  // 各节上下课时刻见 TimetableStore.slotStarts / slotEnds（导出日历经同一份表）。

  SemesterTt get tt => TimetableStore.instance.semester(xnm, xqm);
  bool _isImported(TtCourse c) => c.id.startsWith('jw-');
  int get _weekCount => tt.weekCount.clamp(1, _maxZs);
  int? get _todayWeek => TimetableStore.locateToday(tt.startDate, tt.weekCount);

  /// 手动课程排在教务课程之后 → 渲染时在上层（同位置重叠时用户自己的课优先可见）。
  List<TtCourse> get _allCourses => [
        ...TimetableStore.deriveImported(tt),
        ...tt.courses,
      ];

  @override
  void initState() {
    super.initState();
    final (a, b) = AppState.inferSemester(DateTime.now());
    xnm = a;
    xqm = b;
    // 自定义背景（异步读本地设置，就绪后通知重建）
    TtBackground.I.load();
    // 60s 心跳：过点课程置灰（同网站）+ 兜住跨天/跨周这类粗粒度变化
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
      _scheduleFlip();
    });
    _scheduleFlip();
    AppState.I.addListener(_onAppChange);
    // 提醒插件的启停决定 AppBar 上那颗铃铛在不在，跟着注册表一起刷新
    PluginRegistry.I.addListener(_onAppChange);
    _wasLoggedIn = AppState.I.loggedIn;
    _init();
  }

  /// 在下课那一刻再重绘一次（只有 60s 心跳时，09:55 下课的课最晚 09:55:59 才变灰）。
  /// 按节次下课时刻排一个一次性定时器，到点刷新后重排下一次。
  void _scheduleFlip() {
    _flip?.cancel();
    final now = DateTime.now();
    final next = TimetablePage.nextSlotEndAfter(now, TimetableStore.slotEnds);
    // 今天剩下的课都结束了就不排（明天的事交给心跳）
    if (next == null) return;
    _flip = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleFlip();
    });
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
    _flip?.cancel();
    AppState.I.removeListener(_onAppChange);
    PluginRegistry.I.removeListener(_onAppChange);
    _pc.dispose();
    _dayPc.dispose();
    super.dispose();
  }

  /// 初始化：载入本地 store、同步云端、定位到今天的周/日。
  Future<void> _init({bool keepSemester = false}) async {
    if (mounted) setState(() => _booting = true);
    await TimetableStore.instance.load();
    final adopted = await TimetableStore.instance.syncCloud();
    final manualGrade = AppState.I.direct ? AppState.I.creds.grade.trim() : '';
    if (manualGrade.isNotEmpty && TimetableStore.instance.nj != manualGrade) {
      TimetableStore.instance.nj = manualGrade;
    }
    if (adopted && !keepSemester) {
      // 云端数据覆盖本地后学期可能变化：重置到推断学期。
      // 显式切换学期（keepSemester）时不重置，否则切换会被弹回当前学期。
      final (a, b) = AppState.inferSemester(DateTime.now());
      xnm = a;
      xqm = b;
    }
    _fixWeekCount();
    // 记下「课表现在显示的是哪个学期」：从「我的 → 课程表设置」进来时靠它定位学期。
    TimetableStore.instance.active = '$xnm-$xqm';
    // 只定「日」，**不动周指示器**：周指示器等跳页真正落地时再由 _applyPendingWeek
    // 一起写。否则数据慢 / PageView 还没挂上时，指示器已经跳到本周、内容还停在第 1 周，
    // 就是 issue #13 那个分裂。
    _shownDay = DateTime.now().weekday - 1;
    if (mounted) setState(() => _booting = false);
    if (AppState.I.loggedIn) await _ensureWeek(_todayWeek ?? 1);
    _jumpTo(_todayWeek ?? 1, animate: false);
  }

  void _fixWeekCount() => fixSemesterWeekCount(tt);

  /// 跳到第 [zs] 周（1 起）。**指示器只在真正跳页时赋值**（见 [_applyPendingWeek]）。
  void _jumpTo(int zs, {bool animate = true}) {
    _pendingWeekPage = zs.clamp(1, _weekCount) - 1;
    _pendingWeekAnimate = animate;
    // 可能在 build / layout 里被调（守护条件：不可用时下次再来），一律排到帧末
    _schedulePendingWeek();
  }

  /// 帧末消费一次「待跳页」（onAttach 与各处请求都走它，同一帧只排一次）。
  ///
  /// **能立刻跳就立刻跳**：点击「上一周 / 下一周」、双击周次标题这些都在 idle 阶段
  /// 进这里，此时跳页没有任何理由等——`addPostFrameCallback` 自己**不会排帧**，
  /// 一律延后就会变成「点了没反应，要等下个 60s 心跳才生效」。
  /// 只有在 build / layout 期间（onAttach、切视图那类）才必须延到帧末。
  void _schedulePendingWeek() {
    final binding = WidgetsBinding.instance;
    if (_pendingWeekPage == null) return;
    if (binding.schedulerPhase == SchedulerPhase.idle && _pc.hasClients) {
      _applyPendingWeek();
      return;
    }
    if (_pendingWeekScheduled) return;
    _pendingWeekScheduled = true;
    binding.addPostFrameCallback((_) {
      _pendingWeekScheduled = false;
      _applyPendingWeek();
    });
    // addPostFrameCallback 不排帧：不在帧中时得主动要一帧，回调才会跑
    binding.ensureVisualUpdate();
  }

  bool _pendingWeekScheduled = false;

  /// 跳页收尾：PageView 挂上、能跳了才动，**跳成功的那一次同时写指示器**。
  void _applyPendingWeek() {
    final target = _pendingWeekPage;
    if (target == null || !_pc.hasClients) return;
    _pendingWeekPage = null;
    if (_pendingWeekAnimate) {
      _pc.animateToPage(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pc.jumpToPage(target);
    }
    _shownWeek = target + 1;
    if (mounted) setState(() {});
  }

  Future<void> _ensureWeek(int zs, {bool force = false}) => ensureSemesterWeek(
        context,
        xnm: xnm,
        xqm: xqm,
        tt: tt,
        week: zs,
        maxWeeks: _maxZs,
        loadingWeeks: _loadingWeeks,
        onChanged: () {
          if (mounted) setState(() {});
        },
        force: force,
      );

  Future<void> _importAll() async {
    final lastWeek = await importSemesterCourses(
      context,
      xnm: xnm,
      xqm: xqm,
      tt: tt,
      maxWeeks: _maxZs,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    if (lastWeek > 0) {
      final tw = _todayWeek;
      if (tw != null) _jumpTo(tw);
    }
  }

  Future<void> _importExams() => importExamEvents(
        context,
        xnm: xnm,
        xqm: xqm,
        tt: tt,
        onChanged: () {
          if (mounted) setState(() {});
        },
      );

  /// 切换学期：选完重载课表（新建学期则再进学期设置）。
  Future<void> _pickSemester() async {
    final choice = await showSemesterPicker(
      context,
      xnm: xnm,
      xqm: xqm,
      terms: _terms,
      onTermsLoaded: (t) => _terms = t,
    );
    if (!mounted || choice == null) return;
    if (choice.isNew) {
      await _newSemester();
      return;
    }
    if (choice.xnm != xnm || choice.xqm != xqm) {
      setState(() {
        xnm = choice.xnm;
        xqm = choice.xqm;
      });
      _init(keepSemester: true);
    }
  }

  /// 新建空学期：选学年 + 学期码 → 建档并切换 → 立刻打开「学期设置」。
  Future<void> _newSemester() async {
    final created = await showNewSemesterPicker(context, xnm: xnm, xqm: xqm);
    if (!mounted || created == null) return;
    if (created.xnm != xnm || created.xqm != xqm) {
      setState(() {
        xnm = created.xnm;
        xqm = created.xqm;
      });
      TimetableStore.instance.semester(created.xnm, created.xqm); // 建空学期
      await TimetableStore.instance.persist();
      await _init(keepSemester: true);
    }
    if (mounted) _semSettings(); // 新建后立刻到学期设置（设起点 / 周数）
  }

  /// 学期设置弹窗（弹窗实现在 timetable_semester_sheets.dart，课表页与设置页共用）。
  Future<void> _semSettings() => showSemesterSettingsSheet(
        context,
        xnm,
        xqm,
        onSaved: () => setState(() {}),
      );

  /// 「课程表设置」二级页（学期 / 调休 / 上课提醒 / 淡化显示），回来时刷一次。
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TimetableSettingsPage(semesterKey: '$xnm-$xqm'),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 「导出 / 导入日历」：把课表导成 .ics，或把日历文件导进来当日程。
  Future<void> _openCalendarIo() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TimetableIcsPage(xnm: xnm, xqm: xqm),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _courseForm({TtCourse? existing, bool imported = false}) async {
    final saved = await showCourseForm(
      context,
      tt: tt,
      existing: existing,
      imported: imported,
    );
    if (saved && mounted) setState(() {});
  }

  void _courseFormAdd() => _courseForm();

  void _showCourseDetail(TtCourse c, int zs) {
    final imported = _isImported(c);
    showCourseDetailSheet(
      context,
      course: c,
      imported: imported,
      onEdit: () => _courseForm(existing: c, imported: imported),
      onDelete: () => _deleteCourse(c, zs),
    );
  }

  Future<void> _deleteCourse(TtCourse c, int zs) async {
    await deleteCourse(
      context,
      tt: tt,
      course: c,
      week: zs,
      imported: _isImported(c),
    );
    if (mounted) setState(() {});
  }

  Future<void> _eventForm({TtEvent? existing}) async {
    final saved = await showEventForm(context, tt: tt, existing: existing);
    if (saved && mounted) setState(() {});
  }

  void _showEventDetail(TtEvent e) => showEventDetailSheet(
        context,
        event: e,
        onEdit: () => _eventForm(existing: e),
        onDelete: () => _deleteEvent(e),
      );

  void _deleteEvent(TtEvent e) {
    setState(() => tt.events.removeWhere((x) => x.id == e.id));
    TimetableStore.instance.save();
  }

  /// 跨插件能力：按「接口 + 提供方插件 id」从注册表取，停用 / 未装时取不到（铃铛整颗不出现）。
  ReminderCapability? get _reminder =>
      PluginRegistry.I.capability<ReminderCapability>(PluginIds.reminder);

  /// 上课提醒开关：打开时申请通知权限（必要时再要精确闹钟权限），并按当前课表排期。
  Future<void> _onReminderToggle(bool v) async {
    final reminder = _reminder;
    if (reminder == null) return;
    final messenger = ScaffoldMessenger.of(context);
    String? tip;
    if (v) {
      tip = await reminder.enable();
    } else {
      await reminder.disable();
      tip = '已关闭上课提醒';
    }
    if (!mounted) return;
    if (tip != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(tip), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// 课表页 AppBar 的提醒图标：点击即开关（与「我的」页开关同一份状态）。
  Future<void> _toggleReminder() =>
      _onReminderToggle(!(_reminder?.enabled ?? false));

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 整页监听 AppState：「悬浮玻璃顶栏」开关改完要连 Scaffold 一起重建
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已被扣掉状态栏）
        final topInset = glassTopInset(context);
        return buildTimetableScaffold(
          context: context,
          title: TimetableStore.instance.semesterLabel('$xnm-$xqm') ?? '课程表',
          onTitleTap: _pickSemester,
          actions: buildTimetableActions(
            dayView: _dayView,
            onToggleView: _toggleView,
            reminder: _reminder,
            onToggleReminder: _toggleReminder,
            loggedIn: AppState.I.loggedIn,
            onMenuSelected: _onMenu,
          ),
          body: buildTimetableBody(
            context: context,
            topInset: topInset,
            dayView: _dayView,
            onDayViewLayout: _measureDayPager,
            todayCard: _todayCard,
            examStrip: _examStrip,
            pagerBuilder: (width) => _dayView ? _dayPager(width) : _weekPager(),
            navBar: _dayView ? _dayNav : _weekNav,
          ),
        );
      },
    );
  }

  /// 顶栏的周 / 日视图切换：换算成对侧分页的页码后再切，避免落到第一页。
  void _toggleView() {
    if (!_dayView) {
      // 切到日视图：目标页 = 当前显示的周/日；周/日指示器与目标页同源，不会分裂
      final target = (_shownWeek - 1) * 7 + _shownDay;
      setState(() {
        _dayView = true;
        _shownWeek = target ~/ 7 + 1;
        _shownDay = target % 7;
      });
      _jumpDayWhenReady(target);
    } else {
      final week = _shownWeek;
      setState(() => _dayView = false);
      _jumpTo(week, animate: false);
    }
  }

  /// 日视图分页的「挂上就跳」：与周视图同一套（不落地就不改指示器）。
  void _jumpDayWhenReady(int targetPage) {
    _pendingDayPage = targetPage;
    _schedulePendingDay();
  }

  void _schedulePendingDay() {
    final binding = WidgetsBinding.instance;
    if (_pendingDayPage == null) return;
    if (binding.schedulerPhase == SchedulerPhase.idle && _dayPc.hasClients) {
      _applyPendingDay();
      return;
    }
    if (_pendingDayScheduled) return;
    _pendingDayScheduled = true;
    binding.addPostFrameCallback((_) {
      _pendingDayScheduled = false;
      _applyPendingDay();
    });
    binding.ensureVisualUpdate();
  }

  bool _pendingDayScheduled = false;

  void _applyPendingDay() {
    final target = _pendingDayPage;
    if (target == null || !_dayPc.hasClients) return;
    _pendingDayPage = null;
    _dayPc.jumpToPage(target);
    if (mounted) setState(() {});
  }

  /// 「更多」菜单的分发。
  void _onMenu(String v) {
    switch (v) {
      case 'addCourse':
        _courseFormAdd();
      case 'addEvent':
        _eventForm();
      case 'import':
        _importAll();
      case 'exams':
        _importExams();
      case 'ical':
        _openCalendarIo();
      case 'settings':
        _openSettings();
      case 'switch':
        _pickSemester();
      case 'refresh':
        _ensureWeek(_shownWeek, force: true);
    }
  }

  /// 周视图分页：只有课表格子（顶部两块在分页之外），高度固定（11 节网格）。
  Widget _weekPager() => buildWeekPager(
        controller: _pc,
        weekCount: _weekCount,
        onPageChanged: (i) {
          setState(() => _shownWeek = i + 1);
          _ensureWeek(i + 1);
        },
        gridBuilder: (week) => buildWeekGrid(
          tt: tt,
          week: week,
          todayWeek: _todayWeek,
          allCourses: _allCourses,
          loggedIn: AppState.I.loggedIn,
          directMode: AppState.I.direct,
          loading: _loadingWeeks.contains(week),
          onCourseTap: _showCourseDetail,
          onEventTap: _showEventDetail,
        ),
      );

  /// 日视图分页：只有当天内容（顶部两块在分页之外）。
  /// 每天课数不同、页高只好取当周 7 天的最大值：矮的页下方留白，高的页不会被裁掉。
  Widget _dayPager(double width) => buildDayPager(
        controller: _dayPc,
        width: width,
        height: _dayPagerH == 0 ? 320 : _dayPagerH,
        weekCount: _weekCount,
        probeWeek: _shownWeek,
        probeKeys: _dayProbeKeys,
        onPageChanged: (idx) {
          setState(() {
            _shownWeek = idx ~/ 7 + 1;
            _shownDay = idx % 7;
          });
          _ensureWeek(_shownWeek);
        },
        bodyBuilder: _dayBody,
      );

  /// 量出当周各天内容的最大高度 → 作为日视图分页高度（只在变化时重建，不会来回抖）。
  void _measureDayPager() {
    if (!mounted || !_dayView) return;
    var maxH = 0.0;
    for (final key in _dayProbeKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) maxH = math.max(maxH, box.size.height);
    }
    if (maxH > 0 && (maxH - _dayPagerH).abs() > 0.5) {
      setState(() => _dayPagerH = maxH);
    }
  }

  Widget _dayBody(int week, int day) => buildDayBody(
        tt: tt,
        allCourses: _allCourses,
        week: week,
        day: day,
        todayWeek: _todayWeek,
        onCourseTap: _showCourseDetail,
        onEventTap: _showEventDetail,
      );

  Widget _todayCard() => buildTodayCard(
        tt: tt,
        todayWeek: _todayWeek,
        allCourses: _allCourses,
        onOpenSemesterSettings: _semSettings,
      );

  Widget _examStrip() => buildExamStrip(tt: tt);

  Widget _weekNav() => buildWeekNav(
        shownWeek: _shownWeek,
        weekCount: _weekCount,
        onPrev: _shownWeek > 1 ? () => _jumpTo(_shownWeek - 1) : null,
        onNext: _shownWeek < _weekCount ? () => _jumpTo(_shownWeek + 1) : null,
        onTitleTap: () {
          if (_navTitleTappedTwice()) {
            final tw = _todayWeek;
            _jumpTo(tw ?? 1);
          }
        },
      );

  Widget _dayNav() => buildDayNav(
        shownWeek: _shownWeek,
        shownDay: _shownDay,
        weekCount: _weekCount,
        onGoDay: _goDay,
        onTitleTap: () {
          if (_navTitleTappedTwice()) {
            final tw = _todayWeek;
            _goDay(tw ?? 1, DateTime.now().weekday - 1);
          }
        },
      );

  /// 周次标题 500ms 内被点第二次 → 回到今天。
  bool _navTitleTappedTwice() {
    final now = DateTime.now();
    final twice = _lastNavTap != null &&
        now.difference(_lastNavTap!) < const Duration(milliseconds: 500);
    _lastNavTap = twice ? null : now;
    return twice;
  }

  void _goDay(int week, int day) {
    final idx = ((week - 1) * 7 + day).clamp(0, _weekCount * 7 - 1);
    // 日视图分页未必已挂上（切回来那一帧）：没挂上就走「挂上再跳」，别静默丢掉
    if (!_dayPc.hasClients) {
      _jumpDayWhenReady(idx);
      return;
    }
    _dayPc.animateToPage(
      idx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }
}
