# AGENTS.md —— 给 AI / 协作者的仓库约定

AntiSIT 是 Flutter pub workspace：宿主 `lib/` + 契约层 `packages/campus_core` +
**一个插件 = 一个文件夹**（`packages/plugin_*/`）。这份文件是**动手前必读的硬约定**，
详细说明见 `docs/plugins.md`（插件）与 `docs/extensions.md`（拓展）、`docs/campus-api.md`（服务端协议）。

## 目录结构

```
AntiXiaoYing/
  lib/                        宿主：壳、启动、设置页、插件管理、清单组装
    main.dart                 组装注册表 + 注入主壳回调 + 后台任务注册
    background_tasks.dart     WorkManager 定时任务（二课新活动每小时检查）
    pages/boot_page.dart      启动动画 + 异步初始化
    plugins/manifest.g.dart   ← 生成物，不要手改
  packages/
    campus_core/              契约层（所有插件都只依赖它）
    plugin_*/                 **一个插件文件夹**
      pubspec.yaml            包名 = 文件夹名
      ext.json?               拓展型清单（仅拓展仓库用）
      lib/                    实现
        plugin_*.dart         barrel：暴露 pluginBundle
        <插件类>.dart         插件类（FeaturePlugin / ThemePlugin / AiProviderPlugin）
        pages/                页面级实现（可选）
        market/ publish/ workshop/  子域（仅 plugin_ext 这种大插件）
      assets/                 自家图标 / 样式
  tool/
    gen_plugins.dart         清单 + 依赖表 + plugin_folders.json 生成器
    split_logo.py            校徽三色拆分（启动动画分层用）：sit-mark.png → 三张单层 PNG
  assets/
    plugin_folders.json      ← 生成物：插件文件夹清单（运行期只读）
    sit-mark.png             校徽原图
    sit-mark-{light,dark,green}.png  ← 拆分产物（同一画布、只留本层像素，叠回即原标）
  docs/                       开发文档
```

## 插件：一个文件夹，可以有多个部件

一个插件文件夹 = 一个 Dart 包，但**目录里允许放多个「部件」**：

| 部件 kind | 例子 | 说明 |
|---|---|---|
| `feature` | `activities`、`timetable` | 底栏页 / 工具卡片 / 设置条目，可停用 |
| `theme` | `theme.glass` | 主题色板 + 场景光斑，只选不关 |
| `provider` | `deepseek`、`minimax` | AI 提供商，可停用 |

- 一个文件夹可以贡献**多个 id**（`plugin_ai_mimo` 同时给 mimo 与 mimotokenplan）。
- 部件之间**不 import 彼此的文件**：跨插件一律按 id 经能力注册表取接口。
- `dart run tool/gen_plugins.dart` 会扫描每个文件夹的插件类，写出
  `lib/plugins/manifest.g.dart`（清单）、`docs/plugins.md`（依赖表生成块）、
  `assets/plugin_folders.json`（文件夹清单，含部件划分）。**这三个都是生成物，不要手改。**
- 加插件 = 建 `packages/plugin_xxx/`（照抄 `plugin_grades`）→ 根 `pubspec.yaml`
  的 `workspace` 与 `dependencies` 各加一行 → 跑生成器 → `flutter pub get`。
- 删插件 = 去掉那两行 + 跑生成器（文件夹留不留都行，不进构建就不占包体）。

## 硬约束（踩过的坑）

1. **插件之间不 import 彼此的包**，只用 `PluginIds.*` 常量与能力注册表。
   生成器会扫描 `capability<...>(PluginIds.y)` 与依赖声明对账，用了不声明直接报错退出。
2. **CI 用 `flutter analyze --fatal-infos`**：info 级 lint 也会红。提交前必须跑
   `dart fix --apply` 与 `flutter analyze`（`build/` 下的临时 dart 也会被扫）。
3. **测试全部在宿主 `test/`**：一次 `flutter test` 跑全部；插件包不单独带测试。
4. **文案**：主标题简洁客观，副标题只写当前状态，不解释组件；改写文案前先联网确认设计惯例。
5. **写操作（报名 / 签到 / 充值）只提交一次、绝不自动重试**；超时 / 5xx / 连接重置一律按
   「结果未确认」提示用户先核实（`writeOutcomeUncertain`）。
6. **不做实时模糊（BackdropFilter）**：顶栏 / 底栏 / 切换器都用渐变遮罩；实时模糊在转场与
   滚动时是掉帧主因（issue #20）。`GlassFadedBody` 也是同色遮罩，不用 `ShaderMask`。
7. **本机数据兼容**：`ai_config`、`class_reminder_on`、`campus_timetable`、`update_skipped_version`
   等键名不要改（改 = 丢用户数据）；要迁移就写一次性迁移逻辑。
8. **直连模式修了校园数据 bug，服务器模式必须同步**：两种模式是**两条独立实现**
   （`packages/campus_core/lib/direct/` 直连、服务器侧在隔壁仓库 `/d/anticraft/index`
   的 `backend/campus/dekt.py` + `backend/features/campus_open.py`）。协议字段、
   上游接口（例如二课「我的报名」必须走 `bizFlow groupCode=xshd`、「加分明细」走
   `xsrd`）与错误处理要一起改，否则会出现「直连好了、服务器模式还是老样子」。
   改服务器侧只改本地工作树，**部署要等用户明确说「发布到服务器」**。

## 常用命令

```bash
flutter pub get                      # 根目录一次解析全部包
dart run tool/gen_plugins.dart       # 改了插件集合 / 依赖后重新生成
flutter analyze                      # CI 同款（--fatal-infos）
flutter test                         # 全部测试
dart format <改过的文件>             # 只格式化自己改过的文件
```

## 发版

- 稳定版：`pubspec.yaml` 升到 `1.48.0+206` → 打 `v1.48.0` tag → `release.yml` 发正式 Release。
- 内测版：version 写成 `1.48.0-dev.2+207` → 打 `dev-1.48.0-dev.2` tag → 发 prerelease。
- Gitee / 镜像：`tool/release_gitee.sh`（自动按版本号决定 tag 前缀）与 `tool/upload_mirror.sh`。
- 发版后 App 侧「我的 → 检查更新」二级页会按渠道比较；稳定版与新内测版各自独立提示。

## 提交

- 直接在 `main` 上改，不新建特性分支。
- 一个改动一次提交，提交前 `git add -A` 后先 `git status` 核对文件列表（分组提交容易漏文件）。
- 提交信息写「做了什么 + 为什么」，涉及 issue 的写 `修 issue #N`。
