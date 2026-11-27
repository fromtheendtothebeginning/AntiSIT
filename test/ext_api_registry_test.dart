import 'package:flutter_test/flutter_test.dart';

import 'package:plugin_ext/api_registry.dart';

/// 依赖插件的接口注册表：登记 / 查表 / 卸载清理 / 缺接口判定 / 版本门。
void main() {
  setUp(() => ExtApiRegistry.I = ExtApiRegistry());

  test('依赖插件登记接口，应用插件按名字取用', () {
    final reg = ExtApiRegistry.I;
    reg.register(const ExtApiEntry(extId: 'sit.core-lib', name: 'core.format', reference: 'core.format'));
    reg.register(const ExtApiEntry(extId: 'sit.core-lib', name: 'core.storage', reference: 'core.storage'));

    expect(reg.apisOf('sit.core-lib'), containsAll(['core.format', 'core.storage']));
    expect(reg.byName('core.format')?.extId, 'sit.core-lib');
    expect(reg.byName('不存在'), isNull);
  });

  test('更新依赖插件：同名接口换成新实现（后登记的覆盖）', () {
    final reg = ExtApiRegistry.I;
    reg.register(const ExtApiEntry(extId: 'lib-a', name: 'shared.api', reference: 'v1'));
    reg.register(const ExtApiEntry(extId: 'lib-a', name: 'shared.api', reference: 'v2'));
    expect(reg.byName('shared.api')?.reference, 'v2');
    expect(reg.entries, hasLength(1));
  });

  test('卸载依赖插件：它登记的接口一起消失（应用插件据此降级）', () {
    final reg = ExtApiRegistry.I;
    reg.register(const ExtApiEntry(extId: 'lib-a', name: 'a.api', reference: ''));
    reg.register(const ExtApiEntry(extId: 'lib-b', name: 'b.api', reference: ''));
    reg.unregisterOwner('lib-a');
    expect(reg.byName('a.api'), isNull);
    expect(reg.byName('b.api'), isNotNull);
  });

  test('空名字不登记（防脏数据把表搞乱）', () {
    final reg = ExtApiRegistry.I;
    reg.register(const ExtApiEntry(extId: 'x', name: '  ', reference: ''));
    expect(reg.entries, isEmpty);
  });

  test('缺接口判定：应用插件要求 3 个接口，只提供 2 个', () {
    final reg = ExtApiRegistry.I;
    reg.register(const ExtApiEntry(extId: 'lib', name: 'one', reference: ''));
    reg.register(const ExtApiEntry(extId: 'lib', name: 'two', reference: ''));
    expect(
      missingApisFor(required: ['one', 'two', 'three'], registry: reg),
      ['three'],
    );
    expect(missingApisFor(required: const [], registry: reg), isEmpty);
  });

  group('依赖版本门', () {
    test('没写版本要求：任何版本都满足', () {
      expect(satisfiesDependencyVersion(installedVersion: '0.1.0', required: ''), isTrue);
    });

    test('已装版本够 / 不够', () {
      expect(satisfiesDependencyVersion(installedVersion: '1.2.0', required: '1.2.0'), isTrue);
      expect(satisfiesDependencyVersion(installedVersion: '1.3.0', required: '1.2.0'), isTrue);
      expect(satisfiesDependencyVersion(installedVersion: '1.1.9', required: '1.2.0'), isFalse);
    });

    test('读不到已装版本：按不满足处理（宁可让用户更新）', () {
      expect(satisfiesDependencyVersion(installedVersion: '', required: '1.0.0'), isFalse);
    });
  });
}

