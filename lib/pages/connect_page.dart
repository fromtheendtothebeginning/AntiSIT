import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../direct/campus_direct.dart';
import '../direct/mock_campus_server.dart';
import '../direct/school.dart';
import '../widgets/common.dart';
import 'login_page.dart';

const String _antisitRepo = 'https://github.com/fromtheendtothebeginning/AntiSIT';
const String _anticraftRepo = 'https://github.com/fromtheendtothebeginning/anticraft';

/// 连接设置：项目用同一套接口，两种接入方式——
/// 1) 服务器模式：填任意服务器地址（IP / 域名[:端口]）+ 该服务器的 anticraft 账号密码，由服务器代连校园内网；
/// 2) 直连模式：填学校系统信息 + 校园凭据，App 直接用凭据访问学校系统（不走服务器，需校园网 / 校内 VPN）。
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late AppMode _mode = AppState.I.mode;

  final _server = TextEditingController();
  bool _serverTesting = false;
  String? _serverProbe;

  final _schoolName = TextEditingController();
  final _authBase = TextEditingController();
  final _jwxtBase = TextEditingController();
  final _xgBase = TextEditingController();
  final _ecardBase = TextEditingController();
  final _aesKey = TextEditingController();

  final _sid = TextEditingController();
  final _pwd = TextEditingController();
  final _payPwd = TextEditingController();
  final _dorm = TextEditingController();
  final _realName = TextEditingController();

  bool _hidePwd = true;
  bool _testing = false;
  List<ProbeResult>? _probes;
  String? _error;
  String? _ok;

  @override
  void initState() {
    super.initState();
    final st = AppState.I;
    _server.text = st.serverUrl;
    _loadSchool(st.school);
    _sid.text = st.creds.studentId;
    _pwd.text = st.creds.password;
    _payPwd.text = st.creds.payPassword;
    _dorm.text = st.creds.dorm;
    _realName.text = st.creds.realName;
  }

  void _loadSchool(SchoolProfile s) {
    _schoolName.text = s.name;
    _authBase.text = s.authBase;
    _jwxtBase.text = s.jwxtBase;
    _xgBase.text = s.xgBase;
    _ecardBase.text = s.ecardBase;
    _aesKey.text = s.dektAesKey;
  }

  SchoolProfile _draftSchool() => SchoolProfile(
        name: _schoolName.text.trim(),
        authBase: _authBase.text.trim(),
        jwxtBase: _jwxtBase.text.trim(),
        xgBase: _xgBase.text.trim(),
        ecardBase: _ecardBase.text.trim(),
        dektAesKey: _aesKey.text.trim(),
      );

  @override
  void dispose() {
    for (final c in [
      _server, _schoolName, _authBase, _jwxtBase, _xgBase, _ecardBase, _aesKey,
      _sid, _pwd, _payPwd, _dorm, _realName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ==================== 服务器模式 ====================

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
    try {
      // 空体登录请求：401/422 都说明该地址上跑着同一套开放接口
      final resp = await http
          .post(Uri.parse('$url/api/login'),
              headers: {'Content-Type': 'application/json'}, body: '{}')
          .timeout(const Duration(seconds: 15));
      final ok = [400, 401, 422].contains(resp.statusCode);
      if (mounted) {
        setState(() => _serverProbe = ok
            ? '连接成功：$url（HTTP ${resp.statusCode}，接口可用）'
            : '该地址返回 HTTP ${resp.statusCode}，可能不是同款开放接口服务');
      }
    } catch (e) {
      if (mounted) setState(() => _serverProbe = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _serverTesting = false);
    }
  }

  // ==================== 直连模式 ====================

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
      // 探测用草稿地址，结束恢复原学校；真正切换交给「保存」
      await AppState.I.setSchool(original);
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 调试：一键切到本机模拟校园服务（四个系统都在 127.0.0.1，凭据用模拟值）。
  /// 直连模式没有校园网时，靠它把验证码 / 会话 / 各系统查询链路真正跑起来。
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
        ..realName = MockCampusServer.realName;
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
        _dorm.text = MockCampusServer.dorm;
        _realName.text = MockCampusServer.realName;
        _ok = '已切换到本地模拟服务（${MockCampusServer.instance.baseUrl}）：'
            '教务 / 统一认证 / 学工 / 校付宝都在本机模拟。返回首页查询会弹出验证码，'
            '图片上的数字就是答案（日志里也会打印）。';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '本地模拟服务启动失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

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
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '学校名称', hintText: '如 某某大学'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: domain,
              decoration: const InputDecoration(
                labelText: '学校域名（可留空）',
                hintText: '如 sit.edu.cn',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '填域名会按「子系统.学校域名」自动推导四个系统地址'
              '（authserver. / jwxt. / xg. / ecard.），保存后可逐项改成学校实际地址。',
              style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return;
              final p = SchoolProfile.fromDomain(domain.text);
              Navigator.pop(ctx, SchoolProfile(
                name: n,
                authBase: p.authBase,
                jwxtBase: p.jwxtBase,
                xgBase: p.xgBase,
                ecardBase: p.ecardBase,
              ));
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

  // ==================== 保存 ====================

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
      setState(() => _error = '直连模式需要四个学校系统地址（教务 / 学工 / 统一认证 / 校付宝）');
      return;
    }
    await st.upsertSchool(school);
    await st.setSchool(school);
    st.creds
      ..studentId = _sid.text.trim()
      ..password = _pwd.text
      ..payPassword = _payPwd.text
      ..dorm = _dorm.text.trim()
      ..realName = _realName.text.trim();
    await st.setMode(AppMode.direct);
    CampusDirect.I.forgetLoginState();
    await st.persistDirect();
    st.statusInfo = null;
    st.studentInfo = null;
    if (mounted) {
      setState(() => _ok = _pwd.text.isEmpty
          ? '已保存学校信息：还需填写统一身份认证密码才能查询校园数据'
          : '已保存：直连模式 · ${school.name}（首次查询会要求输入验证码）');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Scaffold(
      appBar: AppBar(title: const Text('连接设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('数据来源', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                SegmentedButton<AppMode>(
                  segments: const [
                    ButtonSegment(
                        value: AppMode.server, label: Text('服务器模式'), icon: Icon(Icons.cloud_outlined)),
                    ButtonSegment(
                        value: AppMode.direct, label: Text('直连模式'), icon: Icon(Icons.lan_outlined)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() {
                    _mode = v.first;
                    _probes = null;
                    _error = null;
                    _ok = null;
                  }),
                ),
                const SizedBox(height: 10),
                Text(
                  _mode == AppMode.server
                      ? '服务器代连校园内网：填任意服务器地址（IP 或域名，可带端口）+ 该服务器的账号密码即可使用，同一套开放接口。'
                      : '本机直连学校系统：填学校系统地址 + 校园凭据，数据不经过任何服务器，需要设备在校园网 / 校内 VPN 内。',
                  style: const TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_mode == AppMode.server) ..._serverSection(st) else ..._directSection(st),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SemColors.dangerSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
              ),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12.5, color: SemColors.danger, height: 1.6)),
            ),
          ],
          if (_ok != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SemColors.successSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SemColors.success.withValues(alpha: 0.35)),
              ),
              child: Text(_ok!,
                  style: const TextStyle(fontSize: 12.5, color: SemColors.success, height: 1.6)),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 服务器模式 UI ====================

  List<Widget> _serverSection(AppState st) => [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('服务器地址', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'IP 或域名（可带端口）',
                  hintText: '192.168.1.10:8000 / my.server.cn:8443',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '登录时用该服务器上的账号密码；校园凭据（学号 / 校园网密码）在该服务器的网站「我的 → 校园服务」配置一次。',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _serverTesting ? null : _probeServer,
                    child: _serverTesting
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('测试连接'),
                  ),
                  OutlinedButton(
                    onPressed: () => _server.clear(),
                    child: const Text('清空'),
                  ),
                  if (kDebugMode)
                    OutlinedButton(
                      onPressed: () {
                        _server.text = AppState.localUrl;
                      },
                      child: const Text('本地调试'),
                    ),
                ],
              ),
              if (_serverProbe != null) ...[
                const SizedBox(height: 8),
                Text(_serverProbe!,
                    style: const TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await _save();
                        if (!mounted) return;
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage()));
                      },
                      child: const Text('保存并登录'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Row(
            children: [
              Icon(
                st.demo
                    ? Icons.science_outlined
                    : (st.token != null ? Icons.check_circle : Icons.info_outline),
                color: st.demo
                    ? SemColors.accent
                    : (st.token != null ? SemColors.success : SemColors.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  st.demo
                      ? '当前为演示模式（本地假数据，不发起请求）'
                      : (st.token != null
                          ? '已登录：${st.username ?? ''} @ ${st.serverUrl.isEmpty ? '未填写地址' : st.serverUrl}'
                          : '该服务器未登录：登录后即可查询校园数据'),
                  style: const TextStyle(fontSize: 12.5, color: SemColors.textSecondary, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _selfHostCard(),
      ];

  // ==================== 直连模式 UI ====================

  List<Widget> _directSection(AppState st) => [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SemColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SemColors.warning.withValues(alpha: 0.35)),
          ),
          child: const Text(
            '直连模式不走服务器：请先连接校园网或校内 VPN（校园内网）。校外且没有校内 VPN 时，'
            '请改用服务器模式，或让学校提供可访问的服务器地址。',
            style: TextStyle(fontSize: 12.5, color: SemColors.warning, height: 1.7),
          ),
        ),
        const SizedBox(height: 10),
        if (kDebugMode) ...[_mockCard(), const SizedBox(height: 10)],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('学校信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addSchool,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加', style: TextStyle(fontSize: 13)),
                  ),
                  if (st.schools.length > 1)
                    TextButton.icon(
                      onPressed: _removeSchool,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除', style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: st.school.name,
                decoration: const InputDecoration(labelText: '当前学校', isDense: true),
                items: [
                  for (final s in st.schools)
                    DropdownMenuItem(value: s.name, child: Text(s.name)),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  final s = st.schools.firstWhere((e) => e.name == v);
                  await st.setSchool(s);
                  CampusDirect.I.forgetLoginState();
                  if (!mounted) return;
                  setState(() {
                    _loadSchool(s);
                    _probes = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schoolName,
                decoration: const InputDecoration(labelText: '学校名称', isDense: true),
              ),
              const SizedBox(height: 10),
              _addrField(_jwxtBase, '教务系统', 'https://jwxt.example.edu.cn'),
              const SizedBox(height: 10),
              _addrField(_xgBase, '学工系统（第二课堂）', 'https://xg.example.edu.cn'),
              const SizedBox(height: 10),
              _addrField(_authBase, '统一身份认证', 'https://authserver.example.edu.cn/authserver'),
              const SizedBox(height: 10),
              _addrField(_ecardBase, '校付宝（校园码 / 电费）', 'https://ecard.example.edu.cn'),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('高级', style: TextStyle(fontSize: 13.5)),
                children: [
                  TextField(
                    controller: _aesKey,
                    decoration: const InputDecoration(
                      labelText: '响应解密密钥（留空即可）',
                      helperText: '个别学校接口返回 isEncrypt 加密数据时需要，向学校系统维护方索取',
                      helperMaxLines: 2,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('校园凭据', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              const Text('仅保存在本机，用于直连学校系统；不会上传到任何服务器。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
              const SizedBox(height: 12),
              TextField(
                controller: _sid,
                decoration: const InputDecoration(
                    labelText: '学号', prefixIcon: Icon(Icons.badge_outlined), isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pwd,
                obscureText: _hidePwd,
                decoration: InputDecoration(
                  labelText: '统一身份认证密码（= 校园网 / VPN 密码）',
                  prefixIcon: const Icon(Icons.lock_outline),
                  isDense: true,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _hidePwd = !_hidePwd),
                    icon: Icon(
                        _hidePwd ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _payPwd,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '校付宝支付密码（校园码 / 电费）',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dorm,
                decoration: const InputDecoration(
                  labelText: '寝室号（电费查询 / 充值）',
                  hintText: '如 24号楼1016',
                  prefixIcon: Icon(Icons.house_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _realName,
                decoration: const InputDecoration(
                  labelText: '姓名（可留空，校付宝登录用；查学工会自动补全）',
                  prefixIcon: Icon(Icons.person_outline),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testing ? null : _testDirect,
                      child: _testing
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('测试连接'),
                    ),
                  ),
                ],
              ),
              if (_probes != null) ...[
                const SizedBox(height: 10),
                for (final p in _probes!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(p.ok ? Icons.check_circle : Icons.error_outline,
                            size: 16, color: p.ok ? SemColors.success : SemColors.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${p.name}：${p.detail}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: p.ok ? SemColors.textSecondary : SemColors.danger,
                                  height: 1.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ];

  Widget _addrField(TextEditingController c, String label, String hint) => TextField(
        controller: c,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      );

  // ==================== 本地模拟服务（仅 debug） ====================

  /// 没有校园网（模拟器 / 教室外）时用它在 App 进程内跑一套行为一致的学校系统，
  /// 用来验证直连链路：验证码弹窗、会话 Cookie、登录失败重试、各系统查询。
  Widget _mockCard() {
    final mock = MockCampusServer.instance;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: SemColors.accent),
              SizedBox(width: 6),
              Text('本地模拟服务（仅调试构建）',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '在 App 内监听 127.0.0.1 起一套与学校系统行为一致的模拟服务：'
            '正方教务（RSA 加密 + 图形验证码）、统一认证 CAS（AES 加密 + 图形验证码）、'
            '学工二课、校付宝（SM4 支付密码）。没有校园网也能把直连链路跑通。',
            style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.7),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _useMock,
                  child: Text(mock.running ? '重启并切到本地模拟服务' : '使用本地模拟服务'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mock.running
                ? '运行中：${mock.baseUrl}（模拟凭据 学号 ${MockCampusServer.studentId} / '
                    '密码 ${MockCampusServer.password} / 支付密码 ${MockCampusServer.payPassword}）'
                : '模拟凭据：学号 ${MockCampusServer.studentId} / 密码 ${MockCampusServer.password} / '
                    '支付密码 ${MockCampusServer.payPassword} / 寝室 ${MockCampusServer.dorm}',
            style: const TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ==================== 自建服务器指引 ====================

  /// 打开仓库链接；打不开（无浏览器/网络受限）时复制到剪贴板兜底。
  Future<void> _openRepo(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已复制链接：$url'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Widget _repoLink(String label, String url) => InkWell(
        onTap: () => _openRepo(url),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 15, color: SemColors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12.5, color: SemColors.accent, height: 1.5)),
              ),
            ],
          ),
        ),
      );

  /// 服务器模式下的自建指引：本项目（API 文档）与现成开源服务端（GPL-3.0）。
  Widget _selfHostCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('自建服务器', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            '上面填的地址可以是任何实现了同一套开放接口的服务器，两种方式：',
            style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary, height: 1.7),
          ),
          const SizedBox(height: 4),
          const Text(
            '① 参照 API 文档自行实现：本项目仓库内 docs/campus-api.md 是完整接口规约，'
                '照此用任意语言 / 框架重建服务端即可接入本 App。',
            style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary, height: 1.7),
          ),
          _repoLink('github.com/fromtheendtothebeginning/AntiSIT（含 API 文档）', _antisitRepo),
          const SizedBox(height: 8),
          const Text(
            '② 直接部署现成服务端：anticraft 校园服务网站就是这套接口的参考实现，同样开源，'
                '部署好把地址填到上方即可。',
            style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary, height: 1.7),
          ),
          _repoLink('github.com/fromtheendtothebeginning/anticraft（GPL-3.0）', _anticraftRepo),
          const SizedBox(height: 6),
          const Text(
            '两个项目均为 GPL-3.0 开源。协议要点：可自由使用、学习、修改与再分发；'
                '再分发或衍生作品必须同样以 GPL-3.0 开源并提供完整源码；软件不含任何担保。',
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}
