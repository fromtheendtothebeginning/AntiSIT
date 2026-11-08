import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_service/update_check.dart';
import 'package:campus_service/update_download.dart';
import 'package:campus_service/widgets/update_dialog.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 「应用内更新下载」的验收：整条链路（流式下载 → 进度 → sha256 校验 → 拉起安装器）
/// 都用注入的假流跑，不联网。重点盯三件容易悄悄错的事：
/// * 校验不过的包必须删掉，绝不能交给安装器；
/// * 中途取消要掐掉半截文件、状态回干净；
/// * 缺「安装未知应用」授权时，回来能凭 readyPath 再装一次。
void main() {
  late Directory tmp;
  const payload = 'fake-apk-bytes';
  final bytes = utf8.encode(payload);
  String sha256Of(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

  /// 分两段发：下载进度和拼包逻辑都要靠它验出来。
  http.StreamedResponse okResponse() => http.StreamedResponse(
      Stream.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]),
      200,
      contentLength: bytes.length);

  UpdateInfo info({bool withSha = true}) => UpdateInfo(
        version: '1.26.0',
        notes: '',
        pageUrl: 'https://gitee.com/ender123/AntiSIT/releases',
        apkUrl: 'https://gitee.com/x/AntiSIT-1.26.0.apk',
        sha256Url: withSha ? 'https://gitee.com/x/AntiSIT-1.26.0.apk.sha256' : null,
      );

  setUp(() {
    UpdateDownloader.I.reset();
    tmp = Directory.systemTemp.createTempSync('update_dl');
    UpdateDownloader.debugSaveDir = () async => tmp;
  });
  tearDown(() {
    UpdateDownloader.I.reset();
    tmp.deleteSync(recursive: true);
  });

  group('下载 → 校验 → 安装', () {
    test('校验通过：文件就位、自动拉起安装器', () async {
      UpdateDownloader.debugStream = (_) async => okResponse();
      UpdateDownloader.debugText = (_) async => sha256Of(payload);
      final installed = <String>[];
      UpdateDownloader.debugInstall = (path) async {
        installed.add(path);
        return true;
      };

      await UpdateDownloader.I.start(info());

      expect(UpdateDownloader.I.status, 'ready');
      expect(UpdateDownloader.I.received, bytes.length);
      expect(UpdateDownloader.I.total, bytes.length);
      expect(UpdateDownloader.I.error, isNull);
      final file = File(UpdateDownloader.I.readyPath!);
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), bytes);
      expect(file.path, endsWith('AntiSIT-1.26.0.apk'), reason: '按版本号命名');
      expect(installed, [file.path], reason: '校验通过后自动拉起安装器');
    });

    test('sha256 对不上：报错、删包、不碰安装器', () async {
      UpdateDownloader.debugStream = (_) async => okResponse();
      UpdateDownloader.debugText =
          (_) async => 'f' * 64; // 64 位十六进制、但哈希不对，走「校验不通过」分支
      final installed = <String>[];
      UpdateDownloader.debugInstall = (path) async {
        installed.add(path);
        return true;
      };

      await UpdateDownloader.I.start(info());

      expect(UpdateDownloader.I.status, 'error');
      expect(UpdateDownloader.I.error, contains('校验不通过'));
      expect(File('${tmp.path}/update/AntiSIT-1.26.0.apk').existsSync(), isFalse,
          reason: '校验不过的包不能留在盘上');
      expect(UpdateDownloader.I.readyPath, isNull);
      expect(installed, isEmpty);
    });

    test('发布页没挂 .sha256：跳过校验直接就绪', () async {
      UpdateDownloader.debugStream = (_) async => okResponse();
      final installed = <String>[];
      UpdateDownloader.debugInstall = (_) async {
        installed.add('x');
        return true;
      };

      await UpdateDownloader.I.start(info(withSha: false));

      expect(UpdateDownloader.I.status, 'ready');
      expect(installed, isNotEmpty);
    });

    test('下载 404：进 error，原因带上状态码', () async {
      UpdateDownloader.debugStream =
          (_) async => http.StreamedResponse(Stream.value([]), 404);

      await UpdateDownloader.I.start(info());

      expect(UpdateDownloader.I.status, 'error');
      expect(UpdateDownloader.I.error, contains('404'));
    });

    test('进度随下载上报，最后能看到 100%', () async {
      UpdateDownloader.I.notifyEveryBytes = 1;
      final fractions = <double>[];
      UpdateDownloader.I.addListener(() {
        if (UpdateDownloader.I.total > 0) {
          fractions.add(UpdateDownloader.I.received / UpdateDownloader.I.total);
        }
      });
      UpdateDownloader.debugStream = (_) async => okResponse();
      UpdateDownloader.debugText = (_) async => sha256Of(payload);
      UpdateDownloader.debugInstall = (_) async => true;

      await UpdateDownloader.I.start(info());

      expect(fractions, isNotEmpty);
      expect(fractions.last, 1.0);
      expect(fractions.first, lessThan(1.0), reason: '分了两段，第一段就该上报');
    });
  });

  group('取消与重入', () {
    test('中途取消：半截文件删掉、状态回 idle、不碰安装器', () async {
      final gate = StreamController<List<int>>();
      UpdateDownloader.debugStream =
          (_) async => http.StreamedResponse(gate.stream, 200, contentLength: 1000);
      final installed = <String>[];
      UpdateDownloader.debugInstall = (_) async {
        installed.add('x');
        return true;
      };

      final done = UpdateDownloader.I.start(info());
      while (UpdateDownloader.I.status != 'downloading') {
        await Future<void>.delayed(Duration.zero);
      }
      gate.add([1, 2, 3]);
      while (UpdateDownloader.I.received < 3) {
        await Future<void>.delayed(Duration.zero);
      }
      final cancelled = UpdateDownloader.I.cancel();
      await done;
      await cancelled; // cancel 是异步的（先关 sink 再删文件），收尾完才断言
      await gate.close();

      expect(UpdateDownloader.I.status, 'idle');
      expect(UpdateDownloader.I.received, 0);
      expect(File('${tmp.path}/update/AntiSIT-1.26.0.apk').existsSync(), isFalse);
      expect(installed, isEmpty);
    });

    test('下载中再点去下载：不会并发第二趟', () async {
      final gate = Completer<void>();
      UpdateDownloader.debugStream = (_) async {
        await gate.future;
        return okResponse();
      };
      UpdateDownloader.debugText = (_) async => sha256Of(payload);
      UpdateDownloader.debugInstall = (_) async => true;

      final first = UpdateDownloader.I.start(info());
      while (UpdateDownloader.I.status != 'downloading') {
        await Future<void>.delayed(Duration.zero);
      }
      await UpdateDownloader.I.start(info()); // busy → 直接返回
      gate.complete();
      await first;

      expect(UpdateDownloader.I.status, 'ready');
    });
  });

  group('拉起安装器', () {
    test('缺「安装未知应用」授权：给出提示，回来凭 readyPath 再装一次', () async {
      Object result = 'settings';
      final calls = <String>[];
      UpdateDownloader.debugStream = (_) async => okResponse();
      UpdateDownloader.debugText = (_) async => sha256Of(payload);
      UpdateDownloader.debugInstall = (path) async {
        calls.add(path);
        return result;
      };

      await UpdateDownloader.I.start(info());
      expect(UpdateDownloader.I.installNote, contains('安装未知应用'));
      expect(UpdateDownloader.I.readyPath, isNotNull, reason: '文件还在，回来不用重下');

      result = true; // 授权回来了
      await UpdateDownloader.I.install();
      expect(UpdateDownloader.I.installNote, isNull);
      expect(calls.length, 2);
    });

    test('拉起失败的错误细节透传到提示里（native 返回 error: 原因）', () async {
      UpdateDownloader.I.readyPath = '/tmp/AntiSIT-1.27.0.apk'; // 就绪态，只测 install 的提示分支
      UpdateDownloader.debugInstall = (path) async => 'error: FileProvider(路径不在白名单)';
      await UpdateDownloader.I.install();
      expect(UpdateDownloader.I.installNote,
          contains('FileProvider(路径不在白名单)'), reason: '真实原因直接可见，别再笼统一句');
    });

    test('去授权回来（app resumed）自动续装，不用再点一次', () async {
      Object result = 'settings';
      final calls = <String>[];
      UpdateDownloader.I.readyPath = '/tmp/AntiSIT-1.27.0.apk';
      UpdateDownloader.debugInstall = (path) async {
        calls.add(path);
        return result;
      };

      await UpdateDownloader.I.install();
      expect(UpdateDownloader.I.installNote, contains('自动继续安装'));
      expect(calls.length, 1);

      // 模拟从授权页回到 App（授权已成功）：lifecycle resumed → 观察者自动续装
      result = true;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 50 && calls.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // 第二次 install 的 notifyListeners 在 calls.add 之后：等 note 真正清掉
      for (var i = 0; i < 100 && UpdateDownloader.I.installNote != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(calls.length, 2, reason: '授权回来自动重试，不用用户再点');
      expect(UpdateDownloader.I.installNote, isNull);
    });
  });

  group('弹窗（真组件）', () {
    Future<void> pumpDialog(WidgetTester tester) async {
      UpdateDownloader.I.reset();
      UpdateDownloader.debugSaveDir = () async => tmp;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showUpdateDialog(ctx, info()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    /// 下载链路里混着两样东西：真磁盘 IO（建目录、写文件，得放 runAsync 放行真事件）
    /// 和 FakeAsync 队列里的微任务（真 IO 完成后的回调排在里面，得 pump 才跑）——
    /// 所以轮着来，直到不在下载中。只 runAsync 不 pump 会死等，只 pump 不 runAsync
    /// 真事件永远不来。
    Future<void> driveDownload(WidgetTester tester) async {
      await tester.tap(find.text('去下载'));
      await tester.pump();
      for (var i = 0; i < 100 && UpdateDownloader.I.busy; i++) {
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(UpdateDownloader.I.busy, isFalse, reason: '假流 100 轮内该跑完');
      await tester.pumpAndSettle();
    }

    testWidgets('去下载 → 下载中 → 就绪后变「安装」', (tester) async {
      await pumpDialog(tester); // reset 在这里面发生，钩子要在它之后设
      UpdateDownloader.debugStream = (_) async => okResponse();
      UpdateDownloader.debugText = (_) async => sha256Of(payload);
      UpdateDownloader.debugInstall = (_) async => true;
      expect(find.text('去下载'), findsOneWidget);

      await driveDownload(tester);

      expect(UpdateDownloader.I.status, 'ready');
      expect(find.text('安装'), findsOneWidget, reason: '下载校验都完成，按钮变「安装」');
      expect(find.text('去下载'), findsNothing);
    });

    testWidgets('下载失败：显示原因、可重试、留了浏览器兜底入口', (tester) async {
      await pumpDialog(tester);
      UpdateDownloader.debugStream =
          (_) async => http.StreamedResponse(Stream.error(Exception('boom')), 200);

      await driveDownload(tester);

      expect(find.textContaining('下载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('用浏览器打开下载链接'), findsOneWidget);
    });
  });
}
