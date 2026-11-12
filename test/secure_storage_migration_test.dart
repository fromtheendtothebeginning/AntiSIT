import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ai/plugin_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 旧版本把 AI Key / 直连 Cookie 明文写在 SharedPreferences 里；现在统一迁到
/// SecureStore。这里验证「读得到旧值 + 明文被删掉」，避免升级后用户重新填 Key。
void main() {
  setUp(() {
    SecureStore.I = MemorySecureStore();
    SharedPreferences.setMockInitialValues({});
  });

  test('AI 配置从明文 prefs 迁入 SecureStore，并删除明文', () async {
    final legacy = AiConfig(
      enabled: true,
      providerId: 'deepseek',
      model: 'deepseek-flash',
      keys: {'deepseek': 'sk-legacy'},
    );
    SharedPreferences.setMockInitialValues({'ai_config': AiConfig.encode(legacy)});

    final loaded = await AiVision.I.load();

    expect(loaded.apiKey, 'sk-legacy');
    expect(await SecureStore.I.read('ai_config'), contains('sk-legacy'));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('ai_config'), isNull, reason: '明文 Key 不能留在 prefs 里');
  });

  test('直连 Cookie 从明文 prefs 迁入 SecureStore，并删除明文', () async {
    const key = 'direct_cookies_migration_test';
    final jar = jsonEncode({
      'jwxt.sit.edu.cn': {'JSESSIONID': 'secret-session'},
    });
    SharedPreferences.setMockInitialValues({key: jar});

    final session = HttpSession(trustHosts: const ['jwxt.sit.edu.cn'], persistKey: key);
    await session.load();

    expect(await SecureStore.I.read(key), jar);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(key), isNull, reason: '明文会话 Cookie 不能留在 prefs 里');
  });
}
