import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mcp_store.dart';

/// 一台 MCP 服务器上的一个工具（`tools/list` 的结果）。
class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

/// MCP 客户端：只做「列工具 / 调工具」两件事（HTTP JSON-RPC）。
///
/// 传输只用 Streamable HTTP（`POST` 一进一出；服务端若回 SSE 也照收）。
/// stdio 在 Android 上等于让拓展跑任意命令，不做。
class McpClient {
  McpClient({required this.server, http.Client? client})
      : _client = client ?? http.Client();

  final McpServer server;
  final http.Client _client;

  static const _protocolVersion = '2025-06-18';

  int _nextId = 1;
  String? _sessionId;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'accept': 'application/json, text/event-stream',
        if (_sessionId != null) 'mcp-session-id': _sessionId!,
        ...server.headers,
      };

  Uri get _endpoint => Uri.parse(server.url);

  /// 发一个 JSON-RPC 请求并等结果；出错抛 [McpError]。
  Future<dynamic> _rpc(String method, [Map<String, dynamic>? params]) async {
    final id = _nextId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    http.Response response;
    try {
      response = await _client
          .post(_endpoint, headers: _headers, body: body)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw McpError('MCP 服务器 ${server.name} 响应超时');
    } catch (e) {
      throw McpError('连不上 MCP 服务器 ${server.name}：$e');
    }
    // Streamable HTTP 会带会话 id；后续请求要回带，否则服务器认不出这一轮
    final sid = response.headers['mcp-session-id'];
    if (sid != null && sid.isNotEmpty) _sessionId = sid;
    if (response.statusCode >= 400) {
      throw McpError('MCP 服务器 ${server.name} 返回 HTTP ${response.statusCode}');
    }
    final text = response.body.trim();
    if (text.isEmpty) throw McpError('MCP 服务器 ${server.name} 没有返回内容');
    final payload = text.startsWith('event:') || text.startsWith('data:')
        ? _parseSse(text)
        : jsonDecode(text);
    final map = payload is Map ? payload : const {};
    if (map['error'] != null) {
      final err = map['error'];
      final message = err is Map ? '${err['message'] ?? err}' : '$err';
      throw McpError('MCP 返回错误：$message');
    }
    return map['result'];
  }

  /// 从 SSE 流里取最后一个 data 行（JSON-RPC 的响应就在里面）。
  static dynamic _parseSse(String body) {
    dynamic last;
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final chunk = line.substring(5).trim();
      if (chunk.isEmpty || chunk == '[DONE]') continue;
      try {
        last = jsonDecode(chunk);
      } catch (_) {}
    }
    if (last == null) throw McpError('MCP 的 SSE 响应里没有 JSON');
    return last;
  }

  /// 握手：initialize → 记下会话 → 发 initialized 通知。
  Future<void> initialize() async {
    final result = await _rpc('initialize', {
      'protocolVersion': _protocolVersion,
      'capabilities': const <String, dynamic>{},
      'clientInfo': const {'name': 'AntiSIT', 'version': '1.48'},
    });
    final info = result is Map ? result : const {};
    // 有的服务器会降级协议版本：不强求一致，能列工具就行
    final serverName = info['serverInfo'] is Map
        ? '${(info['serverInfo'] as Map)['name'] ?? server.name}'
        : server.name;
    _serverName = serverName;
    await _notify('notifications/initialized');
  }

  String? _serverName;
  String get serverName => _serverName ?? server.name;

  Future<void> _notify(String method) async {
    // 通知没有 id，也不该等结果：失败就算了（部分实现直接返回 202 空体）
    try {
      await _client
          .post(
            _endpoint,
            headers: _headers,
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': method,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// 列工具；服务器没实现 tools 能力就返回空表。
  Future<List<McpTool>> listTools() async {
    final result = await _rpc('tools/list');
    final list = result is Map ? (result['tools'] as List?) ?? const [] : const [];
    return [
      for (final raw in list)
        if (raw is Map && raw['name'] != null)
          McpTool(
            name: '${raw['name']}',
            description: '${raw['description'] ?? ''}',
            inputSchema: raw['inputSchema'] is Map
                ? (raw['inputSchema'] as Map).cast<String, dynamic>()
                : const {'type': 'object', 'properties': <String, dynamic>{}},
          ),
    ];
  }

  /// 调一个工具，返回文本化结果。
  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    final result = await _rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final map = result is Map ? result : const {};
    final content = map['content'];
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map && item['text'] != null) {
          parts.add('${item['text']}');
        }
      }
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return jsonEncode(result);
  }

  void close() => _client.close();
}

/// MCP 调用失败的统一异常（文案直接给用户看）。
class McpError implements Exception {
  McpError(this.message);
  final String message;
  @override
  String toString() => message;
}
