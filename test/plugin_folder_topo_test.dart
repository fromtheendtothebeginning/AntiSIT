import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

/// 插件文件夹的拓扑顺序：被依赖的文件夹排在前面（下载 / 展示顺序）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('按依赖拓扑排文件夹：依赖的排在后面', () async {
    SharedPreferences.setMockInitialValues({});
    await PluginFolderCatalog.I.load();
    final order = PluginFolderCatalog.I.topoOrder();
    final pos = {for (var i = 0; i < order.length; i++) order[i].package: i};

    // 真实依赖：plugin_course_cloud 依赖 timetable + fluid_cloud；plugin_reminder 依赖 timetable
    final cc = pos['plugin_course_cloud'];
    final tt = pos['plugin_timetable'];
    final fc = pos['plugin_fluid_cloud'];
    expect(cc, isNotNull);
    expect(tt, isNotNull);
    expect(fc, isNotNull);
    expect(cc!, greaterThan(tt!), reason: '依赖课程表的要排在课程表后面');
    expect(cc, greaterThan(fc!), reason: '也依赖流体云');

    final rm = pos['plugin_reminder'];
    expect(rm, isNotNull);
    expect(rm!, greaterThan(tt), reason: '上课提醒依赖课程表');
    expect(order.length, PluginFolderCatalog.I.folders.length, reason: '不能丢文件夹');
  });

  test('跨文件夹依赖按拓扑序给出下载顺序', () {
    const folders = [
      PluginFolderSpec(
        package: 'app',
        parts: [PluginPartSpec(id: 'app', kind: 'feature')],
        dependencies: ['lib'],
      ),
      PluginFolderSpec(
        package: 'lib',
        parts: [PluginPartSpec(id: 'lib', kind: 'feature')],
        dependencies: ['base'],
      ),
      PluginFolderSpec(
        package: 'base',
        parts: [PluginPartSpec(id: 'base', kind: 'feature')],
      ),
    ];
    expect(
      PluginFolderCatalog.topoOrderFrom(folders).map((f) => f.package),
      ['base', 'lib', 'app'],
    );
  });
}
