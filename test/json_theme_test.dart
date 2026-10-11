import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「导入 JSON 主题」的验收：
/// * 合法 JSON 解析出主题，缺省 success/danger 给默认值；
/// * 各类坏输入（坏 JSON / 缺字段 / 坏颜色）给出人话报错；
/// * 注册表导入后出现在 themes 里并自动启用；同 id 覆盖；删除回落默认；
/// * 重新 load 能从存档里读回来。
const _validJson = '''
{
  "name": "月白",
  "light": { "bg": "#E3E9F2", "surface": "#FFFFFF", "accent": "#3E639B",
             "gold": "#8A6420", "text": "#16233A" },
  "dark":  { "bg": "#0B1322", "surface": "#111A2B", "accent": "#93B1D4",
             "gold": "#E4B863", "text": "#FFFFFF",
             "success": "#3DDC97", "danger": "#FF6B5E" }
}
''';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('JsonThemePlugin.parse', () {
    test('合法 JSON：解析出名字与两档色板', () {
      final t = JsonThemePlugin.parse(_validJson);
      expect(t.name, '月白');
      expect(t.id, startsWith('custom.'));
      expect(t.palette(Brightness.light).bg, const Color(0xFFE3E9F2));
      expect(t.palette(Brightness.light).accent, const Color(0xFF3E639B));
      expect(t.palette(Brightness.dark).bg, const Color(0xFF0B1322));
      expect(t.palette(Brightness.dark).isDark, isTrue);
    });

    test('缺省 success / danger 用默认绿红', () {
      final t = JsonThemePlugin.parse(_validJson);
      expect(t.palette(Brightness.light).success, const Color(0xFF1E7F46));
      expect(t.palette(Brightness.light).danger, const Color(0xFFC3372B));
      expect(t.palette(Brightness.dark).success, const Color(0xFF3DDC97));
    });

    test('带 id 时用调用方的 id（重复导入按 id 覆盖）', () {
      final t = JsonThemePlugin.parse(_validJson.replaceFirst('"name": "月白"', '"name": "月白", "id": "custom.moon"'));
      expect(t.id, 'custom.moon');
    });

    for (final (label, json, reason) in [
      ('不是 JSON', '{oops', '语法错误要报出来'),
      ('根不是对象', '[1,2]', '根节点该是对象'),
      ('缺 name', '{"light": {}, "dark": {}}', '没名字的主题没法展示'),
      ('缺 light', '{"name": "x"}', '两档色板缺一不可'),
      ('缺色键', '{"name": "x", "light": {"bg": "#FFFFFF"}, "dark": {"bg": "#000000"}}', '五个基础色都要给'),
      ('坏颜色', '{"name": "x", "light": {"bg": "红色", "surface": "#FFF", "accent": "#FFF", "gold": "#FFF", "text": "#FFF"}, "dark": {"bg": "#000", "surface": "#000", "accent": "#000", "gold": "#000", "text": "#000"}}', '颜色值不对要指出来'),
    ]) {
      test('$label：报人话错误', () {
        late Object e;
        var threw = false;
        try {
          JsonThemePlugin.parse(json);
        } catch (err) {
          threw = true;
          e = err;
        }
        expect(threw, isTrue, reason: reason);
        expect(e, isA<FormatException>());
        expect((e as FormatException).message, isNotEmpty);
      });
    }
  });

  group('注册表的自定义主题', () {
    PluginRegistry reg() => PluginRegistry(
          features: const [],
          themes: const [GlassTheme()],
        );

    test('导入后进入 themes 并自动启用', () async {
      final r = reg();
      await r.addTheme(JsonThemePlugin.parse(_validJson));
      expect(r.themes.whereType<JsonThemePlugin>().length, 1);
      expect(r.themes.last.name, '月白');
      expect(r.theme.id, startsWith('custom.'), reason: '导入后自动切换过去');
    });

    test('同 id 再导入是覆盖不是重复', () async {
      final r = reg();
      await r.addTheme(JsonThemePlugin.parse(_validJson.replaceFirst('"name": "月白"', '"name": "月白", "id": "custom.moon"')));
      await r.addTheme(JsonThemePlugin.parse(_validJson.replaceFirst(
          '"name": "月白"', '"name": "月白改", "id": "custom.moon"')));
      expect(r.themes.whereType<JsonThemePlugin>().length, 1);
      expect(r.themes.last.name, '月白改');
    });

    test('删除后回落默认主题', () async {
      final r = reg();
      final t = JsonThemePlugin.parse(_validJson.replaceFirst('"name": "月白"', '"name": "月白", "id": "custom.moon"'));
      await r.addTheme(t);
      await r.removeTheme('custom.moon');
      expect(r.themes.whereType<JsonThemePlugin>(), isEmpty);
      expect(r.theme.id, GlassTheme().id, reason: '正在用的自定义主题被删要回落内置');
    });

    test('持久化：重新 load 读得回来', () async {
      final r = reg();
      await r.addTheme(JsonThemePlugin.parse(_validJson));
      final sp = await SharedPreferences.getInstance();
      // 模拟重启：新注册表从同一份存档读
      final r2 = reg();
      // PluginRegistry.load() 读 SharedPreferences 单例（mock 已存好）
      await r2.load();
      expect(r2.themes.whereType<JsonThemePlugin>().length, 1);
      expect(r2.themes.last.name, '月白');
      expect(r2.theme.id, startsWith('custom.'), reason: '上次选中的自定义主题重启后仍在用');
      expect((sp.getStringList('plugin_custom_themes') ?? const []).length, 1);
    });

    test('存档里有坏条目：跳过不崩', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.plugin_custom_themes': ['{oops', _validJson],
      });
      final r = PluginRegistry(features: const [], themes: const [GlassTheme()]);
      await r.load();
      expect(r.themes.whereType<JsonThemePlugin>().length, 1, reason: '坏条目跳过、好的照常读回');
    });
  });
}
