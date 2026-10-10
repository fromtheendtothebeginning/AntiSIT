/// 插件对外提供的能力：插件之间**只按「接口 + 提供方插件 id」取用**，谁也不 import 对方的包
/// ——要用另一个插件的功能时，拿到的是这个接口，实现在提供方的包里。
///
/// 取用方式（接口定义在 campus_core，实现在提供方插件包）：
///
/// ```dart
/// final ai = PluginRegistry.I.capability<AiCapability>(PluginIds.ai);
/// if (ai?.available ?? false) { ... }
/// ```
///
/// 提供方没装（包被删 / 被 EXCLUDE）或被用户停用时返回 null，调用方据此降级——
/// 与依赖图上那条「软依赖虚线边」的含义一致。
///
/// **取用处写的那个 id 就是依赖关系**：`tool/gen_plugins.dart` 会把
/// `capability<...>(PluginIds.y)` 扫出来，跟该插件声明的 `dependencies` /
/// `optionalDependencies` 对账，用了却没声明就报错退出。
abstract class PluginCapability {
  /// 实现通常写成 const 常量（直接放进 [PluginBundle.capabilities]）。
  const PluginCapability();
}
