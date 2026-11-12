import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_check.dart';

/// 「去下载」的应用内实现：把 Release 的 APK 流式拉到本机缓存，**必须**对照发布页
/// 同时挂的 `.apk.sha256` 校验（缺失即拒绝，不跳过），并让 native 确认下载包的包名/
/// 签名与当前安装版本一致，才交给系统安装器覆盖安装（数据保留）。
///
/// 状态机：idle → downloading → verifying → ready（自动拉起安装器）；任何一步失败
/// 进 error，弹窗里可以重试，也可以退回「浏览器打开下载链接」。安卓侧的授权与安装
/// 见 `MainActivity.installApk`——缺「安装未知应用」授权时会先跳系统设置页。
class UpdateDownloader extends ChangeNotifier with WidgetsBindingObserver {
  UpdateDownloader._() {
    // 从「安装未知应用」授权页回来时自动续装（见 didChangeAppLifecycleState）
    WidgetsBinding.instance.addObserver(this);
    // 安装会话的最终状态由 native 异步回传（pending / success / failed）
    _channel.setMethodCallHandler(_onNativeCall);
  }
  static final UpdateDownloader I = UpdateDownloader._();

  static const _channel = MethodChannel('antisit/system');

  /// 进度通知的节流粒度：收满这么多字节才 notify 一次（最后一段总会通知），
  /// 几万次 rebuild 就为了刷进度条不值当。测试里改小。
  int notifyEveryBytes = 256 * 1024;

  /// 当前状态：idle / downloading / verifying / ready / error。
  String status = 'idle';
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

  /// 本次 install 是否已收到 native 的异步安装状态。
  /// 通道返回值与状态事件有先后竞争：收到了就别再用 `true` 把提示清空。
  bool _nativeStatusSeen = false;

  bool get busy => status == 'downloading' || status == 'verifying';

  // ---- 测试注入点（不联网跑完整个流程）----
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
      final base = await (debugSaveDir?.call() ?? getTemporaryDirectory());
      final dir = Directory('${base.path}/update');
      await dir.create(recursive: true);
      // 版本号来自更新源 JSON，不能直接拼进文件名（防 `../` 之类越界）；
      // 正常版本号（1.26.0 / 1.14.0-rc1）原样保留，测试也依赖这个命名。
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

  /// 拉起系统安装器。下载校验通过后会自动调一次；缺「安装未知应用」授权时
  /// native 会跳授权页，授权回来由 [didChangeAppLifecycleState] 自动续装。
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
      // 参数必须是 Map：native 侧用 call.argument("path") 取，MethodCall.argument 遇到
      // 裸字符串会直接抛 ClassCastException（表现为「没能拉起安装器」）。
      r = await (debugInstall?.call(path) ??
          _channel.invokeMethod('installApk', {'path': path}));
    } catch (e) {
      // 通道异常也带上原因：MissingPluginException（没实现）/ PlatformException
      // （ROM 拒绝）各有不同修法，笼统一句没法定位；PlatformException 的 toString
      // 带整段堆栈，只留第一行够定位
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

  /// native 回传的安装状态（PackageInstaller 的异步结果）。
  ///
  /// - pending：系统要求用户确认，MainActivity 已经把确认页拉起来了
  /// - success：系统报告安装成功（覆盖安装时进程通常会被替换，未必能看到）
  /// - failed：拦截 / 冲突 / 包损坏等；安装包还在，重试只需再点「重试安装」
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

  /// 中止本次下载（弹窗点「稍后」、或重开下载前的清理）：关连接与写文件的 sink
  /// （Windows 上句柄不关删不掉文件）、删半截文件、状态回 idle。
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

  /// 原生校验：下载的 APK 必须与当前安装版本的包名、签名一致（Android 安装器本身也会拦，
  /// 但先在这里拦能给用户一句清楚的原因，别把可疑包送到安装确认页）。返回 null = 通过。
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

/// [UpdateDownloader.cancel] 中止下载时抛给 start() 的退出信号
/// （状态由 cancel 自己收拾，start 直接退出就行）。
class _Cancelled implements Exception {
  const _Cancelled();
}
