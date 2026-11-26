import 'package:flutter/material.dart';

import 'ext_bridge_consent.dart';
import 'ext_notification.dart';
import 'extension_item.dart';

/// 通知通道：`notify.*` 的参数解析、弹窗渠道授权与调用。
class ExtNotificationChannel {
  ExtNotificationChannel({
    required this.context,
    required this.extId,
    required this.item,
  });

  final BuildContext context;
  final String extId;
  final ExtensionItem? item;

  Future<Object?> show(Object? args) async {
    final popup = args is Map && args['popup'] == true;
    if (popup) await _consent('notification.popup');
    await ExtNotificationService.instance.show(
      extId: extId,
      extName: item?.name,
      key: _notifyKey(args, required: false),
      title: _notifyTitle(args),
      body: _notifyBody(args),
      popup: popup,
    );
    return true;
  }

  Future<Object?> schedule(Object? args) async {
    if (args is! Map) throw ArgumentError('notify.schedule 要带 {key, title, at}');
    final popup = args['popup'] == true;
    if (popup) await _consent('notification.popup');
    await ExtNotificationService.instance.schedule(
      extId: extId,
      key: _notifyKey(args, required: true)!,
      title: _notifyTitle(args),
      body: _notifyBody(args),
      at: _notifyAt(args),
      popup: popup,
    );
    return true;
  }

  Future<Object?> cancel(Object? args) async {
    await ExtNotificationService.instance
        .cancel(extId: extId, key: _notifyKey(args, required: true)!);
    return true;
  }

  Future<Object?> cancelAll() async {
    await ExtNotificationService.instance.cancelAll(extId: extId);
    return true;
  }

  Future<void> _consent(String capability) => ensureExtConsent(
        context: context,
        extId: extId,
        item: item,
        capability: capability,
      );

  /// 通知标题：必填，给个 200 字上限（系统通知栏也放不下更多）。
  static String _notifyTitle(Object? args) {
    final title = args is Map ? '${args['title'] ?? ''}'.trim() : '';
    if (title.isEmpty) throw ArgumentError('通知要带 title');
    if (title.length > 200) throw ArgumentError('通知 title 最多 200 字');
    return title;
  }

  /// 通知正文：可空；空串按没有正文处理。
  static String? _notifyBody(Object? args) {
    if (args is! Map) return null;
    final body = '${args['body'] ?? ''}'.trim();
    if (body.length > 1000) throw ArgumentError('通知 body 最多 1000 字');
    return body.isEmpty ? null : body;
  }

  /// 拓展自己给的稳定 key：取消 / 覆盖同一条通知靠它。
  static String? _notifyKey(Object? args, {required bool required}) {
    final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
    if (key.isEmpty) {
      if (required) throw ArgumentError('要带 key（取消 / 覆盖同一条通知靠它）');
      return null;
    }
    if (key.length > 100) throw ArgumentError('通知 key 最多 100 字');
    return key;
  }

  /// 定时时刻：ISO 8601 字符串或毫秒时间戳；只接受未来时间。
  static DateTime _notifyAt(Object? args) {
    final raw = args is Map ? args['at'] : null;
    DateTime? at;
    if (raw is num) {
      at = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String && raw.trim().isNotEmpty) {
      at = DateTime.tryParse(raw.trim());
    }
    if (at == null) {
      throw ArgumentError('notify.schedule 要带 at（ISO 8601 时间或毫秒时间戳）');
    }
    if (!at.isAfter(DateTime.now())) throw ArgumentError('at 必须是未来时间');
    return at;
  }
}
