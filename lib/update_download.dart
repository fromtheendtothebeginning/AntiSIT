import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_check.dart';

/// 应用内下载安装：APK 流式拉到本机缓存 → 校验发布页的 `.apk.sha256`（缺失即拒绝，不跳过）
/// → native 确认包名 / 签名与当前版本一致 → 交给系统安装器覆盖安装（数据保留）。
class UpdateDownloader extends ChangeNotifier with WidgetsBindingObserver {
  UpdateDownloader._() {
    // 从「安装未知应用」授权页回来时自动续装（见 didChangeAppLifecycleState）
    WidgetsBinding.instance.addObserver(this);
    // 安装会话的最终状态由 native 异步回传（pending / success / failed）
    _channel.setMethodCallHandler(_onNativeCall);
  }
  static final UpdateDownloader I = UpdateDownloader._();

  static const _channel = MethodChannel('antisit/system');

  /// 进度通知的节流粒度：收满这么多字节才 notify 一次（最后一段总会通知）。
  int notifyEveryBytes = 256 * 1024;

  /// 当前状态：idle / downloading / verifying / ready / error。
  String status = 'idle';

  /// 已收到的字节数。
  int received = 0;

  /// 服务端声明的总大小（0 = 没给 Content-Length，进度条转圈）。
  int total = 0;

  /// 失败原因（error 状态时给弹窗显示）。
  String? error;

  /// 下载校验通过后的本地路径；「去授权再回来」之后就靠它重试 [install]。
  String? readyPath;

  /// 拉起安装器的结果说明（null = 已正常拉起）。
  String? installNote;

  /// 跳去授权「安装未知应用」了：授权回来（app resumed）自动续装，不用再点一次。
  bool _awaitingSettings = false;

  /// 本次 install 是否已收到 native 的异步安装状态（通道返回值与状态事件有先后竞争）。
  bool _nativeStatusSeen = false;

  /// 是否正在下载 / 校验。
  bool get busy => status == 'downloading' || status == 'verifying';

  // 测试注入点（不联网跑完整个流程）
  @visibleForTesting
  static Future<http.StreamedResponse> Function(Uri)? debugStream;
  @visibleForTesting
  static Future<String> Function(Uri)? debugText;
  @visibleForTesting
  static Future<Object?> Function(String path)? debugInstall;
  @visibleForTesting
  static Future<Directory> Function()? debugSaveDir;

  /// 测试注入：原生签名校验。返回 null = 通过，返回字符串 = 失败原因。
  @visibleForTesting
  static Future<String?> Function(String path)? debugVerifySignature;

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Completer<void>? _completer;
  IOSink? _sink;
  File? _partial;
  int _notified = 0;

  /// 更新包缓存目录（`<缓存目录>/update`）：每个版本都下到这里。
  static Future<Directory> cacheDir() async {
    final base = await (debugSaveDir?.call() ?? getTemporaryDirectory());
    final dir = Directory('${base.path}/update');
    await dir.create(recursive: true);
    return dir;
  }

  /// 缓存里所有安装包加起来多大（字节）。
  static Future<int> cachedBytes() async {
    var sum = 0;
    try {
      final dir = await cacheDir();
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.apk')) continue;
        try {
          sum += await e.length();
        } catch (_) {}
      }
    } catch (_) {}
    return sum;
  }

  /// 删掉下载过的安装包，返回释放的字节数。
  /// [keepReady] 为 true 时保留还等着安装的那一份（「重试安装」要用）；启动清扫与手动清理传 false。
  Future<int> purgeCache({bool keepReady = false}) async {
    if (busy) await cancel(); // 正在下的那半截先收掉，否则删不掉（句柄还开着）
    if (keepReady && readyPath == null) return 0;
    final keep = keepReady ? readyPath : null;
    var freed = 0;
    final removedReady = <String>[];
    try {
      final dir = await cacheDir();
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        if (keep != null && e.path.replaceAll('\\', '/') == keep.replaceAll('\\', '/')) {
          continue;
        }
        try {
          freed += await e.length();
          await e.delete();
          removedReady.add(e.path);
        } catch (_) {}
      }
    } catch (_) {}
    final ready = readyPath;
    // 比较时统一分隔符：dir.list() 给的是反斜杠路径，readyPath 可能来自调用方手写，别漏判。
    String normal(String path) => path.replaceAll('\\', '/');
    final removed = removedReady.map(normal).toSet();
    if (ready != null && removed.contains(normal(ready)) && !File(ready).existsSync()) {
      readyPath = null;
      if (status == 'ready' || status == 'error') status = 'idle';
      notifyListeners();
    }
    return freed;
  }

  /// 启动时清扫上次留下的安装包；只在空闲且没有待装文件时做，不动正在下载 / 就绪的那一轮。
  Future<void> sweepCache() async {
    if (busy || readyPath != null) return;
    await purgeCache();
  }

  /// 下载 [info] 的 APK → 校验 sha256 → 校验包名/签名 → 自动拉起安装器。
  Future<void> start(UpdateInfo info) async {
    final apk = info.apkUrl;
    final sha = info.sha256Url;
    if (apk == null || busy) return;
    await cancel(); // 清掉上一轮的状态与半截文件
    if (sha == null || sha.isEmpty) {
      _fail('发布页缺少 .apk.sha256 校验文件，已拒绝自动安装；请用浏览器下载');
      return;
    }
    final apkUri = Uri.tryParse(apk);
    final shaUri = Uri.tryParse(sha);
    if (apkUri == null ||
        shaUri == null ||
        !isAllowedUpdateUrl(apkUri) ||
        !isAllowedUpdateUrl(shaUri)) {
      _fail('更新地址不在允许的发布源内，已拒绝自动安装；请用浏览器打开发布页');
      return;
    }
    status = 'downloading';
    received = 0;
    total = 0;
    error = null;
    installNote = null;
    notifyListeners();

    http.Client? client;
    IOSink? sink;
    try {
      final dir = await cacheDir();
      // 版本号来自更新源 JSON，不能直接拼进文件名（防 `../` 越界）；正常版本号原样保留。
      final safeVersion = info.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      final file = File('${dir.path}/AntiSIT-$safeVersion.apk');
      _partial = file;

      final res = debugStream != null
          ? await debugStream!(Uri.parse(apk))
          : await (_client = client = http.Client())
              .send(http.Request('GET', Uri.parse(apk)));
      if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}');
      total = res.contentLength ?? 0;

      // 30 秒收不到任何数据就当连接死了（大文件下载没法给整体设超时）
      final completer = Completer<void>();
      _completer = completer;
      sink = _sink = file.openWrite();
      _sub = res.stream
          .timeout(const Duration(seconds: 30))
          .listen((chunk) {
            received += chunk.length;
            sink!.add(chunk);
            if (received - _notified >= notifyEveryBytes) {
              _notified = received;
              notifyListeners();
            }
          },
              onDone: completer.complete,
              onError: completer.completeError,
              cancelOnError: true);
      await completer.future;
      await sink.flush();
      await sink.close();
      sink = null;

      status = 'verifying';
      notifyListeners();
      _verify(await _sha256Of(sha), await _digestOf(file));
      final signatureProblem = await (debugVerifySignature?.call(file.path) ??
          _verifyApkSignature(file.path));
      if (signatureProblem != null) throw FormatException(signatureProblem);
      readyPath = file.path;
      _partial = null;
      status = 'ready';
      notifyListeners();
      await install();
    } catch (e) {
      if (e is _Cancelled) return; // cancel() 已经把状态收拾干净
      try {
        await sink?.close();
      } catch (_) {}
      _fail(_reason(e));
    } finally {
      _sink = null;
      _sub = null;
      _completer = null;
      _partial = null;
      client?.close();
      _client = null;
    }
  }

  /// 拉起系统安装器。下载校验通过后自动调一次；缺「安装未知应用」授权时由
  /// [didChangeAppLifecycleState] 在授权回来后续装。
  Future<void> install() async {
    final path = readyPath;
    if (path == null) return;
    // 失败后点「重试安装」：回到就绪态再发起，别让界面一直停在 error 上
    if (status != 'ready') {
      status = 'ready';
      error = null;
    }
    _nativeStatusSeen = false;
    notifyListeners();
    Object? r = 'error';
    try {
      // 参数必须是 Map：native 侧用 call.argument("path") 取，裸字符串会抛 ClassCastException。
      r = await (debugInstall?.call(path) ??
          _channel.invokeMethod('installApk', {'path': path}));
    } catch (e) {
      // 通道异常也带上原因（MissingPluginException / PlatformException 各有不同修法），只留第一行。
      r = 'error: ${'$e'.split('\n').first}';
    }
    _awaitingSettings = r == 'settings';
    installNote = switch (r) {
      // 状态事件可能比通道返回值先到：保留它写好的提示（pending / 失败原因）
      true => _nativeStatusSeen ? installNote : null,
      'settings' => '已跳转授权页：请允许「安装未知应用」，回来自动继续安装',
      'missing' => '安装包不见了，请重新下载',
      String s when s.startsWith('error:') =>
        '没能拉起安装器（${s.substring(6).trim()}）。可改用浏览器下载',
      _ => '没能拉起安装器，可改用浏览器下载',
    };
    notifyListeners();
  }

  /// native 回传的安装状态：pending（已拉起确认页）/ success（安装完成）/ failed（拦截、冲突、包损坏）。
  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'installResult') return null;
    final args = call.arguments is Map ? call.arguments as Map : const {};
    final state = '${args['status'] ?? ''}';
    final code = args['code'] is int ? args['code'] as int : null;
    final message = '${args['message'] ?? ''}'.trim();
    // 用户已经重新下载 / 取消了：上一轮安装的迟到结果别来改当前状态
    if (status != 'ready') return null;
    _nativeStatusSeen = true;
    switch (state) {
      case 'pending':
        installNote = '已调起系统安装确认，请按提示完成安装';
        break;
      case 'success':
        installNote = '安装完成，打开新版本即可';
        // 装完就没用了：删失败也无所谓，启动时的 sweepCache 还会扫一遍。
        unawaited(purgeCache());
        break;
      case 'failed':
        // 只改文案与主按钮，readyPath 留着：重试安装不用重新下载
        status = 'error';
        error = _installFailure(code, message);
        installNote = null;
        break;
    }
    notifyListeners();
    return null;
  }

  /// PackageInstaller 失败码 → 人话（常量见 android.content.pm.PackageInstaller）。
  String _installFailure(int? code, String raw) => switch (code) {
        2 => '系统拦截了安装（手机管家 / 纯净模式或安全策略阻止），请在系统设置里放行后重试',
        3 => '安装被取消',
        4 => '安装包无效或已损坏，请重新下载',
        5 => '安装冲突：已安装版本的签名不同或版本更高，需先卸载旧版',
        6 => '存储空间不足',
        7 => '安装包与当前系统不兼容',
        8 => '安装超时，请重试',
        _ => raw.isEmpty ? '安装失败，可改用浏览器下载' : '安装失败：$raw',
      };

  /// 从「安装未知应用」授权页回到 App：自动把上一次的安装续上（readyPath 还在）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSettings && readyPath != null) {
      _awaitingSettings = false;
      install();
    }
  }

  /// 中止本次下载：关连接与 sink（不关句柄 Windows 上删不掉）、删半截文件、状态回 idle；
  /// ready 状态的成品文件不动（重试「安装」还要用）。
  Future<void> cancel() async {
    _client?.close();
    _client = null;
    _sub?.cancel();
    _sub = null;
    final s = _sink;
    _sink = null;
    try {
      await s?.close();
    } catch (_) {}
    // start() 还挂着等流结束：让它走 _Cancelled 分支退出
    final c = _completer;
    if (c != null && !c.isCompleted) c.completeError(const _Cancelled());
    _completer = null;
    _deletePartial();
    received = 0;
    total = 0;
    error = null;
    readyPath = null;
    installNote = null;
    _nativeStatusSeen = false;
    if (status != 'idle') {
      status = 'idle';
      notifyListeners();
    }
  }

  @visibleForTesting
  void reset() {
    cancel();
    status = 'idle';
    _awaitingSettings = false;
    _nativeStatusSeen = false;
    notifyEveryBytes = 256 * 1024;
    debugStream = null;
    debugText = null;
    debugInstall = null;
    debugSaveDir = null;
    debugVerifySignature = null;
  }

  /// 取发布页挂的 `.apk.sha256`。调用方已保证 [sha256Url] 非空且在发布域白名单内。
  Future<String> _sha256Of(String url) async =>
      (await (debugText?.call(Uri.parse(url)) ?? http.read(Uri.parse(url)))).trim();

  Future<String> _digestOf(File file) async =>
      (await crypto.sha256.bind(file.openRead()).first).toString();

  void _verify(String want, String got) {
    final w = RegExp(r'[0-9a-fA-F]{64}').firstMatch(want)?.group(0);
    if (w == null) throw const FormatException('校验文件里没有 sha256');
    if (w.toLowerCase() != got.toLowerCase()) {
      throw const FormatException('安装包校验不通过（可能下载坏了或被篡改）');
    }
  }

  /// 原生校验：下载的 APK 必须与当前安装版本同包名、同签名（先在这里拦能给一句清楚的原因）。
  Future<String?> _verifyApkSignature(String path) async {
    try {
      final r = await _channel.invokeMethod<Object?>('verifyApkSignature', {'path': path});
      if (r == true) return null;
      if (r is String && r.isNotEmpty) return r;
      return '安装包签名校验未通过（可能不是官方更新）';
    } catch (e) {
      return '无法校验安装包签名：${'$e'.split('\n').first}';
    }
  }

  void _fail(String message) {
    error = message;
    status = 'error';
    _deletePartial();
    notifyListeners();
  }

  void _deletePartial() {
    final p = _partial;
    _partial = null;
    try {
      if (p != null && p.existsSync()) p.deleteSync();
    } catch (_) {}
  }

  /// 失败原因 → 给用户看的短句（限流 / 链接失效最常见）。
  String _reason(Object e) {
    if (e is TimeoutException) return '网络超时';
    final s = '$e';
    if (s.contains('403')) return '下载被拒（403），过一会儿再试';
    if (s.contains('404')) return '下载地址已失效（404）';
    return '下载失败：$s';
  }
}

/// 字节数 → 人话（缓存占用、清理结果这些地方用）。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

/// [UpdateDownloader.cancel] 中止下载时抛给 start() 的退出信号（状态由 cancel 自己收拾）。
class _Cancelled implements Exception {
  const _Cancelled();
}
