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
}
