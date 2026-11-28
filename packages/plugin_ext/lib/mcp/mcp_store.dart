import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一条 MCP 服务器配置（用户自己填的，只落本机）。
///
/// 为什么只有 HTTP：Android 上没有能跑 `stdio` 子进程的沙箱，MCP 的 stdio 传输在
/// 手机上要么跑不起来、要么等于把任意命令交给拓展——所以这里只支持远程 HTTP
/// （普通 JSON-RPC POST / SSE）这一种，导入时也只接受 http(s) 地址。
class McpServer {
  McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.headers = const {},
    this.enabled = true,
  });

  final String id;
  String name;
  String url;

  /// 额外的请求头（认证用，例如 `Authorization: Bearer ...`）。
  final Map<String, String> headers;
  bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'headers': headers,
        'enabled': enabled,
      };

  static McpServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    final url = '${raw['url'] ?? ''}'.trim();
    if (id.isEmpty || url.isEmpty) return null;
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final k = '${entry.key}'.trim();
        if (k.isEmpty) continue;
        headers[k] = '${entry.value}';
      }
    }
    return McpServer(
      id: id,
      name: '${raw['name'] ?? id}',
      url: url,
      headers: headers,
      enabled: raw['enabled'] != false,
    );
  }
}

/// MCP 服务器清单：本机持久化，和拓展清单一样只存在这台设备上。
class McpStore {
  static const _key = 'plugin.ext.mcp_servers';

  Future<List<McpServer>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final item in list)
          if (McpServer.fromJson(item) case final server?) server,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<McpServer> servers) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode([for (final s in servers) s.toJson()]),
    );
  }

  /// 加一条（同 url 已存在就覆盖名字 / 请求头，不重复堆）。
  Future<List<McpServer>> upsert(McpServer server) async {
    final current = await load();
    final index = current.indexWhere(
      (s) => s.id == server.id || s.url == server.url,
    );
    if (index >= 0) {
      current[index] = server;
    } else {
      current.add(server);
    }
    await save(current);
    return current;
  }

  Future<List<McpServer>> remove(String id) async {
    final current = (await load())..removeWhere((s) => s.id == id);
    await save(current);
    return current;
  }
}
