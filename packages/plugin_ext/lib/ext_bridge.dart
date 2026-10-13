import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';
import 'extension_store.dart';

/// 拓展网页能用的接口（方法表见 `docs/extensions.md`，网页侧统一 `antiSIT.call(...)`）：
///
/// | 方法 | 参数 | 返回 |
/// |---|---|---|
/// | `theme` | — | 当前配色的十六进制值（`accent` / `bg` / `card` / `textPrimary` / …） |
/// | `toast` | `{text}` | 弹一条 App 风格的提示 |
/// | `close` | — | 关掉当前网页（回拓展列表） |
/// | `card.setName` | `{text}` | 换卡片上的名称（≤ 20 字；id 不变） |
/// | `card.setDesc` | `{text}` | 换卡片上的简介（≤ 60 字；空串 = 不显示简介） |
/// | `card.setIcon` | `{text}` | 换卡片上的图标（图片网址，或 ≤ 4 字的文字 / emoji；空串 = 用网站 favicon） |
/// | `storage.get` | `{key}` | 该拓展自己存的任意 JSON；没有则 null |
/// | `storage.set` | `{key, value}` | true |
/// | `storage.remove` | `{key}` | true |
///
/// 每个拓展一个实例：绑定自己的 [extId]（数据互相隔离）与打开网页那个 [context]
/// （提示条 / 关页要用）。未知方法一律报错回网页，不静默失败——拓展作者调试时
/// 能立刻看见；用户数据（学号、课表、成绩）**不在**这套接口里，别把用户数据
/// 交给一个用户自己填的网址。
class ExtBridge extends WebBridge {
  ExtBridge({required this.extId, required this.context, ExtensionStore? store})
      : store = store ?? ExtensionStore.I;

  final String extId;
  final BuildContext context;
  final ExtensionStore store;

  @override
  Future<Object?> call(String method, Object? args) async {
    switch (method) {
      case 'theme':
        return _theme();
      case 'toast':
        _toast(args);
        return true;
      case 'close':
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        return true;
      case 'card.setName':
        return _setCard(args, field: 'name');
      case 'card.setDesc':
        return _setCard(args, field: 'desc');
      case 'card.setIcon':
        return _setCard(args, field: 'icon');
      case 'storage.get':
        return store.dataGet(extId, _key(args));
      case 'storage.set':
        if (args is! Map) throw ArgumentError('storage.set 要带 {key, value}');
        await store.dataSet(extId, _key(args), args['value']);
        return true;
      case 'storage.remove':
        await store.dataRemove(extId, _key(args));
        return true;
      default:
        throw ArgumentError('未知接口：$method');
    }
  }

  /// 改自己卡片上的一个字段（名称 / 简介 / 图标），改完落盘，回到列表即可见。
  /// 校验不过直接报错，不静默截断：名称不能空、简介可空（= 不显示）、
  /// 图标要么是图片网址，要么是几个字以内的文字 / emoji。
  Future<Object?> _setCard(Object? args, {required String field}) async {
    if (args is! Map) throw ArgumentError('card.set$field 要带 {text}');
    final text = '${args['text'] ?? ''}'.trim();
    if (field == 'name') {
      if (text.isEmpty) throw ArgumentError('名称不能为空');
      if (text.length > ExtensionItem.nameMaxLength) {
        throw ArgumentError('名称最多 ${ExtensionItem.nameMaxLength} 个字');
      }
    } else if (field == 'icon') {
      // 图片网址不受「几个字」的限制，这里只给个长度上限
      if (text.length > (_isUrl(text) ? 300 : ExtensionItem.iconTextMaxLength)) {
        throw ArgumentError(_isUrl(text)
            ? '图标网址过长'
            : '图标最多 ${ExtensionItem.iconTextMaxLength} 个字（要用图片就填 http/https 网址）');
      }
    } else if (text.length > ExtensionItem.descMaxLength) {
      throw ArgumentError('简介最多 ${ExtensionItem.descMaxLength} 个字');
    }
    final ok = await store.setCard(extId,
        name: field == 'name' ? text : null,
        desc: field == 'desc' ? text : null,
        icon: field == 'icon' ? text : null);
    if (!ok) throw ArgumentError('这条拓展不在清单里，改不了卡片');
    return true;
  }

  static bool _isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  /// 当前配色：拓展照着 App 的样子画，不用自己猜深浅色。
  Map<String, Object?> _theme() => {
        'isDark': SemColors.isDark,
        'accent': _hex(SemColors.accent),
        'accentSoft': _hex(SemColors.accentSoft),
        'bg': _hex(SemColors.bg),
        'card': _hex(SemColors.card),
        'border': _hex(SemColors.border),
        'textPrimary': _hex(SemColors.textPrimary),
        'textSecondary': _hex(SemColors.textSecondary),
        'textMuted': _hex(SemColors.textMuted),
        'danger': _hex(SemColors.danger),
        'success': _hex(SemColors.success),
      };

  /// '#RRGGBB'（与主题导入导出用同一套写法）。
  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  void _toast(Object? args) {
    if (!context.mounted) return;
    final text = args is Map ? '${args['text'] ?? ''}' : '$args';
    if (text.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating));
  }

  static String _key(Object? args) {
    final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
    if (key.isEmpty) throw ArgumentError('要带 key');
    return key;
  }
}
