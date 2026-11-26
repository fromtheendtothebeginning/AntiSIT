part of 'course_select_page.dart';

/// 课程数据加载（轮次 / 课程分页 / 教学班）与抢课调度（定时提交、按结果码收停）。
mixin _CourseSelectService on State<CourseSelectPage> {
  /// 当前选课轮次（页面实现）。
  CourseScope? get _scope;

  /// 能拿选课数据：直连或演示模式（页面实现）。
  bool get _isDirect;

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

  /// 提交间隔与总次数上限。
  static const int _grabIntervalMs = 1500;
  static const int _grabMaxAttempts = 120;

  /// 加载选课轮次，成功后自动拉第一轮课程。
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

  /// 分页加载课程（reset = 从头，more = 追加）。
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
      final list = await ApiClient.I.courseOffers(
        scope,
        keyword: _keyword,
        start: start,
      );
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

  /// 加载某门课的教学班；已缓存且非 force 时不重复请求。
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
      setState(
        () => _sectionErrors[key] = e is ApiError ? e.message : e.toString(),
      );
    } finally {
      if (mounted) setState(() => _loadingSections.remove(key));
    }
  }

  /// 课程在教学班缓存里的键（轮次 + 课程 id）。
  String _keyOf(CourseOffer offer) => '${offer.scopeId}|${offer.id}';

  /// 切换选课轮次：清空列表与教学班缓存后重新拉。
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

  /// 按当前输入框内容搜索。
  void _searchNow() {
    _keyword = _search.text.trim();
    _loadOffers(reset: true);
  }

  /// 抢课前确认：说明提交间隔，以及结果不确定时立刻停手。
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('开始抢课'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _startGrab(offer, section);
  }

  /// 开始定时提交（立即先跑一次）。
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

  /// 单次提交：按结果码决定继续等待还是收停。
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
          setState(
            () => _grabText =
                '第 $_grabAttempt 次 · 名额已满，继续等待…${result.message.isEmpty ? '' : '\n${result.message}'}',
          );
        case CourseSelectStatus.roundClosed:
          _stopGrab(
            message: result.message.isEmpty ? '当前不属于选课阶段' : result.message,
          );
        case CourseSelectStatus.needCaptcha:
          _stopGrab(
            message:
                result.message.isEmpty ? '教务要求验证码，请重新登录后再试' : result.message,
          );
        case CourseSelectStatus.sessionExpired:
          _stopGrab(message: '教务登录已失效，请返回重新进入后重试');
        case CourseSelectStatus.conflict:
        case CourseSelectStatus.creditLimit:
          _stopGrab(
            message: result.message.isEmpty ? '选课被学校拒绝' : result.message,
          );
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
      final uncertain = RegExp(
        r'超时|网络|连接|Socket|timed out',
        caseSensitive: false,
      ).hasMatch(msg);
      _stopGrab(
        message: uncertain ? '请求结果不确定，已停止自动重试。请到「已选课程」确认是否已选上\n$msg' : msg,
      );
    } finally {
      if (mounted && _grabActive) setState(() => _grabBusy = false);
    }
  }

  /// 停止抢课；非 silent 且有结果时弹提示。
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: success ? SemColors.success : null,
          duration: Duration(seconds: success ? 3 : 5),
        ),
      );
    }
  }
}
