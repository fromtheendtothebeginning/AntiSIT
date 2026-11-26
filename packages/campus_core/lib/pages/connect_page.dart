import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../direct/campus_direct.dart';
import '../direct/epay.dart';
import '../direct/mock_campus_server.dart';
import '../direct/school.dart';
import '../widgets/common.dart';
import '../widgets/floating_tabs_header.dart';
import 'connect_credentials_card.dart';
import 'connect_direct_section.dart';
import 'connect_mock_card.dart';
import 'connect_school_card.dart';
import 'connect_server_section.dart';

// 各段与各卡拆到同目录文件，这里 re-export 保持 connect_page.dart 的出口不变。
export 'connect_common.dart';
export 'connect_credentials_card.dart';
export 'connect_direct_section.dart';
export 'connect_mock_card.dart';
export 'connect_school_card.dart';
export 'connect_self_host_card.dart';
export 'connect_server_section.dart';

/// 连接设置：服务器模式（填服务器地址 + 该服务器的账号）与直连模式（填学校系统信息 + 校园凭据）。
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late AppMode _mode = AppState.I.mode;

  /// 模式滑块的连续位置（0 = 服务器 / 1 = 直连）：下方两套设置跟着它一起左右滑动。
  final ValueNotifier<double> _tabPos = ValueNotifier<double>(0);

  /// 在页面区域横滑时写这里（非 null = 拖动中），交给 GlassTabs 驱动同一个位置。
  final ValueNotifier<double?> _tabDrag = ValueNotifier<double?>(null);

  int get _tabIndex => _mode == AppMode.server ? 0 : 1;

  final _server = TextEditingController();
  bool _serverTesting = false;
  String? _serverProbe;

  final _schoolName = TextEditingController();
  final _authBase = TextEditingController();
  final _jwxtBase = TextEditingController();
  final _xgBase = TextEditingController();
  final _ecardBase = TextEditingController();
  final _aesKey = TextEditingController();
  bool _allowSelfSigned = false;

  final _sid = TextEditingController();
  final _pwd = TextEditingController();
  final _payPwd = TextEditingController();
  final _dormBuilding = TextEditingController(); // 楼号，如 24。
  final _dormRoom = TextEditingController(); // 寝室号，如 1016。
  final _realName = TextEditingController();
  final _grade = TextEditingController();

  bool _testing = false;
  List<ProbeResult>? _probes;
  String? _error;
  String? _ok;

  @override
  void initState() {
    super.initState();
    _tabPos.value = _tabIndex.toDouble();
    final st = AppState.I;
    _server.text = st.serverUrl;
    _loadSchool(st.school);
    _sid.text = st.creds.studentId;
    _pwd.text = st.creds.password;
    _payPwd.text = st.creds.payPassword;
    final dorm = splitDorm(st.creds.dorm);
    _dormBuilding.text = dorm.building;
    _dormRoom.text = dorm.room;
    _realName.text = st.creds.realName;
    _grade.text = st.creds.grade;
  }

  /// 把学校档案写进表单。
  void _loadSchool(SchoolProfile s) {
    _schoolName.text = s.name;
    _authBase.text = s.authBase;
    _jwxtBase.text = s.jwxtBase;
    _xgBase.text = s.xgBase;
    _ecardBase.text = s.ecardBase;
    _aesKey.text = s.dektAesKey;
    _allowSelfSigned = s.allowSelfSigned;
  }

  /// 用表单当前值组一份学校档案草稿。
  SchoolProfile _draftSchool() => SchoolProfile(
        name: _schoolName.text.trim(),
        authBase: _authBase.text.trim(),
        jwxtBase: _jwxtBase.text.trim(),
        xgBase: _xgBase.text.trim(),
        ecardBase: _ecardBase.text.trim(),
        dektAesKey: _aesKey.text.trim(),
        allowSelfSigned: _allowSelfSigned,
      );

  @override
  void dispose() {
    for (final c in [
      _server,
      _schoolName,
      _authBase,
      _jwxtBase,
      _xgBase,
      _ecardBase,
      _aesKey,
      _sid,
      _pwd,
      _payPwd,
      _dormBuilding,
      _dormRoom,
      _realName,
      _grade,
    ]) {
      c.dispose();
    }
    _tabPos.dispose();
    _tabDrag.dispose();
    super.dispose();
  }

  void _setTab(int i) {
    if (i == _tabIndex) return;
    setState(() {
      _mode = i == 0 ? AppMode.server : AppMode.direct;
      _probes = null;
      _error = null;
      _ok = null;
    });
  }

  void _onTabDragStart(DragStartDetails _) => _tabDrag.value = _tabPos.value;

  void _onTabDragUpdate(DragUpdateDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    if (w <= 0) return;
    // 与内容方向一致：往左拖 = 去下一格。
    final next = ((_tabDrag.value ?? _tabPos.value) - d.delta.dx / w).clamp(
      0.0,
      1.0,
    );
    _tabDrag.value = next;
    // 「界面实时跟着滑块切换」关掉时不在拖动中换——等松手落位再换。
    if (AppState.I.followSlider) _setTab(next.round());
  }

  void _onTabDragEnd(DragEndDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final v = (-d.velocity.pixelsPerSecond.dx / (w <= 0 ? 1 : w)).clamp(
      -8.0,
      8.0,
    );
    var target = (_tabDrag.value ?? _tabPos.value).round().clamp(0, 1);
    final next = target + (v > 0 ? 1 : -1);
    if (v.abs() >= 5.0 && next >= 0 && next <= 1) target = next; // 甩动多滑一格。
    _tabDrag.value = null; // 交还弹簧：滑块从当前位置弹到落点。
    _setTab(target);
  }

  /// 两套设置并排放在同一个 Stack 里：最贴近滑块的那套决定高度，另一套跟着位置滑进滑出。
  ///
  /// 三处细节都是为了不出现「奇怪的阴影」：
  /// * 已被滑到屏外的那套用 [Offstage] 彻底不画 —— 它的 AppCard 外投影（blur 24）
  ///   会从屏幕另一侧渗回来，在左右边缘各留一条暗带，且随模式切换左右换边。
  /// * 裁剪只裁横向、且**仅滑动中才裁**：静止时还裁的话，[ClipRect] 会沿着卡片
  ///   左右边缘把柔和的圆角外投影竖直切断，卡片下方就留下一条带硬直边的矩形暗带。
  ///   见 [_HorizontalClipper]。
  Widget _slidingSections(AppState st) => ValueListenableBuilder<double>(
        valueListenable: _tabPos,
        builder: (context, rawPos, _) {
          // 开关关掉时两套设置不跟滑块连续滑，只按已落位的模式显示（松手才切）。
          final pos = AppState.I.followSlider ? rawPos : _tabIndex.toDouble();
          final w = MediaQuery.sizeOf(context).width;
          final active = pos.round().clamp(0, 1);
          final other = 1 - active;
          // 弹簧收尾不是精确落点（可能停在 0.999x），阈值留一点余量。
          final sliding = (pos - active).abs() > 0.002;
          Widget panel(int i) => i == 0 ? _serverPanel(st) : _directPanel(st);
          return AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            // 顶部锚定：默认的居中会让内容在高度动画期间整体上下漂移。
            alignment: Alignment.topCenter,
            // 纵向不裁：默认 hardEdge 会沿这块的边界把 AppCard 的外投影切断。
            clipBehavior: Clip.none,
            child: ClipRect(
              clipper: _HorizontalClipper(sliding: sliding),
              child: Stack(
                children: [
                  // 当前这套：既是滑动的一方，也决定这块的高度。
                  Transform.translate(
                    offset: Offset((active - pos) * w, 0),
                    child: panel(active),
                  ),
                  // 另一套按自身高度布局（不能 Positioned.fill：会被拉成当前那套的高度）。
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Transform.translate(
                      offset: Offset((other - pos) * w, 0),
                      // 完全滑出屏幕后不再绘制：投影不会渗回可见区域。
                      child: Offstage(
                        offstage: (other - pos).abs() >= 0.999,
                        child: TickerMode(
                          enabled: (other - pos).abs() < 0.999,
                          child: panel(other),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  /// 服务器模式段。
  Widget _serverPanel(AppState st) => ConnectServerSection(
        server: _server,
        probing: _serverTesting,
        probe: _serverProbe,
        onProbe: _probeServer,
        onSave: _save,
        demo: st.demo,
        loggedIn: st.token != null,
        username: st.username,
        serverUrl: st.serverUrl,
      );

  /// 直连模式段。
  Widget _directPanel(AppState st) => ConnectDirectSection(
        mockCard: kDebugMode
            ? ConnectMockCard(testing: _testing, onUseMock: _useMock)
            : null,
        credentials: ConnectCredentialsCard(
          sid: _sid,
          pwd: _pwd,
          payPwd: _payPwd,
          dormBuilding: _dormBuilding,
          dormRoom: _dormRoom,
          realName: _realName,
          grade: _grade,
          testing: _testing,
          probes: _probes,
          onSave: _save,
          onTest: _testDirect,
        ),
        schoolCard: ConnectSchoolCard(
          schools: st.schools,
          school: st.school,
          name: _schoolName,
          authBase: _authBase,
          jwxtBase: _jwxtBase,
          xgBase: _xgBase,
          ecardBase: _ecardBase,
          aesKey: _aesKey,
          allowSelfSigned: _allowSelfSigned,
          onSelfSignedChanged: (v) => setState(() => _allowSelfSigned = v),
          onAdd: _addSchool,
          onRemove: _removeSchool,
          onPick: _pickSchool,
        ),
      );

  /// 用空体登录请求探测服务器；空地址就地提示，不发请求。
  Future<void> _probeServer() async {
    final url = AppState.normalizeServer(_server.text);
    if (url.isEmpty) {
      setState(() => _serverProbe = '请先填写服务器地址');
      return;
    }
    setState(() {
      _serverTesting = true;
      _serverProbe = null;
    });
    final result = await probeServerEndpoint(url);
    if (!mounted) return;
    setState(() {
      _serverProbe = result;
      _serverTesting = false;
    });
  }

  /// 用草稿地址探测四个学校系统；结束恢复原学校，真正切换交给「保存」。
  Future<void> _testDirect() async {
    final original = AppState.I.school;
    setState(() {
      _testing = true;
      _probes = null;
      _error = null;
    });
    await AppState.I.setSchool(_draftSchool());
    try {
      final r = await CampusDirect.I.testConnection();
      if (mounted) setState(() => _probes = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      await AppState.I.setSchool(original);
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 调试：一键切到本机模拟校园服务（四个系统都在 127.0.0.1，凭据用模拟值）。
  Future<void> _useMock() async {
    setState(() {
      _testing = true;
      _error = null;
      _ok = null;
      _probes = null;
    });
    try {
      await MockCampusServer.instance.start();
      final p = MockCampusServer.instance.profile();
      final st = AppState.I;
      await st.upsertSchool(p);
      await st.setSchool(p);
      st.creds
        ..studentId = MockCampusServer.studentId
        ..password = MockCampusServer.password
        ..payPassword = MockCampusServer.payPassword
        ..dorm = MockCampusServer.dorm
        ..realName = MockCampusServer.realName
        ..grade = MockCampusServer.grade;
      await st.setMode(AppMode.direct);
      await st.persistDirect();
      CampusDirect.I.forgetLoginState();
      st.statusInfo = null;
      st.studentInfo = null;
      if (!mounted) return;
      setState(() {
        _mode = AppMode.direct;
        _loadSchool(p);
        _sid.text = MockCampusServer.studentId;
        _pwd.text = MockCampusServer.password;
        _payPwd.text = MockCampusServer.payPassword;
        final dorm = splitDorm(MockCampusServer.dorm);
        _dormBuilding.text = dorm.building;
        _dormRoom.text = dorm.room;
        _realName.text = MockCampusServer.realName;
        _grade.text = MockCampusServer.grade;
        _ok = '已切换到本地模拟服务（${MockCampusServer.instance.baseUrl}）：'
            '教务 / 统一认证 / 学工 / 校园卡都在本机模拟。返回首页查询会弹出验证码，'
            '图片上的数字就是答案（日志里也会打印）。';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '本地模拟服务启动失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 弹窗添加一所学校（只填名称与域名，地址由域名推导）。
  Future<void> _addSchool() async {
    final name = TextEditingController();
    final domain = TextEditingController();
    final created = await showDialog<SchoolProfile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加学校'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassField(label: '学校名称', controller: name, autofocus: true),
            const SizedBox(height: 12),
            GlassField(label: '学校域名', controller: domain),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return;
              final p = SchoolProfile.fromDomain(domain.text);
              Navigator.pop(
                ctx,
                SchoolProfile(
                  name: n,
                  authBase: p.authBase,
                  jwxtBase: p.jwxtBase,
                  xgBase: p.xgBase,
                  ecardBase: p.ecardBase,
                ),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    name.dispose();
    domain.dispose();
    if (created == null) return;
    await AppState.I.upsertSchool(created);
    await AppState.I.setSchool(created);
    CampusDirect.I.forgetLoginState();
    if (!mounted) return;
    setState(() {
      _loadSchool(created);
      _probes = null;
    });
  }

  /// 删除当前学校档案（至少保留一个）。
  Future<void> _removeSchool() async {
    final name = AppState.I.school.name;
    if (AppState.I.schools.length <= 1) {
      setState(() => _error = '至少保留一个学校');
      return;
    }
    await AppState.I.removeSchool(name);
    CampusDirect.I.forgetLoginState();
    if (!mounted) return;
    setState(() {
      _loadSchool(AppState.I.school);
      _probes = null;
    });
  }

  /// 切换到另一所学校档案并刷新表单。
  Future<void> _pickSchool(SchoolProfile s) async {
    await AppState.I.setSchool(s);
    CampusDirect.I.forgetLoginState();
    if (!mounted) return;
    setState(() {
      _loadSchool(s);
      _probes = null;
    });
  }

  /// 保存当前模式的设置（服务器地址 / 学校档案 + 校园凭据）。
  Future<void> _save() async {
    final st = AppState.I;
    setState(() {
      _error = null;
      _ok = null;
    });
    if (_mode == AppMode.server) {
      await st.setServer(_server.text);
      await st.setMode(AppMode.server);
      st.statusInfo = null;
      st.studentInfo = null;
      if (mounted) {
        setState(() => _ok = '已保存：服务器模式 · ${st.serverUrl}');
      }
      return;
    }
    final school = _draftSchool();
    if (!school.isComplete) {
      setState(() => _error = '直连模式需要四个学校系统地址（教务 / 学工 / 统一认证 / 校园卡）');
      return;
    }
    final grade = _grade.text.trim();
    if (grade.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(grade)) {
      setState(() => _error = '年级请填 4 位入学年，如 2027');
      return;
    }
    final dormBuilding = _dormBuilding.text.trim();
    final dormRoom = _dormRoom.text.trim();
    if (dormBuilding.isEmpty != dormRoom.isEmpty) {
      setState(() => _error = '楼号和寝室号请一起填写（电费查询用，不用可都留空）');
      return;
    }
    await st.upsertSchool(school);
    await st.setSchool(school);
    st.creds
      ..studentId = _sid.text.trim()
      ..password = _pwd.text
      ..payPassword = _payPwd.text
      ..dorm = composeDorm(dormBuilding, dormRoom)
      ..realName = _realName.text.trim()
      ..grade = grade;
    await st.setMode(AppMode.direct);
    CampusDirect.I.forgetLoginState();
    await st.persistDirect();
    st.statusInfo = null;
    st.studentInfo = null;
    if (mounted) {
      setState(
        () => _ok = _pwd.text.isEmpty
            ? '已保存学校信息：还需填写统一身份认证密码才能查询校园数据'
            : '已保存：直连模式 · ${school.name}（首次查询会要求输入验证码）',
      );
    }
  }

  /// 悬浮切换器占的高度（列表顶部要让出这么多，内容才不会被它压住）。
  static const double _tabsRowHeight = 50;

  /// 悬浮玻璃胶囊里的模式切换器（外层玻璃面由 [FloatingTabsHeader] 提供）。
  Widget _tabsRow() => GlassTabs(
        flat: true,
        labels: const ['服务器模式', '直连模式'],
        index: _tabIndex,
        position: _tabPos,
        dragPosition: _tabDrag,
        onChanged: _setTab,
        height: 32,
        fontSize: 11.5,
      );

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    // 整页监听 AppState：顶栏样式开关改完要连 Scaffold 一起重建。
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已扣掉状态栏）。
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('连接设置')),
          body: GlassFadedBody(
            barHeight: topInset,
            // 模式切换器悬浮在顶栏下方：下划收起、上滑展开（同二课活动 / 分数页）。
            child: FloatingTabsHeader(
              topInset: topInset,
              header: _tabsRow(),
              dragPosition: _tabDrag,
              child: GestureDetector(
                // 页面区域横滑切模式；页面内部真接住横滑的组件（滑块自己）照旧优先。
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onTabDragStart,
                onHorizontalDragUpdate: _onTabDragUpdate,
                onHorizontalDragEnd: _onTabDragEnd,
                onHorizontalDragCancel: () => _tabDrag.value = null,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8 + topInset + _tabsRowHeight,
                    12,
                    24,
                  ),
                  children: [
                    // 下方两套设置跟着滑块一起左右滑动（与主界面切页同一套观感）。
                    _slidingSections(st),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: SemColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: SemColors.danger,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
                if (_ok != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SemColors.successSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: SemColors.success.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _ok!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: SemColors.success,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
                // 说明文案统一沉到页底。
                const PageNotes(
                  lines: [
                    '服务器模式：由服务器代连校园内网；登录用该服务器的账号密码，'
                        '校园凭据（学号 / 校园网密码）在该服务器的网站「我的 → 校园服务」配置一次。',
                    '直连模式：本机凭据直连学校系统，数据不经过任何服务器；需设备在校园网 / 校内 VPN 内。',
                    '校园凭据仅保存在本机，不会上传到任何服务器。',
                    '直连模式的「姓名」留空时查学工会自动补全（校园卡登录用）。',
                  ],
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
}

/// 裁掉屏外那套设置的横向溢出，但不碰纵向的投影。
///
/// [sliding] 为 false（已经停在某一格）时返回一个远大于视口的矩形 = 完全不裁：
/// 静止时两套设置没有横向溢出，还裁只会把 AppCard 柔和的 blur 24 外投影沿着
/// 卡片左右边缘竖直切断，卡片下方出现一条带硬直边的矩形暗带。
class _HorizontalClipper extends CustomClipper<Rect> {
  const _HorizontalClipper({required this.sliding});

  /// 是否正在跟随滑块滑动（两套设置同时在画，需要挡住溢出的那套）。
  final bool sliding;

  @override
  Rect getClip(Size size) => sliding
      ? Rect.fromLTWH(0, -2000, size.width, size.height + 4000)
      : Rect.fromLTWH(-4000, -2000, size.width + 8000, size.height + 4000);

  @override
  bool shouldReclip(_HorizontalClipper oldClipper) =>
      oldClipper.sliding != sliding;
}
