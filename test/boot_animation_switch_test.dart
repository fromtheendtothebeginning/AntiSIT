import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/boot_page.dart';

/// 启动动画开关：关掉后启动页不久等（也不播 logo），开关本身要能落盘。
void main() {
  test('最少停留时长：开动画等装配播完，关了只留一帧过渡', () {
    expect(bootMinShowFor(true), bootMinShow);
    expect(bootMinShowFor(false), bootMinShowWhenOff);
    expect(bootMinShowWhenOff, lessThan(const Duration(milliseconds: 300)));
  });

  test('设置项落盘：关掉后读回来还是关的', () async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    expect(AppState.I.bootAnimation, isTrue, reason: '默认开着');
    await AppState.I.setBootAnimation(false);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('boot_animation'), isFalse);
    await AppState.I.setBootAnimation(true);
    expect(sp.getBool('boot_animation'), isTrue);
  });
}
