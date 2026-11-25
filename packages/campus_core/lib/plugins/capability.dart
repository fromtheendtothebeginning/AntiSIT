/// 插件对外提供的能力：插件之间只按「接口 + 提供方插件 id」取用，谁也不 import 对方的包。
///
/// 取用处的 id 就是依赖关系：`tool/gen_plugins.dart` 会扫描 `capability<...>(PluginIds.y)`
/// 并与声明对账，用了却没声明就报错；提供方没装 / 被停用时返回 null，调用方据此降级。
abstract class PluginCapability {
  /// 实现通常写成 const 常量（直接放进 [PluginBundle.capabilities]）。
  const PluginCapability();
}
