# 重构分批方案

仓库：Flutter pub workspace（宿主 `lib/` + `packages/campus_core` 契约层 + 每功能/主题一个 `packages/plugin_*`）。
基线：Dart 3.9 / Flutter 3.35，`flutter analyze` 0 问题，`flutter test` 879 项全绿。
总量：322 个 Dart 文件 / 70k 行，其中 5384 行是注释（约 9.5%）。

## 重构目标

1. **注释只保留「作用」**：类 / 方法 / 字段最多一句说明它做什么；删掉复述代码、历史沿革、
   长篇审美与权衡论证、注释掉的死代码、分隔线噪声。影响正确性的硬约束（协议字段限制、
   平台坑、必须保持的顺序）压缩到 ≤2 行并入对应声明。
2. **超长文件解耦**：单文件 > 600 行按职责拆分到同目录子文件（页面留 State + build 骨架，
   表单 / 弹窗 / 卡片 / 绘制器 / 模型 / 纯函数外移），单文件目标 ≤ 500 行。
3. **代码整理**：删无用 import 与无用私有成员、常量收敛到所属类、重复小工具收敛到公共文件。
4. **不改行为**：只搬移与精简，不改公开 API、不改文案、不改测试断言。

## 分组与批次

按「依赖方向 + 验证边界」分组：宿主依赖全部包，`campus_core` 被所有插件依赖，
所以顺序是 宿主 → core 契约 → core 直连 → core UI → 大插件 → 小插件 → 测试工具。

| 批次 | 范围 | 主要内容 | 主要动作 |
|---|---|---|---|
| B0 | 本文件 | 分组与方向 | — |
| B1 | 宿主壳 `lib/` | main.dart 621、changelog 838、update_check 282、update_download 410、update_dialog 202、predictive_back_fade 266、pages/*（home 304、profile 600、plugin_manager 534、config 156）、widgets/plugin_graph 367、plugins/* | main.dart 抽 `page_transitions.dart`（转场 3 个 builder + 手势，约 400 行）；update 三件套收敛；注释精简 |
| B2 | core 契约与状态 | app_state 490、api_client 479、plugins/registry 596、plugin 229、capability 系列、score_targets 284、timetable_store 704、timetable_ics 489、demo_data 579、secure_store、pinyin_search、nav_swipe、tool_page_cache | registry 拆「AI 提供商 / 能力 / 依赖图」；timetable_store 拆模型与持久化；注释精简 |
| B3 | core 直连层 `direct/` | jwxt 842、mock_campus_server 1300、course_select 608、campus_direct 565、xg 547、academic 493、http_session 258、epay 190、tunnel 174、activities_util 158、school 122、mock_captcha 118、cas 110、crypto/sm4 | 各系统（jwxt / xg / academic / course_select / epay）按「请求 + 解析」拆；mock 服务器按路由域拆；注释精简 |
| B4 | core 组件库与页面 | flexible_grid 1775、glass_widgets 641、glass_top_bar 335、theme_palette 315、common 252、captcha_dialog 249、glass_nav 235、floating_tabs_header 177、balance_chart 110、theme_picker 124、connect_page 1108、login_page 354 | flexible_grid 拆「尺寸模型 / 拖拽 / 位移动画 / 绘制器」；connect_page 拆「服务器段 / 直连段 / 学校卡 / 模拟服务卡」；注释精简 |
| B5 | 课程表 / 成绩 / 教务 | timetable_page 3327、timetable_settings_page 838、timetable_ics_page 531、score_page 1000、score_target_settings_page 401、academic_page 613 | timetable_page 拆「网格与卡片 / 周-日切换条 / 课程与日程表单 / 导入动作 / 页面骨架」；score_page 拆「列表 / 明细 / 快照」；注释精简 |
| B6 | 拓展体系 `plugin_ext` | extensions_page 1549、ext_bridge 1051、cordis_runtime 639、workshop_store 763、market_view 674、market_sources(_view)、publish_page 589 + publish_* | extensions_page 拆「卡片 / 导入与安装 / 权限弹窗 / 菜单」；ext_bridge 拆「注册 / 通道 / 注入」；注释精简 |
| B7 | 大功能插件 | activities_page 1090、scan_page 968、ai_vision 754、ai_settings_page 721、evaluate_page 582、evaluate_form_page 571、evaluate_api 464、evaluate_model 378、course_select_page 797 | 页面拆视图段；AI 拆「请求 / 解析 / 视觉提示」；评教拆「接口 / 模型 / 表单」；注释精简 |
| B8 | 其余中小插件包 | plugin_academic、appearance、backup、camera、course_cloud、ecard、electricity、exams、feedback、fluid_cloud、grades、home_widget、reminder、risk、tools、webview、theme_*、ai_* 家族 | 注释精简、无用成员清理，必要时小拆 |
| B9 | 测试与工具 | test/（extensions_test 2173、market_test 650、scan_page_test 626 等）、tool/gen_plugins 378 | 超长测试按「分组 group」拆文件；测试注释同样只留作用 |

## 每批验收

1. `flutter analyze` 无问题；
2. `flutter test` 全绿（879 项基线，不允许减少）；
3. `git diff --stat` 只包含本批范围；
4. 本地 commit 一次（不推送）。
