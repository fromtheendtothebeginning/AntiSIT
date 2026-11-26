import 'capability.dart';

/// 「流体云课程通知」插件的能力：课表一改就重算流体云排期。
abstract class CourseCloudCapability extends PluginCapability {
  /// 按最新课表重算课程窗口（插件没装 / 被停用时注册表查不到，调用方跳过即可）。
  Future<void> sync();
}
