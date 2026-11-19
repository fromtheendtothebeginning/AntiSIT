import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';

/// `files` 权限与 accept 解析的验收：
/// * 市场拓展没声明 `files`，`files.pick/save` 在进平台通道前就被拒；
/// * accept 同时支持扩展名与 MIME，不传 = 任意文件；
/// * 权限文案与接口映射齐全（安装弹窗 / 权限页靠它展示）。
void main() {
  group('accept 解析', () {
    test('扩展名 / MIME / 逗号串都认', () {
      final groups = ExtFilesService.typeGroupsFromAccept(
          ['text/csv', '.json', 'IMAGE/*', 'md']);
      expect(groups, hasLength(1));
      expect(groups.single.extensions, containsAll(['json', 'md']));
      expect(groups.single.mimeTypes, containsAll(['text/csv', 'image/*']));
    });

    test('不传 / 空串 = 任意文件', () {
      expect(ExtFilesService.typeGroupsFromAccept(null), isEmpty);
      expect(ExtFilesService.typeGroupsFromAccept('  '), isEmpty);
      expect(ExtFilesService.typeGroupsFromAccept([]), isEmpty);
    });

    test('字符串里用逗号分隔也认', () {
      final groups = ExtFilesService.typeGroupsFromAccept('text/plain, .csv');
      expect(groups.single.extensions, ['csv']);
      expect(groups.single.mimeTypes, ['text/plain']);
    });
  });

  test('files 权限有中文说明，接口映射到 files', () {
    expect(kSensitivePermissions, contains('files'));
    expect(kPermissionLabels['files'], contains('系统文件选择器'));
    expect(kMethodPermissions['files.pick'], 'files');
    expect(kMethodPermissions['files.save'], 'files');
  });

  testWidgets('市场拓展没声明 files：接口直接拒，不打开选择器', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final bridge = ExtBridge(
      extId: 'e1',
      context: tester.element(find.byType(SizedBox)),
      item: const ExtensionItem(
        id: 'e1',
        name: '文件工具',
        url: 'https://example.com',
        fromMarket: true,
        permissions: ['storage'],
      ),
    );
    await expectLater(
      bridge.call('files.pick', {'accept': '.txt'}),
      throwsA(isA<ArgumentError>()
          .having((e) => e.message, 'message', contains('files'))),
    );
    await expectLater(
      bridge.call('files.save', {'name': 'a.txt', 'text': 'x'}),
      throwsA(isA<ArgumentError>()
          .having((e) => e.message, 'message', contains('files'))),
    );
  });
}
