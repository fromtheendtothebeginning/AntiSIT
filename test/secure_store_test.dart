import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

void main() {
  late MemorySecureStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = MemorySecureStore();
    SecureStore.I = store;
    // 单例回到干净状态：清掉上一个测试留下的登录态
    final st = AppState.I;
    st.token = null;
    st.username = null;
    st.password = null;
    st.remember = true;
    st.creds = CampusCreds();
  });

  tearDown(() => SecureStore.I = MemorySecureStore());

  test('旧明文 SharedPreferences 里的凭据一次性迁入加密存储并删除明文', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.token': 'old-jwt',
      'flutter.username': '20230001',
      'flutter.password': 'p@ss',
      'flutter.direct_creds': '{"studentId":"20230001","password":"xg-pw","payPassword":"pay-pw"}',
      'flutter.remember': true,
    });
    await AppState.I.load();
    expect(AppState.I.token, 'old-jwt');
    expect(AppState.I.username, '20230001');
    expect(AppState.I.password, 'p@ss');
    expect(AppState.I.creds.password, 'xg-pw');
    expect(AppState.I.creds.payPassword, 'pay-pw');

    final sp = await SharedPreferences.getInstance();
    expect(sp.containsKey('token'), isFalse, reason: '明文 token 应被删除');
    expect(sp.containsKey('username'), isFalse);
    expect(sp.containsKey('password'), isFalse);
    expect(sp.containsKey('direct_creds'), isFalse);

    expect(store.mem['token'], 'old-jwt');
    expect(store.mem['direct_creds'], contains('pay-pw'));
  });

  test('加密存储已有值时优先于明文（明文是残留也不采用）', () async {
    store.mem['token'] = 'new-jwt';
    SharedPreferences.setMockInitialValues({'flutter.token': 'stale-jwt'});
    await AppState.I.load();
    expect(AppState.I.token, 'new-jwt');
  });

  test('登录后凭据只落加密存储，明文 SharedPreferences 不再出现', () async {
    await AppState.I.load();
    await AppState.I.saveLogin(token: 'jwt-1', username: 'u1', password: 'pw1');
    final sp = await SharedPreferences.getInstance();
    expect(sp.containsKey('token'), isFalse);
    expect(sp.containsKey('password'), isFalse);
    expect(store.mem['token'], 'jwt-1');
    expect(store.mem['password'], 'pw1');
  });

  test('remember=false 不持久化账号密码', () async {
    await AppState.I.load();
    await AppState.I.setRemember(false);
    await AppState.I.saveLogin(token: 'jwt-2', username: 'u2', password: 'pw2');
    expect(store.mem.containsKey('username'), isFalse);
    expect(store.mem.containsKey('password'), isFalse);
    expect(store.mem['token'], 'jwt-2');
  });

  test('清除直连会话后支付密码不在加密存储里', () async {
    store.mem['direct_creds'] = '{"studentId":"1","password":"x","payPassword":"pay"}';
    await AppState.I.load();
    await AppState.I.clearDirectSession();
    expect(store.mem['direct_creds'], isNot(contains('payPassword":"pay"')));
  });

  group('主动退出登录不该被自动重登救回来', () {
    test('服务器模式：退出后密码与「记住密码」一起清掉', () async {
      await AppState.I.load();
      await AppState.I.setRemember(true);
      await AppState.I.saveLogin(token: 'jwt', username: '20230001', password: 'pw');
      expect(AppState.I.hasCreds, isTrue);

      await AppState.I.clearSession(keepCreds: false, manual: true);

      expect(AppState.I.token, isNull);
      expect(AppState.I.remember, isFalse, reason: '自动重登开关要一起关掉');
      expect(AppState.I.password, isNull, reason: '旧密码不能留着给自动重登用');
      expect(AppState.I.hasCreds, isFalse);
      // 学号保留，重新登录时不用重打
      expect(AppState.I.username, '20230001');
      expect(store.mem.containsKey('password'), isFalse, reason: '加密存储里也不能留密码');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('remember'), isFalse, reason: '「记住密码」落盘为关');
    });

    test('直连模式：退出后校园密码清掉、自动重登关掉，学号保留', () async {
      await AppState.I.load();
      await AppState.I.setRemember(true);
      AppState.I.creds
        ..studentId = '20230001'
        ..password = 'campus-pw'
        ..payPassword = 'pay-pw'
        ..dorm = '24号楼1016';
      await AppState.I.persistDirect();

      await AppState.I.clearDirectSession(manual: true);

      expect(AppState.I.creds.hasLogin, isFalse, reason: '密码清掉后不再是登录态');
      expect(AppState.I.remember, isFalse);
      expect(AppState.I.creds.studentId, '20230001', reason: '学号保留');
      expect(AppState.I.creds.dorm, '24号楼1016', reason: '寝室保留');
      expect(store.mem['direct_creds'], isNot(contains('campus-pw')));
    });

    test('非主动退出（掉线 / 换模式）仍保留密码', () async {
      await AppState.I.load();
      await AppState.I.setRemember(true);
      await AppState.I.saveLogin(token: 'jwt', username: 'u', password: 'pw');

      await AppState.I.clearSession();

      expect(AppState.I.remember, isTrue, reason: '非主动退出不动自动重登开关');
      expect(AppState.I.password, 'pw', reason: '密码继续留在内存与加密存储里');
    });
  });
}
