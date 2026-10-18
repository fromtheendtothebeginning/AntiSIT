import 'dart:io';

import 'package:crypto/crypto.dart';

import '../bundle_import.dart';
import '../extension_item.dart';
import '../extension_store.dart';
import 'market_entry.dart';
import 'market_source.dart';

/// 把市场里的条目装进本地清单。
///
/// 装 = 下载 → **校验 sha256** → 解压 → 入列。校验在解压**之前**，哈希不对连文件都不落盘。
/// 更新就是再装一次：拓展 id 不变，所以解压目录被换掉、而它的数据
/// （`plugin.ext.data.<id>.*`）留着——记的设置、历史都不会因为更新丢掉。
class MarketInstaller {
  MarketInstaller({ExtensionStore? store, MarketSource? source})
      : store = store ?? ExtensionStore.I,
        source = source ?? MarketSource.I;

  final ExtensionStore store;
  final MarketSource source;

  ExtensionItem? installed(String id) {
    for (final e in store.items) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 市场里的这条装没装过。
  bool isInstalled(String id) => installed(id) != null;

  /// 装过且有新版（或同版本内容变了）。
  bool hasUpdate(MarketEntry entry) {
    final have = installed(entry.id);
    if (have == null) return false;
    return marketHasUpdate(
      installedVersion: have.version,
      installedSha: have.sha256,
      entry: entry,
    );
  }

  /// 装 / 更新一条。
  ///
  /// * `bundle`：下载 zip → 校验 sha256 → 解压 → 入列（更新时保留卡片上改过的名字 / 简介 / 图标）；
  /// * `web`：不下载东西，只记一条网址（站点自己会变，没有版本可更新）。
  ///
  /// 抛 [StateError] 时消息可以直接给用户看（哈希不对 / 包坏了 / 与内置冲突）。
  Future<ExtensionItem> install(MarketEntry entry) async {
    if (store.isBuiltin(entry.id)) {
      throw StateError('「${entry.name}」的 id 与内置拓展冲突（${entry.id}），装不了');
    }
    final have = installed(entry.id);

    if (!entry.isBundle) {
      if (have != null) return have; // 网址型：装过就是装过
      final item = ExtensionItem(
        id: entry.id,
        name: entry.name,
        url: entry.url,
        desc: entry.desc,
        icon: entry.icon,
        permissions: entry.permissions,
        fromMarket: true,
      );
      await store.add(item);
      return item;
    }

    final bytes = await source.download(entry.zip);
    final actual = sha256.convert(bytes).toString();
    if (actual != entry.sha256) {
      throw StateError('下载到的内容和市场记录的不一致（可能被改过 / 没下完），已放弃安装');
    }

    final dir = await store.bundleDir(entry.id);
    final ExtBundle bundle;
    try {
      bundle = extractBundle(bytes: bytes, dir: dir);
    } on FormatException catch (e) {
      throw StateError('这个拓展包有问题：${e.message}');
    } on FileSystemException catch (e) {
      throw StateError('解压失败（${e.message}）');
    }

    final ExtensionItem item;
    if (have == null) {
      item = ExtensionItem(
        id: entry.id,
        name: entry.name,
        url: bundle.entry,
        desc: entry.desc,
        icon: entry.icon,
        bundled: true,
        version: entry.version,
        sha256: entry.sha256,
        permissions: entry.permissions,
        fromMarket: true,
      );
      await store.add(item);
    } else {
      // 更新：名字 / 简介 / 图标留着（那是用户在卡片上改过的），只换内容与版本
      item = have.copyWith(
        url: bundle.entry,
        bundled: true,
        version: entry.version,
        sha256: entry.sha256,
        permissions: entry.permissions,
        fromMarket: true,
      );
      await store.update(item);
    }
    return item;
  }

  /// 卸载：清单条目、解压目录、它的数据一起清（与拓展页里的删除同一个动作）。
  Future<void> uninstall(String id) => store.remove(id);
}
