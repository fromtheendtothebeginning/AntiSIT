# OPPO 泛在卡片（流体云 / 桌面卡）工程

这是按 OPPO 开放平台文档搭的 **UPK 卡片工程骨架**，用于在 ColorOS 上把 AntiSIT 的
「今日课程」做成真正的**流体云**（状态栏胶囊 / 展开面板 / 锁屏 / 通知中心）和
**桌面卡片**。它不是 Flutter 工程的一部分，也不参与 `flutter build`；需要单独用
OPPO 的卡片工具打包、上架。

## 依据的文档

| 文档 | 地址 |
|---|---|
| 流体云模板（信息区域 / 胶囊规范） | https://open.oppomobile.com/new/developmentDoc/info?id=12658 |
| 流体云卡片（工程配置） | https://open.oppomobile.com/new/developmentDoc/info?id=12965 |
| 桌面 / 负一屏卡模板 | https://open.oppomobile.com/new/developmentDoc/info?id=12657 |
| 小组件模板 | https://open.oppomobile.com/new/developmentDoc/info?id=12659 |
| config.json | https://open.oppomobile.com/new/developmentDoc/info?id=12645 |
| card-config.json | https://open.oppomobile.com/new/developmentDoc/info?id=12646 |
| 数据绑定（无宿主） | https://open.oppomobile.com/new/developmentDoc/info?id=12669 |
| 事件绑定 | https://open.oppomobile.com/new/developmentDoc/info?id=12666 |
| SeedlingSupportSDK 接入指南 | https://open.oppomobile.com/new/developmentDoc/info?id=12719 |

关键规则（照着做的）：

* 流体云是**固定模板**，不允许改布局 / CSS，只能填数据；`<card-template entry="notification" category="modular">`。
* 展开态分三块：`leading` = 顶部信息、`center` = 核心信息、`trailing` = 底部信息；
  只有核心信息能单独显示，顶部 / 底部不能单独用。
* 胶囊态 `<compact>` 分 `leading` / `trailing`；背景固定黑色；文本尽量 ≤5 字。
* 用 `<compact>` 时 `config.json` 的入口必须包含 `statusbar`。
* 桌面卡 `entry="desktop"` 可自定义布局；`card-config.json` 的 `support` 要包含对应尺寸。

## 目录

```
oppo_card/
  README.md
  src/
    config.json               # 服务基础信息 / 入口 / 运行版本
    index.oml                 # 流体云模板 + 桌面卡模板 + 数据 / 事件
    seedling.js               # 卡片 JS 生命周期与兜底数据
    assets/
      card-config.json        # 宿主信息、支持的尺寸、点击行为
      images/icon.png         # 144×144 PNG（已从 App 图标生成）
```

## 上线前必须替换的占位

`src/config.json`：

* `identifier.id`：`auto_generate` → 泛在服务库分配的 **服务 id**
* `intent.action` / `intent.domain`：替换成 OPPO 分配的意图（课程提醒场景）
* `identifier.url`：如需自己的包名可改（当前 `top.anticraft.campus_service.course`）

`card-config.json`：

* `host.packageName` / `host.componentName` 必须与 App 里实现的 Provider 完全一致
* `host.minHostVersion` = 宿主 APK 的 versionCode 下限（当前 100）

`assets/images/icon.png`：已生成 144×144、10KB，符合文档要求（PNG / sRGB / ≤50KB）。

`meta-data.capabilities` 暂未配置：该文档标注「能力配置文件即将上线」，等 OPPO 提供格式再补。

## App 侧需要做的事（本仓库暂未接入）

1. **申请泛在卡片服务**：联系 OPPO 开通，拿服务 id / 意图 / 上架权限（这一步绕不过去）。
2. 接入 **SeedlingSupportSDK**（Maven）：
   ```kotlin
   implementation("com.oplus.pantanal.card:seedling-support-lite:3.0.7")
   ```
   `lite` 只含泛在服务；要兼容速览用 `external`。
3. 继承 `SeedlingCardWidgetProvider`：
   * `onCardCreate / onShow / onHide / onDestroy / onUpdateData`
   * 在 `onUpdateData` 里把课表数据 `Bundle` 交给 `updateData(card, bundle)`，
     字段名与 `index.oml` 的 `{{ }}` 对应（capsuleLeft / courseName / place / timeRange …）
4. `AndroidManifest.xml` 注册 Provider（`exported=true`）：
   ```xml
   <provider
       android:name=".SeedlingCardProvider"
       android:authorities="top.anticraft.campus_service.seedling"
       android:enabled="true"
       android:exported="true">
       <intent-filter>
           <action android:name="com.oplus.seedling.action.SEEDLING_CARD" />
       </intent-filter>
   </provider>
   ```
   （失败回调可选：`SeedlingCardEventProvider`，authority 固定
   `${applicationId}.card.event.provider`。）
5. 课表变化时调用 `updateData` 推最新数据（与现有 `HomeWidget` 同步同一个入口最省事）。

## 打包与上架

1. 用 OPPO **Pantanal DevStudio** 打开 `oppo_card/`（或把 `src/` 导入新建的卡片工程）。
2. 本地预览：状态栏胶囊 / 展开面板 / 桌面卡三个入口各看一遍。
3. 打包 UPK → 上传泛在服务库 → 提交审核 → 灰度 / 全量。

## 与当前 App 内实现的关系

App 里已经有的「流体云课程通知」是**系统实时通知**（Android 16 live update + 常驻倒计时），
在 ColorOS 上不会自动变成官方流体云形态。本工程是走 OPPO 官方卡片通道的另一条路：
两者可以并存——UPK 未上架 / 未生效时用系统通知兜底，上架后由卡片通道接管。
