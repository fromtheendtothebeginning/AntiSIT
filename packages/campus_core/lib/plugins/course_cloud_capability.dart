import 'capability.dart';

/// 「流体云课程通知」插件的能力：课表一改就重算流体云排期。
///
/// 课表保存在 [TimetableStore] 里，它不知道流体云插件的存在；保存完顺手调一下这个
/// 能力（插件没装 / 被停用时注册表查不到，跳过就行），课程窗口就跟着最新课表走。
abstract class CourseCloudCapability extends PluginCapability {
  Future<void> sync();
}
