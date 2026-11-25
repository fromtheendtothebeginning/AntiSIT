// 内容数据层：功能、插件、文档章节、FAQ —— 页面只负责渲染，改内容不用碰组件。
// 事实来源：仓库 README.md / docs/plugins.md / docs/extensions.md / docs/campus-api.md（2026-11）。

export const FEATURES = [
  {
    icon: "calendar",
    title: "课程表",
    desc: "多学期管理，周 / 日视图切换，滑动翻周、回到今天；下课即置灰（按节次下课时刻精确重绘，不是隔一分钟才变）。",
    tags: ["教务导入", "考试转日程", "调休", "云端同步"]
  },
  {
    icon: "qr",
    title: "校园码",
    desc: "动态付款码按配置间隔自动刷新（默认 10 秒，服务端有效期更短时听服务端的）+ 校园卡余额，亮码期间屏幕常亮；校付宝公网可达，两种模式都无需校园网。",
    tags: ["动态码", "余额", "常亮"]
  },
  {
    icon: "chart",
    title: "成绩与学业",
    desc: "全部学期 / 按学期查询，平均绩点与学分绩点一览；学业情况给出计划内外通过数与各类别学分要求。",
    tags: ["绩点", "学分", "学业情况"]
  },
  {
    icon: "list",
    title: "第二课堂",
    desc: "达标分数细分着色，加分明细与活动看板都支持搜索 + 类别标签级联筛选；搜索支持全拼与首字母（如 ty 搜「体育」）。",
    tags: ["拼音搜索", "加分明细", "活动看板"]
  },
  {
    icon: "bolt",
    title: "宿舍电费",
    desc: "余额查询、充值（带防重复扣款保护）、历史余额折线图（7 / 30 / 90 天）；服务器模式读站内记录，直连模式存本机。",
    tags: ["余额", "充值", "折线图"]
  },
  {
    icon: "puzzle",
    title: "拓展与插件市场",
    desc: "拓展运行时基于 Cordis，一个扩展就是 ext.json + main.js；市场目录必须过签名校验，每个包再核 sha256 才解压。",
    tags: ["Cordis", "签名目录", "第三方源"]
  },
  {
    icon: "notifications",
    title: "流体云课程通知",
    desc: "课前 15 分钟亮起常驻倒计时，下课前自动收起；排期走系统闹钟并支持开机恢复，App 没打开也生效。",
    tags: ["ColorOS", "原子通知", "焦点通知"]
  },
  {
    icon: "widget",
    title: "桌面卡片与快捷方式",
    desc: "主屏小组件「今日课程」与「校园卡余额」，课表保存 / 校园码刷新后自动同步；长按图标有校园码、课表快捷方式。",
    tags: ["AppWidget", "静态快捷方式", "无需厂商 SDK"]
  },
  {
    icon: "scan",
    title: "扫一扫",
    desc: "只识二维码、自动变焦、带手电筒，也能从相册挑图识别；扫出二课签到码时走专门面板，由学校接口判定签到还是签退。",
    tags: ["签到码", "相册识别", "码型分流"]
  },
  {
    icon: "palette",
    title: "外观与手感",
    desc: "玻璃质感界面、可预测式返回（Android 14+ 与手指 1:1 跟手）、悬浮玻璃顶栏可关；工具卡片长按整理可换位调尺寸。",
    tags: ["玻璃顶栏", "预测式返回", "卡片整理"]
  }
];

export const PLUGIN_GROUPS = [
  {
    name: "核心 · 契约层",
    note: "插件都依赖它，它不依赖任何插件 —— 否则 pub 会报循环依赖",
    items: ["campus_core"]
  },
  {
    name: "功能插件",
    note: "底栏页面 / 工具卡片 / 设置条目都由插件贡献，可逐项启停",
    items: ["plugin_timetable", "plugin_ecard", "plugin_grades", "plugin_exams", "plugin_score",
      "plugin_activities", "plugin_electricity", "plugin_evaluate", "plugin_scan", "plugin_ext",
      "plugin_webview", "plugin_camera", "plugin_reminder", "plugin_backup", "plugin_feedback",
      "plugin_academic", "plugin_course_select"]
  },
  {
    name: "主题插件",
    note: "只选不关：换的是色板，不是功能",
    items: ["plugin_theme_glass", "plugin_theme_ink", "plugin_theme_bamboo", "plugin_appearance"]
  },
  {
    name: "AI 提供商",
    note: "一家一个包（含自家 logo）：停用后不出现在 AI 设置的选择器里",
    items: ["plugin_ai", "plugin_ai_deepseek", "plugin_ai_opencode_go", "plugin_ai_kimi", "plugin_ai_glm",
      "plugin_ai_qwen", "plugin_ai_gpt", "plugin_ai_gemini", "plugin_ai_mimo", "plugin_ai_minimax"]
  }
];

export const STATS = [
  { value: "37", label: "个 Dart 包（契约层 + 36 个插件）" },
  { value: "3", label: "套主题色板（玻璃 / 墨 / 竹）" },
  { value: "10", label: "家 AI 提供商各占一包" },
  { value: "GPL-3.0", label: "开源协议 · 可自建服务器" }
];

// 首页展示区：截图来自当前源码（test/site_shots_test.dart 生成），每页两套配色。
// 文件名规则见 lib/shots.js —— 站点自动按访客主题选 dark / light，不用手工换图。
export const SHOWCASE = [
  {
    id: "timetable",
    label: "课程表",
    title: "一眼看清这一周",
    desc: "周视图按节次排布、按课程上色，滑一下就翻周；正在上的课高亮、已经下课的格子自动置灰。调休、单次日程、每周重复都画在同一张表里。",
    bullets: ["滑动翻周 / 回到今天", "下课即置灰（精确到节次）", "调休与日程事件同表渲染"]
  },
  {
    id: "ecard",
    label: "校园码",
    title: "亮码即付，定时换码",
    desc: "动态付款码按配置间隔刷新（默认 10 秒，服务端有效期更短时听服务端的），余额就挂在码下面；亮码时屏幕保持常亮。动态码仅供本人付款使用。",
    bullets: ["定时自动刷新 + 立即刷新", "余额随码显示", "校付宝公网可达，无需校园网"]
  },
  {
    id: "grades",
    label: "成绩",
    title: "绩点、学分、类别一次看全",
    desc: "顶部汇总平均绩点与门数，下面逐门列出成绩、学分与绩点；课程类别以标签呈现，按学年学期筛选随手切。",
    bullets: ["全部学期 / 按学期查询", "平均绩点与学分绩点", "类别标签 + 排序"]
  },
  {
    id: "activities",
    label: "第二课堂",
    title: "报名中的活动，搜得到",
    desc: "活动看板带搜索与类别标签筛选，全拼和首字母都能命中；每条活动给主办、名额、活动时间与报名窗口，报名状态一眼分辨。",
    bullets: ["拼音搜索（全拼 / 首字母）", "类别级联筛选", "报名状态分色"]
  },
  {
    id: "tools",
    label: "工具",
    title: "卡片宫格，自己排",
    desc: "成绩单、考试安排、二课分数、学业情况、学生评教……常用工具收在一屏宫格里；长按进入整理，拖动换位、拖右下角调大小（1×1 / 1×3 / 2×3 / 2×2），顺序与尺寸都记在本机。",
    bullets: ["长按拖动换位", "四档尺寸 + 连续缩放", "顺序与尺寸存本机"]
  }
];

export const PRINCIPLES = [
  {
    title: "一个插件 = 一个 Dart 包",
    desc: "功能页面、主题色板、AI 提供商描述都在各自的包里。导入插件就是往 pubspec 加一行依赖，删除就是去掉那一行 —— 不用改宿主代码。"
  },
  {
    title: "契约层只向下",
    desc: "campus_core 提供 AppState / ApiClient / 组件库 / 插件接口，插件只依赖它、它不依赖插件。少数「往上跳」的地方改成宿主注入的回调。"
  },
  {
    title: "清单由脚本生成",
    desc: "插件清单与依赖关系由 tool/gen_plugins.dart 扫描各包源码生成。依赖引用不存在的 id、自依赖、硬依赖成环，生成器直接报错退出。"
  },
  {
    title: "两种接入方式，同一套接口",
    desc: "服务器模式由服务器代连校园内网；直连模式用本机凭据直接访问学校系统。任意语言实现同一套接口形式，都能给 App 当后端。"
  }
];

export const DOC_GROUPS = [
  {
    group: "开始",
    items: [
      { id: "what", title: "拓展是什么" },
      { id: "first", title: "第一个拓展（10 分钟）" },
      { id: "life", title: "生命周期与 ctx.effect" }
    ]
  },
  {
    group: "界面",
    items: [
      { id: "ui", title: "AntiUI 组件" },
      { id: "theme", title: "主题与夜间模式" },
      { id: "nav", title: "页面栈与返回" }
    ]
  },
  {
    group: "能力",
    items: [
      { id: "storage", title: "存储与凭据" },
      { id: "net", title: "联网：https 与校内 http" },
      { id: "ai", title: "调用 AI" },
      { id: "notify", title: "通知（即时 / 定时 / 横幅）" },
      { id: "misc", title: "剪贴板 · 文件 · 登录 · 保活" }
    ]
  },
  {
    group: "发布",
    items: [
      { id: "perm", title: "权限声明与授权" },
      { id: "pack", title: "打包、自检、安装" },
      { id: "market", title: "发布到市场 / 第三方源" },
      { id: "migrate", title: "旧 html 拓展迁移" }
    ]
  },
  {
    group: "附录",
    items: [
      { id: "safety", title: "安全边界" },
      { id: "appdev", title: "写 Dart 功能插件" },
      { id: "api", title: "开放接口规约" }
    ]
  }
];