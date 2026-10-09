# 插件化架构（功能与主题）

**一个插件 = 一个 Dart 包**。功能页面、主题色板都在各自的包里，插件清单由脚本扫描
`pubspec.yaml` 的依赖生成——导入插件就是加一行依赖，删除插件就是去掉那一行。

```
AntiXiaoYing/                     宿主（App）：壳、设置页、插件管理、清单组装
  lib/main.dart                   组装注册表 + 注入主壳回调
  lib/plugins/bootstrap.dart      buildAppRegistry()：核心插件 + 各插件包
  lib/plugins/manifest.g.dart     ← 生成物，不要手改
  lib/plugins/core_bundles.dart   两个核心插件（network / profile）
  lib/pages/{home,profile,plugin_manager}_page.dart
  lib/widgets/{plugin_graph,theme_picker}.dart
  tool/gen_plugins.dart           清单生成器
  packages/
    campus_core/                  契约层：服务 + 组件库 + 插件接口 + 注册表
    plugin_timetable/  plugin_ecard/  plugin_tools/  plugin_grades/
    plugin_exams/      plugin_score/  plugin_activities/  plugin_electricity/
    plugin_ai/         plugin_reminder/  plugin_feedback/
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

| 插件包 | 插件 id | 硬依赖 | 软依赖 | 可停用 | 贡献点 |
|---|---|---|---|---|---|
| （宿主） | `network` | — | — | ✗ 核心 | 无界面（数据来源与登录态） |
| （宿主） | `profile` | `network` | — | ✗ 核心 | 底栏页（登录 / 设置 / 插件管理入口） |
| `plugin_timetable` | `timetable` | `network` | `ai` | ✓ | 底栏页 + 设置条目（淡化已上完的课） |
| `plugin_ecard` | `ecard` | `network` | — | ✓ | 底栏页 |
| `plugin_tools` | `tools` | — | — | ✓ | 底栏页（没有工具时自动隐藏） |
| `plugin_grades` | `grades` | `network` | — | ✓ | 工具卡片 |
| `plugin_exams` | `exams` | `network` | — | ✓ | 工具卡片 |
| `plugin_score` | `score` | `network` | — | ✓ | 工具卡片（顺带缓存学籍给「我的」页） |
| `plugin_activities` | `activities` | `network` | — | ✓ | 工具卡片 |
| `plugin_electricity` | `electricity` | `network` | — | ✓ | 工具卡片（余额速览） |
| `plugin_ai` | `ai` | `network` | — | ✓ | 设置条目 |
| `plugin_reminder` | `reminder` | `timetable` | — | ✓ | 设置条目（开关 + 一行自检摘要，详情与引导在二级页 `ReminderGuidePage`：通知权限 / 精确闹钟 / 省电策略，一键跳系统设置）+ 启动排期 |
| `plugin_feedback` | `feedback` | — | — | ✓ | 设置条目 |
| `plugin_theme_glass` | `theme.glass` | — | — | 主题只选不关 | 浅/深色板 + 场景光斑 |
| `plugin_theme_ink` / `plugin_theme_bamboo` | `theme.ink` / `theme.bamboo` | — | — | 同上 | 浅/深色板 |

`network` 与 `profile` 是**核心插件**，留在宿主里不可停用：前者是登录与数据来源（所有取数
插件的硬依赖），后者承载登录入口与「插件管理」——停掉它就没有恢复其它插件的入口了。

### 插件之间不 import 彼此的包

需要跨包引用的 id（`network` / `timetable` / `ai` / …）集中在 `campus_core` 的
`PluginIds` 常量里。这不是洁癖：如果 `plugin_reminder` 直接
`import 'package:plugin_timetable/...'`，那删掉 `plugin_timetable` 会让它编译不过，
「自由删除」就断了。按 id 引用的结果是——被引用的插件被删掉时，
`PluginRegistry.validate` 把悬空依赖报成管理页顶部的一条告警，而不是编译错误。

## 导入一个插件

```
1. cp -r packages/plugin_grades packages/plugin_xxx     # 照抄结构
2. 改名字三处：目录名、pubspec 的 name、lib/plugin_xxx.dart（barrel）
3. 写实现（实现 FeaturePlugin 或 ThemePlugin），最后加一行：
     const PluginBundle pluginBundle = PluginBundle(features: [XxxPlugin()]);
4. 宿主 pubspec.yaml 的依赖与 workspace 各加一行：
     plugin_xxx:
       path: packages/plugin_xxx
5. dart run tool/gen_plugins.dart     # 重新生成清单
6. flutter pub get
```

包内可以用 `campus_core` 的一切，需要第三方依赖就在这个包的 pubspec 里自己加
（例如 `plugin_timetable` 声明了 `image_picker`）——**删掉这个包，它的依赖与原生插件权限
也跟着从构建里消失**。

## 删除一个插件

```
1. 宿主 pubspec.yaml 去掉那两行（workspace 与依赖）
2. dart run tool/gen_plugins.dart
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

`EXCLUDE_*` 开关名由包名推导（`plugin_theme_ink` → `EXCLUDE_THEME_INK`），
生成器会把清单打出来。每个 `if` 都是编译期常量判断，所以 AOT 摇树真的会删代码
（上面表格里的数字就是删掉 6 个包 / 用 `--dart-define` 剔除 11 个功能的实测值）。

```bash
flutter build apk --release \
  --dart-define=EXCLUDE_ACTIVITIES=true \
  --dart-define=EXCLUDE_ELECTRICITY=true \
  --dart-define=EXCLUDE_THEME_BAMBOO=true
```

## 清单生成器

`tool/gen_plugins.dart`（纯 Dart，`dart run` 直接跑）：

* 扫描宿主 `pubspec.yaml` 的 `dependencies:` 段，取所有 `plugin_*` 键，**保持书写顺序**
  （顺序即底栏/工具宫格的默认顺序）；
* 校验每个包有 `lib/<包名>.dart`（barrel），缺了就报错退出——这是插件包的唯一命名约定；
* 生成 `lib/plugins/manifest.g.dart`：`import` 各包 barrel + 编译期开关 + `pluginBundles`；
* 内容没变化时不重写文件（避免无意义的 diff）。

## 管理界面

「我的 → 插件管理」：

1. **依赖关系图**：一列 = 一层依赖（基础插件在右、组合功能在左），箭头指向被依赖方，
   虚线是软依赖，灰点 = 已停用；可双指放大、点节点看详情并原地启停。
2. **实时效果**：底栏长什么样、工具宫格有几个，跟着开关即时变——改一处就能看见自己
   关掉了什么，不用退出去翻页面。
3. **功能插件**：逐项开关；停用有下游的插件会先列出连带清单确认（重新启用不会自动恢复）。
   核心插件显示锁图标、没有开关；停用的行会明显变淡并带「已停用」标记。
4. **主题插件**：单选，直接切换。

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

- **资产还在宿主**：`assets/brands/*.svg`（AI 提供商 logo）由宿主 pubspec 声明，core 里的
  `BrandLogo` 按同样的 key 读——能跑，但严格说 core 借用宿主的资产。
- **`class_reminder_service.dart` 属于 core**：课表页（在 `plugin_timetable` 里）要调它，
  如果把它搬进 `plugin_reminder`，两个包就会互相依赖（pub 不允许）。所以「上课提醒」插件
  只装开关 UI 与启动排期，通知服务本身是基础设施，删掉插件不会移除
  `flutter_local_notifications`。
- **停用不减小包体**，只有剔除/删除才减。
- **停用「上课提醒」不会撤回已排的定时通知**：不再重排，但此前排好的会继续弹，
  最多到 30 天排期窗口结束；要立刻停用 用设置里的开关。
- **测试都留在宿主的 `test/`**：一个 `flutter test` 跑全部（CI 只构建，见
  `.github/workflows/release.yml`），代价是插件包本身不带测试。
- **课表页内部没有继续拆**：`plugin_timetable` 里的导入 / 调休 / 编辑仍属同一个插件。
- **偏好键名没改**：为不破坏老用户的本地数据，`ai_config`、`class_reminder_on`、
  `campus_timetable` 等键保持原样；注册表的键是 `plugin_disabled` / `plugin_theme`。
