import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MCP 服务器清单：存 / 读 / 同名覆盖 / 删除，都只落本机。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认空清单；存进去读回来一致', () async {
    final store = McpStore();
    expect(await store.load(), isEmpty);

    await store.save([
      McpServer(
        id: 'a',
        name: '示例服务器',
        url: 'https://example.com/mcp',
      ),
    ]);
    final loaded = await store.load();
    expect(loaded.length, 1);
    expect(loaded.first.name, '示例服务器');
    expect(loaded.first.url, 'https://example.com/mcp');
    expect(loaded.first.enabled, isTrue);
  });

  test('同 url 再加一次是覆盖，不堆两条', () async {
    final store = McpStore();
    await store.upsert(McpServer(
      id: 'a',
      name: '旧名字',
      url: 'https://x.example.com/mcp',
    ));
    final after = await store.upsert(McpServer(
      id: 'b',
      name: '新名字',
      url: 'https://x.example.com/mcp',
    ));
    expect(after.length, 1, reason: '同一个地址不该堆成两台');
    expect(after.first.name, '新名字');
  });

  test('删除只去掉那一条', () async {
    final store = McpStore();
    await store.upsert(McpServer(id: 'a', name: 'A', url: 'https://a.example.com/mcp'));
    await store.upsert(McpServer(id: 'b', name: 'B', url: 'https://b.example.com/mcp'));
    final left = await store.remove('a');
    expect(left.map((s) => s.id), ['b']);
  });

  test('存档损坏时当成空清单，不炸', () async {
    SharedPreferences.setMockInitialValues({
      'plugin.ext.mcp_servers': '这不是 json',
    });
    final store = McpStore();
    expect(await store.load(), isEmpty);
  });

  test('请求头原样保留（认证靠它）', () async {
    final store = McpStore();
    await store.upsert(McpServer(
      id: 'a',
      name: 'A',
      url: 'https://a.example.com/mcp',
      headers: const {'Authorization': 'Bearer abc'},
    ));
    final loaded = await store.load();
    expect(loaded.first.headers['Authorization'], 'Bearer abc');
  });
}
