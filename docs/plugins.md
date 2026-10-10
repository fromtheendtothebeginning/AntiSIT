# 插件化架构（功能 / 主题 / AI 提供商）

**一个插件 = 一个 Dart 包**。功能页面、主题色板、AI 提供商描述都在各自的包里，插件清单与
插件之间的依赖关系都由脚本扫描 `pubspec.yaml` 与各插件源码生成——导入插件就是加一行依赖，
删除插件就是去掉那一行。

```
AntiXiaoYing/                     宿主（App）：壳、设置页、插件管理、清单组装
  lib/main.dart                   组装注册表 + 注入主壳回调
  lib/plugins/bootstrap.dart      buildAppRegistry()：核心插件 + 各插件包
  lib/plugins/manifest.g.dart     ← 生成物，不要手改
  lib/plugins/core_bundles.dart   两个核心插件（network / profile）
  lib/pages/{home,profile,plugin_manager}_page.dart
  lib/widgets/{plugin_graph,theme_picker}.dart
  tool/gen_plugins.dart           清单 + 依赖关系表生成器（含依赖校验）
  packages/
    campus_core/                  契约层：服务 + 组件库 + 插件接口 + 注册表
                                    + 能力接口（ai_capability / reminder_capability）
    plugin_timetable/  plugin_ecard/  plugin_tools/  plugin_grades/
    plugin_exams/      plugin_score/  plugin_activities/  plugin_electricity/
    plugin_ai/         plugin_reminder/  plugin_feedback/
    plugin_ai_deepseek/  plugin_ai_opencode_go/  plugin_ai_kimi/  plugin_ai_glm/
    plugin_ai_qwen/      plugin_ai_gpt/          plugin_ai_gemini/
    plugin_ai_mimo/      plugin_ai_minimax/      ← AI 提供商：一家一个包（含自家 logo）
    plugin_theme_glass/  plugin_theme_ink/  plugin_theme_bamboo/
```

所有包在同一个 **pub workspace** 里（根 pubspec 的 `workspace:` + 各包 `resolution: workspace`），
根目录一次 `flutter pub get` 全部解析。

## 为什么要有 campus_core

插件包要用 `AppState` / `ApiClient` / `AppCard` / `SemColors` / `PluginRegistry`……这些必须在
一个**插件可以依赖、而它不依赖插件**的包里，否则 pub 会报循环依赖。所以共享层整体下沉成
`campus_core`，插件包只写：

```yaml
dependencies:
  campus_core:
    path: ../campus_core
```

`campus_core` 里少数几处需要「往上跳」的地方（登录成功回主壳）不能直接引用宿主的页面，
改成宿主注入的回调：

```dart
// packages/campus_core/lib/host.dart
Widget Function() hostShellBuilder = () => const SizedBox.shrink();
```

宿主在 `main()` 里赋值（`lib/main.dart`）。

## 依赖关系

硬依赖 = 启停联动（启用我时一起启用；停用被依赖者会连带停用我，关系图画实线）；
软依赖 = 可选增强（不联动，虚线）。

三种插件贡献：**功能**（底栏页 / 工具卡片 / 设置条目，可停用）、**主题**（只选不关）、
**AI 提供商**（可停用：停用后不出现在 AI 设置的选择器里，见下面「AI 提供商」一节）。

下面这张表由 `dart run tool/gen_plugins.dart` 从**各插件源码**生成（读 `id` / `dependencies` /
`optionalDependencies` / `removable` 与重写了哪些贡献方法），**不要手改**：加插件时忘了写依赖，
新插件会以「无依赖」出现在表里，一眼能看出来；依赖引用了不存在的 id / 自依赖 / 硬依赖成环，
生成器直接报错退出，不用等运行时才在管理页看到告警。

<!-- BEGIN GENERATED plugin-deps -->
| 插件包 | 插件 id | 硬依赖 | 软依赖 | 用到的能力 | 可停用 | 贡献点 |
|---|---|---|---|---|---|---|
| （宿主） | `network` | — | — | — | ✗ 核心 | 无界面 + 启动初始化 |
| （宿主） | `profile` | `network` | — | — | ✗ 核心 | 底栏页 |
| `plugin_feedback` | `feedback` | — | — | — | ✓ | 设置条目 |
| `plugin_electricity` | `electricity` | `network` | — | — | ✓ | 工具卡片 + 卡面预取 |
| `plugin_activities` | `activities` | `network` | — | — | ✓ | 工具卡片 |
| `plugin_score` | `score` | `network` | — | — | ✓ | 工具卡片 + 卡面预取 |
| `plugin_exams` | `exams` | `network` | — | — | ✓ | 工具卡片 |
| `plugin_grades` | `grades` | `network` | — | — | ✓ | 工具卡片 |
| `plugin_timetable` | `timetable` | `network` | `ai`、`reminder` | `ai`、`reminder` | ✓ | 底栏页 + 设置条目 |
| `plugin_ecard` | `ecard` | `network` | — | — | ✓ | 底栏页 |
| `plugin_tools` | `tools` | — | — | — | ✓ | 底栏页 |
| `plugin_ai` | `ai` | `network` | — | — | ✓ | 设置条目 + 启动初始化 |
| `plugin_ai` | `custom` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_deepseek` | `deepseek` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_opencode_go` | `opencode-go` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_kimi` | `kimi` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_glm` | `glm` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_qwen` | `qwen` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_gpt` | `gpt` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_gemini` | `gemini` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_mimo` | `mimo` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_mimo` | `mimotokenplan` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_minimax` | `minimax` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_ai_minimax` | `minimaxtokenplan` | — | — | — | ✓ | AI 提供商（一家一个包） |
| `plugin_reminder` | `reminder` | `timetable` | — | — | ✓ | 设置条目 + 启动初始化 |
| `plugin_theme_glass` | `theme.glass` | — | — | — | 主题只选不关 | 主题色板 + 场景光斑 |
| `plugin_theme_ink` | `theme.ink` | — | — | — | 主题只选不关 | 主题色板 |
| `plugin_theme_bamboo` | `theme.bamboo` | — | — | — | 主题只选不关 | 主题色板 |
<!-- END GENERATED plugin-deps -->

生成不出来的人话细节（手写）：

- `timetable` 的设置条目 =「上完的课淡化显示」。
- `score` 的工具卡片顺带缓存学籍给「我的」页；`tools` 的底栏页在没有工具启用时自动隐藏。
- `reminder` 的设置条目带一行自检摘要，详情与引导在二级页 `ReminderGuidePage`
  （通知权限 / 精确闹钟 / 省电策略，一键跳系统设置），启动时还负责排期。

`network` 与 `profile` 是**核心插件**，留在宿主里不可停用：前者是登录与数据来源（所有取数
插件的硬依赖），后者承载登录入口与「插件管理」——停掉它就没有恢复其它插件的入口了。

### 插件之间不 import 彼此的包

需要跨包引用的 id（`network` / `timetable` / `ai` / …）集中在 `campus_core` 的
`PluginIds` 常量里。这不是洁癖：如果 `plugin_reminder` 直接
`import 'package:plugin_timetable/...'`，那删掉 `plugin_timetable` 会让它编译不过，
「自由删除」就断了。按 id 引用的结果是——被引用的插件被删掉时，
`PluginRegistry.validate` 把悬空依赖报成管理页顶部的一条告警，而不是编译错误。

**要用另一个插件的功能**（不是只声明顺序）就按 id 从**能力注册表**取接口，见下一节：
实现留在提供方的包里，调用方只 import campus_core 的接口。

## AI 提供商

一家一个包（`plugin_ai_xxx/`），每个包在 barrel 里贡献一个 `AiProviderPlugin`：

```dart
class DeepSeekProvider extends AiProviderPlugin {
  String get id => 'deepseek';      // ← 持久化键：用户填的 Key、选的模型都按它存
  String get label => 'DeepSeek';
  String get baseUrl => 'https://api.deepseek.com';   // OpenAI 兼容基址
  List<String> get models => const [...];             // 只在拉不到官方 /models 时兜底
  String get defaultModel => 'deepseek-flash';
  String get docs => 'https://platform.deepseek.com/api_keys';  // 「申请 API Key」按钮跳这里
  String get logo => 'packages/plugin_ai_deepseek/assets/deepseek.svg';  // 图标也在这个包里
  Map<String, dynamic> thinkingOff(String model) => const {'thinking': {'type': 'disabled'}};
}
const PluginBundle pluginBundle = PluginBundle(providers: [DeepSeekProvider()]);
```

几条约定：

* **协议细节随包走**：关思考字段（各家写法不同，乱加会 400）写在提供商的 `thinkingOff`
  里，不再集中在 core 的 switch；`AiVision.applyThinkingOff` 只是查注册表转发。
* **id 不能改**：它就是 `ai_config` 里 `providerId` 与 `keys` 的键，改了等于丢用户已填的 Key。
* **logo 随包走**：包自己声明 `assets/`，界面按 `packages/<包名>/assets/x.svg` 读；
  删包时图标一起从构建里消失。
* **可停用**：插件管理页逐家开关（与功能插件共用 `plugin_disabled` 键）。停用后它不出现在
  AI 设置的选择器里，AI 也按「未配置」处理（验证码退回手动输入、校历识别入口消失）；
  存档里的 Key 留着，开回来就能继续用。停用**当前正在用的那家**会先弹确认。
  存档里的 providerId 指向一个被停用或删掉的提供商时，`AiConfig.providerUsable` 为假——
  不会把 A 家的 Key 发到回退后的 B 家域名上。
* **一个包可以贡献多条**：同一家厂商的按量付费与订阅套餐模型名一样、域名或 Key 不同
  （`plugin_ai_mimo` = MiMo + Token Plan，`plugin_ai_minimax` = MiniMax + M Plan）。
* 内置的**「自定义」**提供商（地址自己填）留在公共 AI 插件 `plugin_ai` 里——它是兜底入口，
  没有删掉的意义（也照样可以停用，只是停用它就少了一种自建服务的入口）。

## 能力注册表（要用别人的功能怎么办）

**规则**：插件之间的依赖只有两种形态——「声明」与「按 id 取能力」，谁也不 import 对方的包。

* **提供方**在自己包的 barrel 里声明（key 就是本插件 id）：

  ```dart
  const PluginBundle pluginBundle = PluginBundle(
    features: [AiPlugin()],
    providers: [CustomProvider()],
    capabilities: {PluginIds.ai: AiCapabilityImpl()},   // ← 本包对外提供的能力
  );
  ```

  接口（`AiCapability`）定义在 campus_core，实现在提供方包里。声明在清单里而不是
  `init()` 里注册：`init()` 只在启动时跑一次、运行期启用插件不会补跑，声明在清单里就是
  构建期就位，只按启停状态决定能不能查到，也就不需要额外的注销钩子。

* **消费方**只按「接口 + 提供方 id」取用，并在依赖里**声明这个 id**：

  ```dart
  final ai = PluginRegistry.I.capability<AiCapability>(PluginIds.ai);
  if (ai?.available ?? false) { ... }
  ```

  提供方没装（包被删 / 被 EXCLUDE）或被用户停用时返回 null，调用方据此降级——
  和依赖图上那条软依赖虚线边是一回事。今天用到能力的只有 `plugin_timetable`
  （AI：校历识别；上课提醒：AppBar 铃铛），core 自己（验证码弹窗、课表存储重排期）
  也走同一套。

* **校验**：`tool/gen_plugins.dart` 会扫每个插件源码里的
  `capability<...>(PluginIds.y)`，与它声明的 `dependencies` / `optionalDependencies`
  对账——**用了却没声明就报错退出**（依赖图上的边因此与代码耦合一一对应）；
  生成的关系表里也有「用到的能力」一列。能力挂在不存在的插件 id 上时，
  由 `PluginRegistry.validateCapabilities` 报成管理页顶部的一条告警。

## 导入一个插件

```
1. cp -r packages/plugin_grades packages/plugin_xxx     # 照抄结构
2. 改名字三处：目录名、pubspec 的 name、lib/plugin_xxx.dart（barrel）
3. 写实现（实现 FeaturePlugin 或 ThemePlugin），最后加一行：
     const PluginBundle pluginBundle = PluginBundle(features: [XxxPlugin()]);
   要给别的插件用（对外提供功能）就再挂一条 capacity：
     capabilities: {PluginIds.xxx: XxxCapabilityImpl()}   // 见「能力注册表」一节
4. 依赖别的插件就在插件类里写 `List<String> get dependencies => const [PluginIds.xxx];`
   （只按 id 引用，别 import 对方的包）；生成器会把它记进依赖关系表并校验 id 存在
5. 宿主 pubspec.yaml 的依赖与 workspace 各加一行：
     plugin_xxx:
       path: packages/plugin_xxx
6. dart run tool/gen_plugins.dart     # 重新生成清单 + 依赖关系表（顺带校验依赖）
7. flutter pub get
```

包内可以用 `campus_core` 的一切，需要第三方依赖就在这个包的 pubspec 里自己加
（例如 `plugin_timetable` 声明了 `image_picker`）——**删掉这个包，它的依赖与原生插件权限
也跟着从构建里消失**。

### 导入一个 AI 提供商

同上，只是照抄 `packages/plugin_ai_deepseek/`（最干净的一个）：

```
1. cp -r packages/plugin_ai_deepseek packages/plugin_ai_xxx
2. 改名字三处：目录名、pubspec 的 name、lib/plugin_ai_xxx.dart（barrel）
3. 改类里的 id / label / baseUrl / models / defaultModel / docs / logo，实现 thinkingOff
4. 把品牌 logo 放进 packages/plugin_ai_xxx/assets/（logo 的 key 写 packages/<包名>/assets/<文件>）
5. 宿主 pubspec.yaml 的依赖与 workspace 各加一行（顺序 = AI 设置页里提供商列表的顺序）
6. dart run tool/gen_plugins.dart     # 重新生成清单 + 依赖关系表
7. flutter pub get
```

删一家 = 去掉那两行 + 跑生成器；它的代码、依赖与图标一起不进构建（要出各种 SKU 也可以用
`--dart-define=EXCLUDE_AI_XXX=true` 在打包时剔除）。

## 删除一个插件

```
1. 宿主 pubspec.yaml 去掉那两行（workspace 与依赖）
2. dart run tool/gen_plugins.dart     # 表里那一行同时消失
3. flutter pub get；packages/plugin_xxx/ 目录想留想删都行
```

不编译进 App 的代码不会留在包里。实测（删掉 grades / exams / score / activities /
electricity / feedback 六个包，其余照旧）：

| | 全量 14 个包 | 删掉 6 个包 |
|---|---|---|
| APK | 60,127,825 B | 59,503,865 B（−624 KB，−1.0%） |
| `libapp.so`（Dart AOT） | 8,782,768 B | 8,586,160 B（**−196,608 B，−2.2%**） |
| MaterialIcons 字体 | 13,420 B | 11,348 B（只留还够得着的图标） |
| 删掉页面的字符串 | 有 | **0 次**（`宿舍电费` / `报名状态一览` / `历年成绩与 GPA` 都查不到） |

APK 只降 1% 是因为大头是 Flutter 引擎的原生库；Dart 代码本身降 2.2%，且被删功能确实
从二进制里消失了。

## 三种「不要这个功能」

| 粒度 | 怎么做 | 什么时候决定 | 包体 |
|---|---|---|---|
| 停用 | 管理页开关（`plugin_disabled` 键） | 用户运行期，随时可逆 | 不变 |
| 剔除 | `--dart-define=EXCLUDE_XXX=true` 构建 | 打包时（同一份代码出不同 SKU） | 变小，代码被摇掉 |
| 删除 | 去掉 pubspec 依赖 + 生成器 | 改仓库时 | 变小，包目录整个不在 |

`EXCLUDE_*` 开关名由包名推导（`plugin_theme_ink` → `EXCLUDE_THEME_INK`，
`plugin_ai_deepseek` → `EXCLUDE_AI_DEEPSEEK`），生成器会把清单打出来。
（主题没有「停用」这一档——它是只选不关的声明式贡献，见上文。）
每个 `if` 都是编译期常量判断，所以 AOT 摇树真的会删代码
（上面表格里的数字就是删掉 6 个包 / 用 `--dart-define` 剔除 11 个功能的实测值）。

```bash
flutter build apk --release \
  --dart-define=EXCLUDE_ACTIVITIES=true \
  --dart-define=EXCLUDE_ELECTRICITY=true \
  --dart-define=EXCLUDE_THEME_BAMBOO=true
```

## 生成器

`tool/gen_plugins.dart`（纯 Dart，`dart run` 直接跑），一次生成两份东西：

* **清单** `lib/plugins/manifest.g.dart`：扫描宿主 `pubspec.yaml` 的 `dependencies:` 段，
  取所有 `plugin_*` 键**保持书写顺序**（顺序即底栏/工具宫格的默认顺序），`import` 各包
  barrel + 编译期开关 + `pluginBundles`；
* **依赖关系表**：扫描各插件包与宿主 `core_bundles.dart` 的插件类（`FeaturePlugin` /
  `ThemePlugin` / `AiProviderPlugin` 三种都认），读 `id` / `dependencies` /
  `optionalDependencies` / `removable` 与重写了哪些贡献方法，
  写回本文档表格的两行标记之间。**加插件（含加一家 AI 提供商）不用再手抄这张表**，它跟着代码走。
* 两份内容都没变化时不重写文件（避免无意义的 diff）。
* 生成前先**校验依赖**：引用了不存在的 id / 自依赖 / 硬依赖成环 → 打印错误并退出，
  不写出任何文件（悬空**软**依赖只提醒，因为它的语义就是「有则增强、删了拉倒」）；
  同时校验每个包有 `lib/<包名>.dart`（barrel）与显式的
  `class Xxx extends …Plugin`——插件类认不出来也直接报错，
  免得新插件静默地从表里漏掉。

## 管理界面

「我的 → 插件管理」：

1. **依赖关系图**：一列 = 一层依赖（基础插件在右、组合功能在左），箭头指向被依赖方，
   虚线是软依赖，灰点 = 已停用；可双指放大、点节点看详情并原地启停。
2. **实时效果**：底栏长什么样、工具宫格有几个，跟着开关即时变——改一处就能看见自己
   关掉了什么，不用退出去翻页面。
3. **功能插件**：逐项开关；停用有下游的插件会先列出连带清单确认（重新启用不会自动恢复）。
   核心插件显示锁图标、没有开关；停用的行会明显变淡并带「已停用」标记。
4. **主题插件**：单选，直接切换。
5. **AI 提供商**：逐家开关；停用当前正在用的那家会先确认（AI 会变成未配置）。
   停用的提供商不再出现在「AI 设置」的选择器里，换用哪家在「我的 → 设置 → AI 设置」。

「我的 → 设置」里的插件条目（上课提醒 / 上完的课淡化 / AI 设置 / 提交反馈）也是插件贡献的，
插件停用或被删掉后自然消失。

### 实时更新是怎么保证的

壳层（`home_page.dart`）监听注册表，所以底栏与各页会跟着启停重建；但**页面自己也监听**——
工具页、我的页、课表页各自 `addListener(PluginRegistry.I)`，不依赖「壳层顺手把我重建了」
这个隐含前提（这正是之前工具宫格在停用插件后不刷新的原因）。

### 工具排序

「工具 → 右上角排序」：拖拽手柄调整顺序，松手即写进 `plugin_tool_order`（按插件 id 记），
工具页立刻跟着变；「恢复默认」回到 pubspec 依赖顺序。没排到的插件排在已排的后面，
所以新装一个插件不会打乱你已经排好的位置，删掉插件也不会残留无效 id。

### 课表「下课立刻变灰」

「已上完」是按当前时刻算的，但只有 60s 心跳驱动重绘时，09:55 下课的课最晚要到
09:55:59 才变灰。现在按下课时刻（只看节次时间）额外排一个一次性定时器，到点即重绘并
续排下一次（`TimetablePage.nextSlotEndAfter`，有单测覆盖边界：正好下课、下课 1 秒后、
课都上完、跨天）。

## 已知边界

- **停用不减小包体**，只有剔除/删除才减。
- **停用「上课提醒」不会撤回已排的定时通知**：不再重排，但此前排好的会继续弹，
  最多到 30 天排期窗口结束；要立刻停用 用设置里的开关。
- **删除「上课提醒」插件会连通知依赖一起消失**：`flutter_local_notifications` 与
  `timezone` 现在声明在 `plugin_reminder` 自己的 pubspec 里（以前挂在 core 上），
  删掉这个包就不再打进构建。
- **测试都留在宿主的 `test/`**：一个 `flutter test` 跑全部（CI 只构建，见
  `.github/workflows/release.yml`），代价是插件包本身不带测试。
- **课表页内部没有继续拆**：`plugin_timetable` 里的导入 / 调休 / 编辑仍属同一个插件。
- **偏好键名没改**：为不破坏老用户的本地数据，`ai_config`、`class_reminder_on`、
  `campus_timetable` 等键保持原样；注册表的键是 `plugin_disabled` / `plugin_theme`。
