import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart';

import '../bundle_import.dart';
import '../extension_item.dart';
import '../extension_store.dart';
import 'ext_dependency_plan.dart';
import 'market_entry.dart';
import 'market_source.dart';
import 'market_sources.dart';

/// 把市场里的条目装进本地清单：下载 → **校验 sha256** → 解压 → 入列。
///
/// 校验在解压**之前**（哈希不对连文件都不落盘）；更新就是再装一次，id 不变所以
/// 拓展自己的数据（`plugin.ext.data.<id>.*`）留着。
class MarketInstaller {
  MarketInstaller({ExtensionStore? store, MarketSource? source})
    : store = store ?? ExtensionStore.I,
      source = source ?? MarketSource.I;

  final ExtensionStore store;
  final MarketSource source;

  /// 下载某条拓展的内容：官方目录走内置镜像，第三方源走条目自己的地址。
  /// 测试里可以换掉它（默认实现两条路都覆盖了）。
  Future<List<int>> Function(MarketEntry entry)? downloadOverride;

  Future<List<int>> download(MarketEntry entry) {
    final custom = downloadOverride;
    if (custom != null) return custom(entry);
    if (!entry.official) return ExtSourceStore.I.download(entry);
    return source.download(entry.zip);
  }

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

  /// 装 / 更新一条：`bundle` 走下载校验解压入列，`web` 只记一条网址。
  ///
  /// 抛 [StateError] 时消息可以直接给用户看（App 版本不够 / 哈希不对 / 包坏了 /
  /// 与内置冲突）；版本门在这里再拦一道，「全部更新」这类批量路径绕不过去。
  Future<ExtensionItem> install(MarketEntry entry) async {
    // 演示模式：假拓展没有真实包可下，直接把「已装版本」推进到目录版本。
    // 内容路径写成 demo:// 标记（真去打开会提示不存在，演示流程不依赖它）。
    if (AppState.I.demo && entry.id.startsWith('demo-')) {
      final have = installed(entry.id);
      final item =
          (have ??
                  ExtensionItem(
                    id: entry.id,
                    name: entry.name,
                    url: '',
                    bundled: true,
                  ))
              .copyWith(
                url: 'demo:///main.js',
                bundled: true,
                runtime: ExtensionItem.runtimeCordis,
                version: entry.version,
                sha256: entry.sha256,
                permissions: entry.permissions,
                fromMarket: true,
                sourceId: entry.sourceId,
                minAppVersion: entry.minAppVersion,
              );
      if (have == null) {
        await store.add(item);
      } else {
        await store.update(item);
      }
      return item;
    }
    final app = await ExtensionItem.appVersionLoader();
    if (entry.needsNewerApp(app)) {
      throw StateError(
        '「${entry.name}」需要 App ≥${entry.minAppVersion}，请先升级 App',
      );
    }
    if (store.isBuiltin(entry.id)) {
      throw StateError('「${entry.name}」的 id 与内置拓展冲突（${entry.id}），装不了');
    }
    final have = installed(entry.id);
    // 同一个 id 只能由一个源管：否则第三方源可以拿官方拓展的 id 把已装的内容顶掉
    if (have != null && have.sourceId != entry.sourceId) {
      final from = have.sourceId.isEmpty ? '官方目录' : have.sourceId;
      final to = entry.sourceId.isEmpty ? '官方目录' : entry.sourceId;
      throw StateError(
        '这条拓展（${entry.id}）已经由「$from」装着了，'
        '不能换到「$to」上装——要先卸载它',
      );
    }

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
        sourceId: entry.sourceId,
        minAppVersion: entry.minAppVersion,
      );
      await store.add(item);
      return item;
    }

    if (entry.isLegacyBundle) {
      throw StateError('这个拓展还是旧版网页格式（目录里没有 runtime: cordis），请等作者升级后再装');
    }
    final bytes = await download(entry);
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
    if (bundle.manifest.id != entry.id) {
      throw StateError(
        '拓展包里的 id（${bundle.manifest.id}）与市场记录（${entry.id}）不一致，已放弃安装',
      );
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
        runtime: ExtensionItem.runtimeCordis,
        version: entry.version,
        sha256: entry.sha256,
        permissions: entry.permissions,
        fromMarket: true,
        sourceId: entry.sourceId,
        minAppVersion: entry.minAppVersion,
      );
      await store.add(item);
    } else {
      // 更新：名字 / 简介 / 图标留着（那是用户在卡片上改过的），只换内容与版本
      item = have.copyWith(
        url: bundle.entry,
        bundled: true,
        runtime: ExtensionItem.runtimeCordis,
        version: entry.version,
        sha256: entry.sha256,
        permissions: entry.permissions,
        fromMarket: true,
        sourceId: entry.sourceId,
        minAppVersion: entry.minAppVersion,
      );
      await store.update(item);
    }
    return item;
  }

  /// 已装拓展的 id → 版本（算依赖是否满足用）。
  Map<String, String> installedVersions() => {
    for (final e in store.items)
      if (!e.builtin) e.id: e.version,
  };

  /// 这个目录条目要装的东西（含依赖），按拓扑序排好。
  ///
  /// 应用插件会自动带上 `requires` 里声明的依赖插件（以及它们自己的依赖）；
  /// 目录里找不到的依赖会出现在 [ExtInstallPlan.unresolved]（此时拒绝安装）。
  ExtInstallPlan planFor(
    MarketEntry entry, {
    Map<String, MarketEntry>? catalog,
  }) {
    // 目录里的全部条目（调用方一般传「官方 + 第三方源」的合并列表）
    final byId = <String, MarketEntry>{
      for (final e in (catalog ?? const <String, MarketEntry>{}).values)
        e.id: e,
      entry.id: entry,
    };
    return planExtInstall(
      target: parseExtNodes([entry]).single,
      catalog: {
        for (final e in byId.values) e.id: parseExtNodes([e]).single,
      },
      installed: installedVersions(),
    );
  }

  /// 安装计划里的所有条目（按顺序逐个下载）：应用插件先装依赖，再装自己。
  ///
  /// 下载进度通过 [onStep] 报出去（树状下载界面按它上色）；单个失败不挡后面的，
  /// 但缺了依赖的应用插件不会被装（见下面的 depends 检查）。
  Future<ExtInstallReport> installPlan(
    ExtInstallPlan plan, {
    void Function(ExtTreeRow row)? onStep,
  }) async {
    final failed = <String>[];
    final done = <String>[];
    for (var i = 0; i < plan.order.length; i++) {
      final node = plan.order[i];
      final already =
          installedVersions().containsKey(node.id) &&
          !plan.conflicts.contains(node.id);
      if (already) {
        onStep?.call(
          ExtTreeRow(
            node: node,
            depth: 0,
            needed: false,
            state: ExtTreeState.skipped,
          ),
        );
        continue;
      }
      onStep?.call(
        ExtTreeRow(
          node: node,
          depth: 0,
          needed: true,
          state: ExtTreeState.downloading,
        ),
      );
      try {
        await install(node.entry);
        done.add(node.id);
        onStep?.call(
          ExtTreeRow(
            node: node,
            depth: 0,
            needed: true,
            state: ExtTreeState.done,
          ),
        );
      } catch (err) {
        failed.add('${node.name}：$err');
        onStep?.call(
          ExtTreeRow(
            node: node,
            depth: 0,
            needed: true,
            state: ExtTreeState.failed,
            error: '$err',
          ),
        );
      }
    }
    return ExtInstallReport(done: done, failures: failed);
  }

  /// 卸载：清单条目、解压目录、它的数据一起清（与拓展页里的删除同一个动作）。
  Future<void> uninstall(String id) => store.remove(id);
}

/// 一次「装应用插件 + 它的依赖」的结果。
class ExtInstallReport {
  const ExtInstallReport({required this.done, required this.failures});

  /// 装成功的 id。
  final List<String> done;

  /// 失败条目（每行一句给用户看的话）。
  final List<String> failures;

  bool get ok => failures.isEmpty;
}
