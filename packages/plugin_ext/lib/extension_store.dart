import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'builtin_extensions.dart';
import 'ext_notification.dart';
import 'extension_item.dart';

/// 拓展清单 + 每个拓展自己的键值存储。
///
/// 清单 = [kBuiltinExtensions]（编译前固定的，随包发布、不落盘）+ 用户自己加的
/// （落在 `plugin.ext.items`）。每个拓展的键值数据落在 `plugin.ext.data.<id>.*`；
/// 压缩包导入的解压文件落在 `<文档目录>/ext/<id>/`。页面监听它重建。
class ExtensionStore extends ChangeNotifier {
  ExtensionStore();

  /// 宿主启动时换成真实实例；测试里换成干净的（与 `PluginRegistry.I` 同一个套路）。
  static ExtensionStore I = ExtensionStore();

  /// 编译前固定的内置拓展（默认就是源码里的 [kBuiltinExtensions]；
  /// 单测里可以替换成临时清单来验「内置不可删改」）。
  static List<ExtensionItem> builtins = kBuiltinExtensions;

  static const String _kItems = 'plugin.ext.items';
  static const String _kOrder = 'plugin.ext.order';
  static const String _kSizes = 'plugin.ext.sizes';
  static const String _kHideUrls = 'plugin.ext.hide_urls';
  static const String _kBuiltinCard = 'plugin.ext.builtin_card';
  static const String _kDataPrefix = 'plugin.ext.data.';

  List<ExtensionItem> _items = const [];

  /// 接口给**内置拓展**改的卡片显示值（extId → {name / desc / icon}）。
  /// 内置项本身不落盘（清单在源码里，见 [builtins]），所以它们的接口改动只能另存一处；
  /// 用户自己加的拓展不需要这一层——接口直接改清单条目（见 [setCard]）。
  Map<String, Map<String, String>> _builtinCard = {};

  /// 卡片的自定义排序（按拓展 id 记）：空 = 默认顺序（内置在前，其后按添加先后）。
  /// 增删拓展都不用改它——没排到的按原顺序接在后面，已删的留在里面也无害。
  List<String> _order = const [];

  /// 卡片的自定义尺寸（按拓展 id 记）：空 = 全部默认 2x3（半屏宽 × 常规高）。
  /// 和排序一样，没记到的用默认值，已删的条目在删除 / 读盘时清掉。
  Map<String, GridCardSize> _sizes = <String, GridCardSize>{};

  /// 当前的拓展清单（副本，外部改不动）。默认内置排在前面，用户拖过排序后按
  /// [_order] 排（见 [setOrder]）。内置项已套上接口覆盖值：调用方拿到的一律是
  /// **卡片上实际显示**的那份。
  List<ExtensionItem> get items => List.unmodifiable(_applyOrder([
        for (final e in _items) e.builtin ? _withBuiltinCard(e) : e,
      ]));

  /// 按 [_order] 重排：排过的在前（按存的先后），没排过的保持原顺序接在后面。
  List<ExtensionItem> _applyOrder(List<ExtensionItem> all) {
    if (_order.isEmpty) return all;
    final pos = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    final ordered = [for (final e in all) if (pos.containsKey(e.id)) e]
      ..sort((a, b) => pos[a.id]!.compareTo(pos[b.id]!));
    return [...ordered, for (final e in all) if (!pos.containsKey(e.id)) e];
  }

  /// 保存自定义排序（按显示顺序传 id）；传空 = 恢复默认顺序。
  Future<void> setOrder(List<String> ids) async {
    _order = List.unmodifiable(ids);
    final sp = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await sp.remove(_kOrder);
    } else {
      await sp.setStringList(_kOrder, ids);
    }
    notifyListeners();
  }

  /// 拓展卡片的网格尺寸：没改过就是默认的 2x3。
  GridCardSize sizeOf(String id) => _sizes[id] ?? GridCardSize.standard;

  /// 是否有用户改过尺寸的拓展卡片（排序页据此决定要不要露出「重置大小」）。
  bool get hasCustomSizes => _sizes.isNotEmpty;

  /// 保存某张拓展卡片的尺寸。传 [GridCardSize.standard] = 恢复默认（不会多存一条）。
  Future<void> setSize(String id, GridCardSize size) async {
    if (!_items.any((e) => e.id == id)) return;
    final next = Map<String, GridCardSize>.of(_sizes);
    if (size == GridCardSize.standard) {
      next.remove(id);
    } else {
      next[id] = size;
    }
    final same = next.length == _sizes.length &&
        next.entries.every((e) => _sizes[e.key] == e.value);
    if (same) return;
    _sizes = next;
    await _persistSizes();
    notifyListeners();
  }

  /// 把所有拓展卡片恢复到默认尺寸。
  Future<void> resetSizes() async {
    if (_sizes.isEmpty) return;
    _sizes = <String, GridCardSize>{};
    await (await SharedPreferences.getInstance()).remove(_kSizes);
    notifyListeners();
  }

  Future<void> _persistSizes() async {
    final sp = await SharedPreferences.getInstance();
    if (_sizes.isEmpty) {
      await sp.remove(_kSizes);
      return;
    }
    await sp.setString(_kSizes, jsonEncode({
      for (final entry in _sizes.entries) entry.key: entry.value.key,
    }));
  }

  /// 读尺寸表：坏数据 / 认不出的尺寸都按默认处理，不把整页带崩。
  static Map<String, GridCardSize> _parseSizes(String? raw) {
    if (raw == null || raw.isEmpty) return <String, GridCardSize>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, GridCardSize>{};
      return {
        for (final entry in decoded.entries)
          if (entry.value is String)
            '${entry.key}': GridCardSize.parse(entry.value),
      };
    } catch (e) {
      debugPrint('[ext] 卡片尺寸解析失败已忽略：$e');
      return <String, GridCardSize>{};
    }
  }

  /// 隐藏全部网址（拓展页右上角那一个总开关）：卡片上直接不显示网址那一行。
  /// 编辑 / 详情里始终看得到，不然就没法改。
  bool hideUrls = false;

  /// 是否已经从本地读过一次（页面据此决定要不要 load）。
  bool loaded = false;

  /// 内置拓展（编译前固定）：用户端不给删、不给改。
  bool isBuiltin(String id) => builtins.any((e) => e.id == id);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _items = [
      ...builtins,
      for (final raw in sp.getStringList(_kItems) ?? const <String>[])
        ..._tryParseOne(raw),
    ];
    _order = sp.getStringList(_kOrder) ?? const [];
    hideUrls = sp.getBool(_kHideUrls) ?? false;
    _builtinCard = _parseBuiltinCard(sp.getString(_kBuiltinCard));
    // 尺寸只留清单里还存在的拓展；默认尺寸没有存的必要
    final alive = {for (final e in _items) e.id};
    _sizes = _parseSizes(sp.getString(_kSizes))
      ..removeWhere((id, size) =>
          !alive.contains(id) || size == GridCardSize.standard);
    // 演示模式：种一条「市场装的旧版」假拓展，配合市场里的演示目录演示
    // 「可更新 → 点卡片跳市场 → 更新」全流程；退出演示时清掉 demo-* 条目。
    if (AppState.I.demo) {
      if (!_items.any((e) => e.id == 'demo-note')) {
        _items = [..._items, _demoInstalledNote()];
        await _persist();
      }
    } else if (_items.any((e) => e.id.startsWith('demo-'))) {
      _items = [for (final e in _items) if (!e.id.startsWith('demo-')) e];
      await _persist();
    }
    loaded = true;
    notifyListeners();
  }

  /// 演示用的「已装 v1.0.0」记事本（市场目录里是 v2.0.0，所以显示可更新）。
  static ExtensionItem _demoInstalledNote() => const ExtensionItem(
        id: 'demo-note',
        name: '演示记事本',
        url: 'demo://demo-note/main.js',
        desc: '演示模式专用的假拓展（市场里有 v2.0.0 更新）',
        icon: '📒',
        bundled: true,
        runtime: ExtensionItem.runtimeCordis,
        version: '1.0.0',
        sha256: 'demo-note-1',
        permissions: ['storage'],
        fromMarket: true,
      );

  Future<void> setHideUrls(bool v) async {
    if (hideUrls == v) return;
    hideUrls = v;
    await (await SharedPreferences.getInstance()).setBool(_kHideUrls, v);
    notifyListeners();
  }

  Future<void> add(ExtensionItem item) async {
    _items = [..._items, item];
    await _persist();
    notifyListeners();
  }

  Future<void> update(ExtensionItem item) async {
    if (isBuiltin(item.id)) return; // 内置的改动由发行方在源码清单里做
    _items = [for (final e in _items) e.id == item.id ? item : e];
    await _persist();
    notifyListeners();
  }

  /// 删除：内置的不给删；压缩包导入的连同解压出来的文件一起清掉，
  /// 它的键值数据（`plugin.ext.data.<id>.*`）也一起清——删除弹窗就是这么跟用户说的。
  Future<void> remove(String id) async {
    if (isBuiltin(id)) return;
    final gone = [for (final e in _items) if (e.id == id) e];
    _items = [for (final e in _items) if (e.id != id) e];
    await _persist();
    for (final e in gone) {
      if (e.bundled) await _deleteBundle(e.id);
    }
    // 卸载时把它排过的通知一起撤掉（非移动端 / 权限异常不该挡住卸载）
    try {
      await ExtNotificationService.instance.cancelAll(extId: id);
    } catch (_) {}
    if (_sizes.remove(id) != null) await _persistSizes();
    await clearData(id);
    notifyListeners();
  }

  /// 换掉某条拓展卡片上的显示值（拓展网页用 `card.setName` / `card.setDesc` /
  /// `card.setIcon` 接口改自己的卡片，见 [ExtBridge]）。
  /// 找不到这条拓展 → false（调用方据此报错）。
  ///
  /// 用户自己加的拓展直接改清单条目——用户在 App 里的编辑与接口写的是同一条数据，
  /// 后写的生效；内置拓展的改动落在 [ExtensionStore._builtinCard] 覆盖层里
  /// （覆盖只影响卡片显示，不影响它在源码清单里的定义）。
  Future<bool> setCard(String id, {String? name, String? desc, String? icon}) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    if (!_items[i].builtin) {
      await update(_items[i].withCard(name: name, desc: desc, icon: icon));
      return true;
    }
    final merged = {...?_builtinCard[id]};
    if (name != null) merged['name'] = name;
    if (desc != null) merged['desc'] = desc;
    if (icon != null) merged['icon'] = icon;
    _builtinCard = {..._builtinCard, id: merged};
    await _persistBuiltinCard();
    notifyListeners();
    return true;
  }

  /// 给内置项套上接口覆盖值（没被接口改过的字段仍用清单里的值）。
  ExtensionItem _withBuiltinCard(ExtensionItem e) {
    final o = _builtinCard[e.id];
    if (o == null || o.isEmpty) return e;
    return e.withCard(name: o['name'], desc: o['desc'], icon: o['icon']);
  }

  Future<void> _persistBuiltinCard() async {
    await (await SharedPreferences.getInstance())
        .setString(_kBuiltinCard, jsonEncode(_builtinCard));
  }

  /// 读覆盖层：坏数据整份忽略（不让它把拓展列表带崩）。
  static Map<String, Map<String, String>> _parseBuiltinCard(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.value is Map)
            '${e.key}': {
              for (final f in (e.value as Map).entries)
                if (f.value is String) '${f.key}': f.value as String,
            },
      };
    } catch (err) {
      debugPrint('[ext] 卡片覆盖值解析失败已忽略：$err');
      return {};
    }
  }

  // ==================== 压缩包导入 ====================

  /// 拓展解压目录的根目录从哪儿来（`<文档目录>/ext/<id>`）。
  /// 单测里 path_provider 没有实现，所以留一个可替换的取目录函数
  /// （与 `SiteIcon.loader`、`ExtensionStore.I` 同一个套路）。
  static Future<String> Function() documentsDirectory =
      () async => (await getApplicationDocumentsDirectory()).path;

  /// 某个拓展的解压根目录：`<文档目录>/ext/<id>`。
  Future<String> bundleDir(String id) async => '${await documentsDirectory()}/ext/$id';

  Future<void> _deleteBundle(String id) async {
    try {
      final dir = Directory(await bundleDir(id));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      debugPrint('[ext] 清理压缩包目录失败：$e');
    }
  }

  /// 删掉某个拓展的解压目录（导入取消时清刚解出来的文件用）。
  Future<void> deleteBundleDir(String id) => _deleteBundle(id);

  // ==================== 拓展自己的存储（按拓展 id 隔离）====================

  Future<Object?> dataGet(String extId, String key) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('$_kDataPrefix$extId.$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw; // 不是 JSON 就原样给回去
    }
  }

  Future<void> dataSet(String extId, String key, Object? value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$_kDataPrefix$extId.$key', jsonEncode(value));
  }

  Future<void> dataRemove(String extId, String key) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('$_kDataPrefix$extId.$key');
  }

  /// 清掉某条拓展的全部键值数据（删除拓展时用）。返回清掉的条数。
  Future<int> clearData(String extId) async {
    final sp = await SharedPreferences.getInstance();
    final prefix = '$_kDataPrefix$extId.';
    final keys = [for (final k in sp.getKeys()) if (k.startsWith(prefix)) k];
    for (final k in keys) {
      await sp.remove(k);
    }
    return keys.length;
  }

  // ==================== 落盘 ====================

  /// 只写用户自己加的（内置的在源码清单里，不落盘——改清单升级 App 就生效）。
  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kItems, [
      for (final e in _items)
        if (!e.builtin) jsonEncode(e.toJson()),
    ]);
  }

  /// 单条坏数据只跳过它自己，别把整张清单带崩。
  static List<ExtensionItem> _tryParseOne(String raw) {
    try {
      return [ExtensionItem.parse(jsonDecode(raw))];
    } catch (e) {
      debugPrint('[ext] 拓展条目解析失败已跳过：$e');
      return const [];
    }
  }
}
