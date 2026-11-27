import 'package:campus_service/pages/profile_page.dart';
import 'package:campus_service/update_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新检查：版本比较 / Release 解析（纯函数）、检查更新的四种结果、点过「稍后」之后不再自动弹。
void main() {
  /// 一份 GitHub Release 的返回体（字段按真实接口裁到用得上的那些）。
  Map<String, dynamic> releaseJson(
    String tag, {
    String? body,
    bool withApk = true,
  }) => {
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
        'browser_download_url': 'https://gitee.com/ender123/AntiSIT/x.sha256',
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
      // 预发布段不能按字典序比：rc10 应当比 rc2 新、alpha 比 beta 旧
      ('1.14.0-rc10', '1.14.0-rc2', 1),
      ('1.14.0-rc2', '1.14.0-rc2.1', -1),
      ('1.14.0-alpha', '1.14.0-beta', -1),
      ('1.14.0-rc1', '1.14.0-rc1.1', -1),
      // tag 前缀：稳定版 v，内测版 dev-（两种都要剥掉才比得了）
      ('dev-1.48.1-dev.1', '1.47.4', 1),
      ('dev-1.48.1-dev.1', '1.48.1', -1),
      ('dev-1.48.1-dev.2', 'dev-1.48.1-dev.1', 1),
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
      expect(
        info.apkUrl,
        endsWith('/v1.13.6/x.apk'),
        reason: '挑 .apk 资产，不是 .sha256',
      );
      expect(
        info.sha256Url,
        'https://gitee.com/ender123/AntiSIT/x.sha256',
        reason: '应用内下载完要对哈希',
      );
      expect(info.canSelfInstall, isTrue);
      expect(info.pageUrl, endsWith('/releases/tag/v1.13.6'));
      expect(info.notes, '· 修了某个 bug\n· 加了更新检查');
      expect(info.notes, isNot(contains('安装说明模板')), reason: '模板部分不带给用户看');
    });

    test('Gitee 返回体没有 html_url（实测为 null）：发布页回落到 Gitee，不带用户去 GitHub', () {
      final info = parseRelease(const {
        'tag_name': 'v1.26.0',
        'assets': [
          {
            'name': 'AntiSIT-1.26.0.apk',
            'browser_download_url':
                'https://gitee.com/ender123/AntiSIT/releases/download/v1.26.0/a.apk',
          },
          {
            'name': 'AntiSIT-1.26.0.apk.sha256',
            'browser_download_url':
                'https://gitee.com/ender123/AntiSIT/releases/download/v1.26.0/a.apk.sha256',
          },
        ],
      })!;
      expect(info.pageUrl, startsWith('https://gitee.com/'), reason: '国内用户打得开');
      expect(info.pageUrl, isNot(contains('github.com')));
      expect(info.apkUrl, endsWith('/a.apk'));
      expect(info.sha256Url, endsWith('/a.apk.sha256'));
    });

    test('没挂 APK 资产时只有页面地址', () {
      final info = parseRelease(releaseJson('v1.13.6', withApk: false))!;
      expect(info.apkUrl, isNull);
      expect(info.canSelfInstall, isFalse);
      expect(info.pageUrl, isNotEmpty);
    });

    test('只接受发布域白名单内的 https 资产链接', () {
      final info = parseRelease(const {
        'tag_name': 'v1.30.0',
        'assets': [
          {
            'name': 'a.apk',
            'browser_download_url': 'http://gitee.com/x/a.apk', // 明文
          },
          {
            'name': 'a.apk.sha256',
            'browser_download_url': 'https://evil.example/x.sha256', // 非发布域
          },
          {
            'name': 'b.apk',
            'browser_download_url':
                'https://objects.githubusercontent.com/x/b.apk',
          },
          {
            'name': 'b.apk.sha256',
            'browser_download_url': 'https://anticraft.top/apk/b.apk.sha256',
          },
        ],
      })!;
      expect(
        info.apkUrl,
        'https://objects.githubusercontent.com/x/b.apk',
        reason: '明文 / 非白名单地址被丢弃，CDN 主机放行',
      );
      expect(info.sha256Url, 'https://anticraft.top/apk/b.apk.sha256');
      expect(info.canSelfInstall, isTrue);
    });

    test('缺 sha256 时不允许应用内安装', () {
      final info = parseRelease(const {
        'tag_name': 'v1.30.0',
        'assets': [
          {
            'name': 'AntiSIT-1.30.0.apk',
            'browser_download_url': 'https://gitee.com/x/a.apk',
          },
        ],
      })!;
      expect(info.apkUrl, isNotNull);
      expect(info.sha256Url, isNull);
      expect(info.canSelfInstall, isFalse);
    });

    test('更新地址白名单：https + 发布域', () {
      expect(isAllowedUpdateUrl(Uri.parse('https://gitee.com/a.apk')), isTrue);
      expect(
        isAllowedUpdateUrl(Uri.parse('https://api.github.com/a.apk')),
        isTrue,
      );
      expect(
        isAllowedUpdateUrl(Uri.parse('https://anticraft.top/apk/a.apk')),
        isTrue,
      );
      expect(isAllowedUpdateUrl(Uri.parse('http://gitee.com/a.apk')), isFalse);
      expect(isAllowedUpdateUrl(Uri.parse('https://evil.com/a.apk')), isFalse);
      expect(
        isAllowedUpdateUrl(Uri.parse('https://gitee.com.evil.com/a.apk')),
        isFalse,
      );
    });

    test('没有 tag_name（出错的返回体）返回 null', () {
      expect(parseRelease(const {'message': 'Not Found'}), isNull);
    });

    test('变更清单：去掉 markdown 记号与空行', () {
      expect(
        releaseSummary('### 本次更新\n\n- 甲\n\n* 乙\n#### 标题\n'),
        '· 甲\n· 乙\n标题',
      );
      expect(releaseSummary('只有一段说明'), '只有一段说明');
      expect(releaseSummary(''), isEmpty);
    });
  });

  group('双渠道指向同一版本', () {
    test('只发了稳定版：内测版退回同一份（应用内两个渠道都能看到这个版本）', () {
      final picked = selectByChannel([releaseJson('v1.48.0')]);
      expect(picked.stable!.version, '1.48.0');
      expect(picked.dev!.version, '1.48.0', reason: '没发 dev 包时不让内测版用户干等');
      expect(picked.devShared, isTrue);
    });

    test('有带预发布段的版本：内测版用它，不再借稳定版', () {
      final picked = selectByChannel([
        releaseJson('v1.48.0'),
        releaseJson('v1.48.0-dev.2'),
      ]);
      expect(picked.stable!.version, '1.48.0');
      expect(picked.dev!.version, '1.48.0-dev.2');
      expect(picked.devShared, isFalse);
    });
  });

  group('检查更新二级页', () {
    /// 「我的」页足够高，设置卡里的条目都建得出来。
    Future<void> pumpProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
      await tester.pumpAndSettle();
    }

    /// 从「我的」页点进二级页并等它检查完。
    Future<void> openCenter(WidgetTester tester) async {
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
    }

    testWidgets('平时显示当前版本与渠道', (tester) async {
      await pumpProfile(tester);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('v1.13.5 (92) · 稳定版'), findsOneWidget);
    });

    testWidgets('查到新版本：弹引导，能「去下载」和「稍后」', (tester) async {
      UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.6');
      await pumpProfile(tester);
      await openCenter(tester);

      expect(find.text('发现新版本 1.13.6'), findsOneWidget);
      expect(find.text('当前 v1.13.5 · 最新 v1.13.6'), findsOneWidget);
      expect(find.textContaining('修了某个 bug'), findsOneWidget);
      expect(find.text('去下载'), findsOneWidget);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 1.13.6'), findsNothing, reason: '弹窗关掉了');
      expect(UpdateChecker.I.skipped, '1.13.6');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'update_skipped_stable',
        ),
        '1.13.6',
        reason: '下次启动不再弹这个版本',
      );
      expect(find.text('有新版本 v1.13.6'), findsOneWidget, reason: '二级页上仍标着有新版本');
    });

    testWidgets('已是最新：不弹窗，二级页显示「已是最新」', (tester) async {
      UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.5');
      await pumpProfile(tester);
      await openCenter(tester);

      expect(find.text('已是最新'), findsOneWidget);
      expect(find.textContaining('发现新版本'), findsNothing);
    });

    testWidgets('守着内测版时点「稍后」，也记在内测版这一档（下次不再弹同一个包）', (tester) async {
      SharedPreferences.setMockInitialValues({'update_channel': 'dev'});
      UpdateChecker.I.debugFetch = () async => [releaseJson('v1.13.6')];
      await pumpProfile(tester);
      await openCenter(tester);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();

      expect(UpdateChecker.I.skipped, '1.13.6', reason: '当前渠道记住了');
      expect(
        (await SharedPreferences.getInstance()).getString('update_skipped_dev'),
        '1.13.6',
      );
      // 重新 load + check：不再自动弹
      UpdateChecker.I.stableAvailable = null;
      UpdateChecker.I.devAvailable = null;
      await UpdateChecker.I.load();
      await UpdateChecker.I.check();
      expect(UpdateChecker.I.shouldPrompt, isFalse);
    });

    testWidgets('守着内测版的用户，只发了稳定版时也能收到提示', (tester) async {
      SharedPreferences.setMockInitialValues({'update_channel': 'dev'});
      UpdateChecker.I.debugFetch = () async => [releaseJson('v1.13.6')];
      await pumpProfile(tester);
      await openCenter(tester);
      await tester.tap(find.text('稍后')); // 关掉引导弹窗，看二级页上的状态
      await tester.pumpAndSettle();

      expect(
        find.text('有新版本 v1.13.6（与稳定版相同）'),
        findsOneWidget,
        reason: '内测版这一行不是「暂无版本信息」，两个渠道指向同一个包',
      );
    });

    testWidgets('检查失败：给出原因（GitHub 访问不了 / 限流都常见）', (tester) async {
      UpdateChecker.I.debugFetch = () async => throw Exception('boom');
      await pumpProfile(tester);
      await openCenter(tester);

      expect(find.textContaining('检查更新失败：网络不可用'), findsOneWidget);
      expect(find.textContaining('检查更新失败：'), findsWidgets, reason: '二级页上也留着原因');
    });

    testWidgets('稳定版与内测版分开显示：能切换渠道，切到内测版提示它的新版本', (tester) async {
      UpdateChecker.I.debugFetch = () async => [
        releaseJson('v1.13.6'),
        releaseJson('v1.14.0-dev.1'),
      ];
      await pumpProfile(tester);
      await openCenter(tester);
      await tester.tap(find.text('稍后')); // 关掉稳定版的引导弹窗
      await tester.pumpAndSettle();

      expect(find.text('稳定版'), findsOneWidget);
      expect(find.text('内测版'), findsOneWidget);
      expect(find.text('有新版本 v1.13.6'), findsOneWidget);
      expect(find.text('暂无版本信息'), findsNothing, reason: '内测版这一行也拿到了版本');
      expect(
        find.text('有新版本 v1.14.0-dev.1'),
        findsOneWidget,
        reason: '内测版比稳定版高，但要用户自己切过去',
      );

      // 内测版那行有新版时按钮是「更新」，点整行（标题）就是切渠道
      await tester.tap(find.text('内测版'));
      await tester.pumpAndSettle();
      expect(UpdateChecker.I.channel, UpdateChannel.dev);
      expect(
        (await SharedPreferences.getInstance()).getString('update_channel'),
        'dev',
      );
      // 切过去之后内测版成了当前渠道：它也有新版本，可以直接更新
      expect(find.text('有新版本 v1.14.0-dev.1'), findsOneWidget);
      expect(
        find.text('发现新版本 1.14.0-dev.1'),
        findsOneWidget,
        reason: '切到内测版后自动提示那条渠道的新版本',
      );
    });

    testWidgets('关掉弹窗提醒：不再自动弹，设置也落盘', (tester) async {
      UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.6');
      await pumpProfile(tester);
      await openCenter(tester);
      await tester.tap(find.text('稍后')); // 关掉引导弹窗，保证开关点得到
      await tester.pumpAndSettle();
      await tester.tap(find.text('新版本弹窗提醒'));
      await tester.pumpAndSettle();

      expect(UpdateChecker.I.promptEnabled, isFalse);
      expect(UpdateChecker.I.shouldPrompt, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'update_prompt_enabled',
        ),
        isFalse,
      );
    });
  });

  group('多源尝试（GitHub 失败退回镜像）', () {
    test('第一个源挂了用第二个，拿到结果', () async {
      final tried = <Uri>[];
      final j = await fetchLatestFrom(
        [Uri.parse('https://a/1'), Uri.parse('https://b/2')],
        (api) async {
          tried.add(api);
          if (api.host == 'a') throw Exception('timeout');
          return {'tag_name': 'v9.9.9'};
        },
      );
      expect(j['tag_name'], 'v9.9.9');
      expect(tried.length, 2);
    });

    test('全部失败抛最后一个错误', () async {
      await expectLater(
        fetchLatestFrom([Uri.parse('https://a/1'), Uri.parse('https://b/2')], (
          api,
        ) async {
          if (api.host == 'a') throw Exception('first');
          throw Exception('second');
        }),
        throwsA(
          isA<Exception>().having((e) => '$e', 'msg', contains('second')),
        ),
      );
    });

    test('镜像源已配置（Gitee 优先，GitHub 次之，anticraft.top 兜底）', () {
      expect(latestReleaseApis.first.host, 'gitee.com');
      expect(latestReleaseApis.first.path, contains(giteeUpdateRepo));
      expect(latestReleaseApis[1].host, 'api.github.com');
      expect(latestReleaseApis.last.host, 'anticraft.top');
    });

    test('内测版 tag（dev-1.48.1-dev.1）解析成 1.48.1-dev.1，不会因为前缀比错', () {
      expect(normalizeVersion('dev-1.48.1-dev.1'), '1.48.1-dev.1');
      final info = parseRelease(releaseJson('dev-1.48.1-dev.1'))!;
      expect(info.version, '1.48.1-dev.1');
      expect(info.channel, UpdateChannel.dev, reason: '带预发布段 → 内测版');
    });

    test('Gitee 列表必须带 direction=desc：默认升序只会拿到最老的那批', () {
      // 实测 per_page=50 不带 direction 时返回 v1.19.0…v1.41.7，最新几个版本压根不在里面
      expect(releaseListApis.first.host, 'gitee.com');
      expect(releaseListApis.first.queryParameters['direction'], 'desc');
      expect(releaseListApis[1].host, 'api.github.com');
    });

    test('多源都成功时取版本最高的，镜像滞后不会藏住新版', () async {
      final j = await fetchLatestFrom(
        [
          Uri.parse('https://gitee.com/a'),
          Uri.parse('https://api.github.com/b'),
        ],
        (api) async {
          return api.host == 'gitee.com'
              ? releaseJson('v1.18.0')
              : releaseJson('v1.19.0');
        },
      );
      expect(parseRelease(j)!.version, '1.19.0');
    });

    test('同版本优先靠前的源（Gitee 下载地址）', () async {
      final a = {'tag_name': 'v1.19.0', 'marker': 'gitee'};
      final b = {'tag_name': 'v1.19.0', 'marker': 'github'};
      final j = await fetchLatestFrom([
        Uri.parse('https://gitee.com/a'),
        Uri.parse('https://api.github.com/b'),
      ], (api) async => api.host == 'gitee.com' ? a : b);
      expect(j['marker'], 'gitee');
    });
  });

  test('点过「稍后」的版本不再自动弹，手动检查仍看得到', () async {
    UpdateChecker.I.debugFetch = () async => releaseJson('v1.13.6');
    await UpdateChecker.I.load();
    await UpdateChecker.I.check();
    expect(UpdateChecker.I.shouldPrompt, isTrue);

    await UpdateChecker.I.skip();

    // 下次启动：清掉内存里的结论，重新 load + check —— 应该不再弹
    UpdateChecker.I.stableAvailable = null;
    UpdateChecker.I.devAvailable = null;
    await UpdateChecker.I.load();
    await UpdateChecker.I.check();
    expect(UpdateChecker.I.shouldPrompt, isFalse);
    expect(
      UpdateChecker.I.available!.version,
      '1.13.6',
      reason: '结论还在，「我的」页照旧能看到',
    );
  });
}
