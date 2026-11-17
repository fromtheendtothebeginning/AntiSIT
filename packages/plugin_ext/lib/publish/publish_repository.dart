import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'publish_models.dart';

/// 远端仓库信息（只需要默认分支与是否公开）。
class RemoteRepo {
  const RemoteRepo({required this.defaultBranch, required this.private});

  final String defaultBranch;
  final bool private;
}

/// 远端文件：内容读不出来（文件太大 / 二进制被截断）时 [bytes] 为 null，
/// 但 [sha] 仍然可用于更新。
class RemoteFile {
  const RemoteFile({required this.bytes, required this.sha});

  final List<int>? bytes;
  final String sha;
}

/// 发布用的远端仓库操作。抽成接口是为了单测能换掉真实 HTTP。
abstract class PublishRepository {
  Future<String> login();

  /// 仓库不存在返回 null。
  Future<RemoteRepo?> repo();

  /// 新建一个公开仓库（auto_init）。
  Future<RemoteRepo> create();

  Future<RemoteFile?> file(String path, {required String branch});

  /// 内容没变就跳过（不制造空提交）。
  Future<void> putFile(
    String path,
    List<int> bytes, {
    required String branch,
    required String message,
  });
}

PublishRepository defaultPublishRepository(
  PublishConfig config,
  String token, {
  http.Client? client,
}) =>
    switch (config.provider) {
      PublishProvider.github => GitHubPublishRepository(
          owner: config.owner,
          repo: config.repo,
          token: token,
          client: client,
        ),
      PublishProvider.gitee => GiteePublishRepository(
          owner: config.owner,
          repo: config.repo,
          token: token,
          client: client,
        ),
    };

String _encodePath(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');

bool _sameBytes(List<int> a, List<int> b) => listEquals(a, b);

String _shortBody(http.Response res) {
  final body = res.body.trim();
  return body.length <= 300 ? body : '${body.substring(0, 300)}…';
}

// ==================== GitHub ====================

/// GitHub REST API（Contents API）。
///
/// Token 需要 `repo`（私有仓库 / 更新已有文件）或 `public_repo`（公开仓库）范围；
/// 新建仓库也走同一个 Token。
class GitHubPublishRepository implements PublishRepository {
  GitHubPublishRepository({
    required this.owner,
    required String repo,
    required this.token,
    http.Client? client,
  })  : repoName = repo,
        _client = client ?? http.Client();

  final String owner;
  final String repoName;
  final String token;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);
  static const Map<String, String> _accept = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'AntiSIT',
  };

  Map<String, String> get _headers => {..._accept, 'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.https('api.github.com', path, query);

  Future<http.Response> _get(Uri uri) =>
      _client.get(uri, headers: _headers).timeout(_timeout);

  Future<http.Response> _put(Uri uri, Object body) => _client
      .put(uri,
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body))
      .timeout(_timeout);

  Future<http.Response> _post(Uri uri, Object body) => _client
      .post(uri,
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body))
      .timeout(_timeout);

  @override
  Future<String> login() async {
    final res = await _get(_uri('/user'));
    _ok(res);
    final raw = jsonDecode(res.body);
    final login = raw is Map ? '${raw['login'] ?? ''}' : '';
    if (login.isEmpty) throw StateError('GitHub Token 校验失败（读不到账号）');
    return login;
  }

  @override
  Future<RemoteRepo?> repo() async {
    final res = await _get(_uri('/repos/$owner/$repoName'));
    if (res.statusCode == 404) return null;
    _ok(res);
    return _parseRepo(res);
  }

  @override
  Future<RemoteRepo> create() async {
    final me = await login();
    final path = owner.toLowerCase() == me.toLowerCase()
        ? '/user/repos'
        : '/orgs/$owner/repos';
    final res = await _post(_uri(path), {
      'name': repo,
      'private': false,
      'auto_init': true,
      'description': 'AntiSIT 拓展源',
    });
    _ok(res);
    return _parseRepo(res);
  }

  @override
  Future<RemoteFile?> file(String path, {required String branch}) async {
    final res = await _get(
        _uri('/repos/$owner/$repoName/contents/${_encodePath(path)}', {'ref': branch}));
    if (res.statusCode == 404) return null;
    _ok(res);
    final raw = jsonDecode(res.body);
    if (raw is! Map) return null;
    final content = '${raw['content'] ?? ''}';
    List<int>? bytes;
    if (content.isNotEmpty) {
      try {
        bytes = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
      } catch (_) {
        bytes = null;
      }
    }
    return RemoteFile(bytes: bytes, sha: '${raw['sha'] ?? ''}');
  }

  @override
  Future<void> putFile(String path, List<int> bytes,
      {required String branch, required String message}) async {
    final existing = await file(path, branch: branch);
    if (existing?.bytes != null && _sameBytes(existing!.bytes!, bytes)) return;
    final body = <String, Object?>{
      'message': message,
      'content': base64Encode(bytes),
      'branch': branch,
      if (existing != null && existing.sha.isNotEmpty) 'sha': existing.sha,
    };
    final res = await _put(
        _uri('/repos/$owner/$repoName/contents/${_encodePath(path)}'), body);
    _ok(res);
  }

  RemoteRepo _parseRepo(http.Response res) {
    final raw = jsonDecode(res.body);
    if (raw is! Map) throw StateError('GitHub 返回的仓库信息看不懂');
    final branch = '${raw['default_branch'] ?? ''}'.trim();
    return RemoteRepo(
      defaultBranch: branch.isEmpty ? 'main' : branch,
      private: raw['private'] == true,
    );
  }

  void _ok(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var msg = 'GitHub 请求失败（HTTP ${res.statusCode}）';
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map && '${raw['message'] ?? ''}'.isNotEmpty) {
        msg = 'GitHub：${raw['message']}';
      }
    } catch (_) {
      msg = 'GitHub 请求失败（HTTP ${res.statusCode}）：${_shortBody(res)}';
    }
    throw StateError(msg);
  }
}

// ==================== Gitee ====================

/// Gitee Open API v5。Token 需要仓库（projects）相关权限。
///
/// Gitee 的 Token 走 `access_token` 参数 / 表单字段；写文件时新建用 POST、
/// 更新用 PUT 并带旧文件的 sha。
class GiteePublishRepository implements PublishRepository {
  GiteePublishRepository({
    required this.owner,
    required String repo,
    required this.token,
    http.Client? client,
  })  : repoName = repo,
        _client = client ?? http.Client();

  final String owner;
  final String repoName;
  final String token;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  Uri _uri(String path, [Map<String, String>? query]) => Uri.https(
        'gitee.com',
        '/api/v5$path',
        {...?query, 'access_token': token},
      );

  Future<http.Response> _get(Uri uri) =>
      _client.get(uri, headers: const {'Accept': 'application/json'}).timeout(_timeout);

  Future<http.Response> _send(String method, Uri uri, Object body) => _client
      .send(http.Request(method, uri)
        ..headers.addAll(const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode(body))
      .then(http.Response.fromStream)
      .timeout(_timeout);

  @override
  Future<String> login() async {
    final res = await _get(_uri('/user'));
    _ok(res);
    final raw = jsonDecode(res.body);
    final login = raw is Map ? '${raw['login'] ?? ''}' : '';
    if (login.isEmpty) throw StateError('Gitee Token 校验失败（读不到账号）');
    return login;
  }

  @override
  Future<RemoteRepo?> repo() async {
    final res = await _get(_uri('/repos/$owner/$repoName'));
    if (res.statusCode == 404) return null;
    _ok(res);
    return _parseRepo(res);
  }

  @override
  Future<RemoteRepo> create() async {
    final me = await login();
    if (owner.toLowerCase() != me.toLowerCase()) {
      throw StateError('Gitee 只能在当前 Token 的账号下新建仓库（$me），'
          '要发到组织请先在 Gitee 建好仓库再填这里');
    }
    final res = await _send('POST', _uri('/user/repos'), {
      'access_token': token,
      'name': repo,
      'private': false,
      'auto_init': true,
      'description': 'AntiSIT 拓展源',
    });
    _ok(res);
    return _parseRepo(res);
  }

  @override
  Future<RemoteFile?> file(String path, {required String branch}) async {
    final res = await _get(_uri(
      '/repos/$owner/$repoName/contents/${_encodePath(path)}',
      {'ref': branch},
    ));
    if (res.statusCode == 404) return null;
    _ok(res);
    final raw = jsonDecode(res.body);
    final item = raw is List && raw.isNotEmpty && raw.first is Map
        ? raw.first as Map
        : (raw is Map ? raw : null);
    if (item == null) return null;
    final content = '${item['content'] ?? ''}';
    List<int>? bytes;
    if (content.isNotEmpty) {
      try {
        bytes = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
      } catch (_) {
        bytes = null;
      }
    }
    return RemoteFile(bytes: bytes, sha: '${item['sha'] ?? ''}');
  }

  @override
  Future<void> putFile(String path, List<int> bytes,
      {required String branch, required String message}) async {
    final existing = await file(path, branch: branch);
    if (existing?.bytes != null && _sameBytes(existing!.bytes!, bytes)) return;
    final body = <String, Object?>{
      'access_token': token,
      'content': base64Encode(bytes),
      'message': message,
      'branch': branch,
    };
    final uri = _uri('/repos/$owner/$repoName/contents/${_encodePath(path)}');
    if (existing != null && existing.sha.isNotEmpty) {
      body['sha'] = existing.sha;
      final res = await _send('PUT', uri, body);
      _ok(res);
    } else {
      final res = await _send('POST', uri, body);
      _ok(res);
    }
  }

  RemoteRepo _parseRepo(http.Response res) {
    final raw = jsonDecode(res.body);
    if (raw is! Map) throw StateError('Gitee 返回的仓库信息看不懂');
    final branch = '${raw['default_branch'] ?? ''}'.trim();
    return RemoteRepo(
      defaultBranch: branch.isEmpty ? 'master' : branch,
      private: raw['private'] == true,
    );
  }

  void _ok(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var msg = 'Gitee 请求失败（HTTP ${res.statusCode}）';
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map) {
        final direct = '${raw['message'] ?? ''}'.trim();
        if (direct.isNotEmpty) {
          msg = 'Gitee：$direct';
        } else if (raw['error'] != null) {
          msg = 'Gitee：${raw['error']}';
        }
      }
    } catch (_) {
      msg = 'Gitee 请求失败（HTTP ${res.statusCode}）：${_shortBody(res)}';
    }
    throw StateError(msg);
  }
}
