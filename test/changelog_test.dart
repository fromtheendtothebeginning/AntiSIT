import 'package:campus_service/changelog.dart';
import 'package:campus_service/update_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新日志：版本筛选（升级 / 跨多版本 / 降级 / 首装）与「升级后首次打开弹一次」。
void main() {
  group('changelogEntriesSince', () {
    test('升一个版本：只有新版本的条目', () {
      expect(changelogEntriesSince('1.17.0', '1.18.0').map((e) => e.version), ['1.18.0']);
    });

    test('跨多个版本：从新到旧列出', () {
      expect(
        changelogEntriesSince('1.15.0', '1.17.0').map((e) => e.version),
        ['1.17.0', '1.16.1'],
      );
    });

    test('首装 / 版本未变 / 降级安装：都不弹', () {
      expect(changelogEntriesSince(null, '1.18.0'), isEmpty);
      expect(changelogEntriesSince('1.18.0', '1.18.0'), isEmpty);
      expect(changelogEntriesSince('1.18.0', '1.17.0'), isEmpty);
    });

    test('日志数据：版本号从新到旧严格递减（表头加条目时别把顺序写反）', () {
      for (var i = 1; i < appChangelog.length; i++) {
        expect(
          compareVersions(appChangelog[i - 1].version, appChangelog[i].version),
          greaterThan(0),
          reason: '${appChangelog[i - 1].version} 应比 ${appChangelog[i].version} 新',
        );
      }
    });
  });

  group('showChangelogIfUpdated', () {
    testWidgets('升级后第一次打开弹一次，第二次不再弹', (tester) async {
      SharedPreferences.setMockInitialValues({kChangelogSeenVersion: '1.16.1'});
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) => TextButton(
                onPressed: () async {
                  results.add(await showChangelogIfUpdated(ctx, '1.18.0'));
                },
                child: const Text('go'),
              )),
        ),
      ));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsOneWidget);
      // 弹的是 1.17.0 与 1.18.0；已见过的 1.16.1 不该再出现
      expect(find.textContaining('1.18.0 ·'), findsOneWidget);
      expect(find.textContaining('1.17.0 ·'), findsOneWidget);
      expect(find.textContaining('1.16.1'), findsNothing);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(results, [true]);

      // 版本已记下：再触发不弹
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsNothing);
      expect(results, [true, false]);
    });

    testWidgets('首次安装：不弹，只记下当前版本', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) => TextButton(
                onPressed: () async {
                  results.add(await showChangelogIfUpdated(ctx, '1.18.0'));
                },
                child: const Text('go'),
              )),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsNothing);
      expect(results, [false]);
      expect((await SharedPreferences.getInstance()).getString(kChangelogSeenVersion), '1.18.0');
    });
  });
}
