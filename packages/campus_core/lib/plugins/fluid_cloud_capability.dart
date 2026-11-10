import 'capability.dart';

/// 流体云（ColorOS 流体云 / OriginOS 原子通知 / 澎湃OS 焦点通知）的当前状态。
class FluidCloudInfo {
  const FluidCloudInfo({
    required this.vendor,
    required this.label,
    required this.apiLevel,
    required this.notificationsEnabled,
    required this.exactAlarm,
    required this.promotedSupported,
  });

  /// `coloros` / `originos` / `hyperos` / `other`。
  final String vendor;

  /// 给用户看的系统名：ColorOS / OriginOS / 澎湃OS / 本机系统。
  final String label;

  final int apiLevel;

  /// 通知权限（Android 13+）当前是否允许。
  final bool notificationsEnabled;

  /// 精确闹钟是否已授权；没授权时排期会降级成不精确（差几分钟）。
  final bool exactAlarm;

  /// 系统是否支持 Android 16 的 promoted ongoing（决定能否被系统升格成流体云形态）。
  final bool promotedSupported;

  bool get isKnownVendor => vendor != 'other';

  Map<String, Object?> toJson() => {
        'vendor': vendor,
        'label': label,
        'apiLevel': apiLevel,
        'notificationsEnabled': notificationsEnabled,
        'exactAlarm': exactAlarm,
        'promotedSupported': promotedSupported,
      };

  static FluidCloudInfo fromJson(Map<Object?, Object?> j) => FluidCloudInfo(
        vendor: '${j['vendor'] ?? 'other'}',
        label: '${j['label'] ?? '本机系统'}',
        apiLevel: j['apiLevel'] is num ? (j['apiLevel'] as num).toInt() : 0,
        notificationsEnabled: j['notificationsEnabled'] == true,
        exactAlarm: j['exactAlarm'] == true,
        promotedSupported: j['promotedSupported'] == true,
      );
}

/// 一条「亮起窗口」：到 `startAt - leadMinutes` 亮起，`endAt` 收起。
///
/// 课程通知用它；其它插件要往流体云上放东西也可以复用（比如考试倒计时）。
class FluidCloudWindow {
  const FluidCloudWindow({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.subtitle = '',
    this.leadMinutes = 15,
    this.nextPlace = '',
    this.nextTitle = '',
  });

  final String id;
  final String title;
  final String subtitle;

  /// 开始 / 结束时刻（epoch 毫秒）。
  final int startAt;
  final int endAt;

  /// 提前多少分钟亮起。
  final int leadMinutes;

  /// 下一节课的地点 / 课程名（预览用；排期发出的窗口留空，由原生自己找）。
  final String nextPlace;
  final String nextTitle;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'startAt': startAt,
        'endAt': endAt,
        'leadMinutes': leadMinutes,
        'nextPlace': nextPlace,
        'nextTitle': nextTitle,
      };

  static FluidCloudWindow fromJson(Map<Object?, Object?> j) => FluidCloudWindow(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        startAt: j['startAt'] is num ? (j['startAt'] as num).toInt() : 0,
        endAt: j['endAt'] is num ? (j['endAt'] as num).toInt() : 0,
        leadMinutes: j['leadMinutes'] is num ? (j['leadMinutes'] as num).toInt() : 15,
        nextPlace: '${j['nextPlace'] ?? ''}',
        nextTitle: '${j['nextTitle'] ?? ''}',
      );
}

/// 流体云能力：把常驻进度通知交给系统展示。
///
/// **不需要厂商 SDK**：ColorOS / OriginOS / 澎湃OS 都按系统通知规则接入，
/// Android 16+ 声明 promoted ongoing 后由系统映射到各自的流体云 / 原子通知 / 焦点通知形态；
/// 更早的系统就是一条常驻倒计时通知（通知栏里照常可见）。
abstract class FluidCloudCapability extends PluginCapability {
  /// 当前系统信息（品牌、通知权限、精确闹钟、是否支持 promoted ongoing）。
  Future<FluidCloudInfo> info();

  /// 立刻亮一条（预览 / App 在前台时补亮）。返回 false = 没发出去（通知权限/渠道被关）。
  Future<bool> show(FluidCloudWindow window);

  /// 收起当前这条。
  Future<void> dismiss();

  /// 整批交给系统闹钟排期：到点亮、到点收，App 被杀也生效。返回排上的窗口数。
  Future<int> schedule(List<FluidCloudWindow> windows);

  /// 取消所有已排窗口并收起通知。
  Future<void> clear();

  /// 请求通知权限（Android 13+）。已授权返回 true。
  Future<bool> requestPermission();
}
