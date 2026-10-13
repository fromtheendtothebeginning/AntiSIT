import 'package:campus_service/pages/profile_page.dart';
import 'package:campus_service/update_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「更新检查」的验收：
/// * 版本比较 / Release 解析（不联网，纯函数）；
/// * 「我的 → 检查更新」：查到新版本弹引导（去下载 / 稍后），已是最新给提示，失败给原因；
/// * 点过「稍后」的版本记在本地，之后不再自动弹（手动检查照旧能看到）。
void main() {
  /// 一份 GitHub Release 的返回体（字段按真实接口裁到用得上的那些）。
  Map<String, dynamic> releaseJson(
    String tag, {
    String? body,
    bool withApk = true,
  }) =>
      {
        'tag_name': tag,
        'html_url': 'https://github.com/$updateRepo/releases/tag/$tag',
        'body': body ?? '## AntiSIT\n\n安装说明模板\n\n### 本次更新\n- 修了某个 bug\n- 加了更新检查\n',
        'assets': [
          if (withApk)
            {
              'name': 'AntiSIT-${tag.replaceFirst('v', '')}.apk',
              'browser_download_url':
                  'https://github.com/$updateRepo/releases/download/$tag/x.apk',
            },
          {
            'name': 'AntiSIT-${tag.replaceFirst('v', '')}.apk.sha256',
            'browser_download_url': 'https://example.com/x.sha256',
          },
        ],
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateChecker.I.reset();
    PackageInfo.setMockInitialValues(
      appName: 'AntiSIT',
      packageName: 'top.anticraft.campus',
      version: '1.13.5',
      buildNumber: '92',
      buildSignature: '',
    );
  });

  group('版本比较', () {
    /// (a, b, 期望)：>0 = a 更新，0 = 等价，<0 = a 更旧
    const cases = <(String, String, int)>[
      ('1.13.6', '1.13.5', 1),
      ('1.13.5', '1.13.5', 0),
      ('v1.13.5', '1.13.5', 0),
      ('1.13.5+92', '1.13.5', 0), // 构建号不参与：同版本号重发不提示
      ('1.8.15', '1.13.5', -1),
      ('1.10.0', '1.9.9', 1),
      ('1.13', '1.13.0', 0),
      ('1.14.0', '1.13.9', 1),
      ('1.13.5-rc1', '1.13.5', -1), // 预发布比正式版旧
    ];

    for (final (a, b, want) in cases) {
      test('$a vs $b = $want', () {
        expect(compareVersions(a, b).sign, want);
      });
    }
  });

  group('Release 解析', () {
    test('取版本号 / 变更清单 / APK 直链 / 页面地址', () {
      final info = parseRelease(releaseJson('v1.13.6'))!;
      expect(info.version, '1.13.6');
      expect(info.apkUrl, endsWith('/v1.13.6/x.apk'), reason: '挑 .apk 资产，不是 .sha256');
      expect(info.pageUrl, endsWith('/releases/tag/v1.13.6'));
      expect(info.notes, '· 修了某个 bug\n· 加了更新检查');
      expect(info.notes, isNot(contains('安装说明模板')), reason: '模板部分不带给用户看');
    });

    test('没挂 APK 资产时只有页面地址', () {
      final info = parseRelease(releaseJson('v1.13.6', withApk: false))!;
      expect(info.apkUrl, isNull);
      expect(info.pageUrl, isNotEmpty);
    });

    test('没有 tag_name（出错的返回体）返回 null', () {
      expect(parseRelease(const {'message': 'Not Found'}), isNull);
    });

    test('变更清单：去掉 markdown 记号与空行', () {
      expect(releaseSummary('### 本次更新\n\n- 甲\n\n* 乙\n#### 标题\n'),
          '· 甲\n· 乙\n标题');
      expect(releaseSummary('只有一段说明'), '只有一段说明');
      expect(releaseSummary(''), isEmpty);
    });
  });

  group('手动检查', () {
    /// 「我的」页足够高，设置卡里的条目都建得出来。
    Future<void> pumpProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
      await tester.pumpAndSettle();
    }

    testWidgets('平时显示当前版本', (tester) async {
      await pumpProfile(tester);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('当前 v1.13.5 (92)'), findsOneWidget);
    });

    testWidgets('查到新版本：弹引导，能「去下载」和「稍后」', (tester) async {
      UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.6');
      await pumpProfile(tester);

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 1.13.6'), findsOneWidget);
      expect(find.text('当前 v1.13.5 · 最新 v1.13.6'), findsOneWidget);
      expect(find.textContaining('修了某个 bug'), findsOneWidget);
      expect(find.text('去下载'), findsOneWidget);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 1.13.6'), findsNothing, reason: '弹窗关掉了');
      expect(UpdateChecker.I.skipped, '1.13.6');
      expect((await SharedPreferences.getInstance()).getString('update_skipped_version'),
          '1.13.6', reason: '下次启动不再弹这个版本');
      expect(find.text('发现新版本 v1.13.6'), findsOneWidget, reason: '条目上仍标着有新版本');
    });

    testWidgets('已是最新：不弹窗，给一句提示', (tester) async {
      UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.5');
      await pumpProfile(tester);

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.textContaining('发现新版本'), findsNothing);
    });

    testWidgets('检查失败：给出原因（GitHub 访问不了 / 限流都常见）', (tester) async {
      UpdateChecker.I.debugFetch = () async => throw Exception('boom');
      await pumpProfile(tester);

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.textContaining('检查更新失败：网络不可用'), findsOneWidget);
      expect(find.textContaining('检查失败：'), findsOneWidget, reason: '条目上也留着原因');
    });
  });

  test('点过「稍后」的版本不再自动弹，手动检查仍看得到', () async {
    UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.6');
    await UpdateChecker.I.load();
    await UpdateChecker.I.check();
    expect(UpdateChecker.I.shouldPrompt, isTrue);

    await UpdateChecker.I.skip();

    // 下次启动：清掉内存里的结论，重新 load + check —— 应该不再弹
    UpdateChecker.I.available = null;
    await UpdateChecker.I.load();
    await UpdateChecker.I.check();
    expect(UpdateChecker.I.shouldPrompt, isFalse);
    expect(UpdateChecker.I.available!.version, '1.13.6', reason: '结论还在，「我的」页照旧能看到');
  });
}
