// 内容数据层：功能、插件、展示图、文档目录 —— 页面只负责渲染，改文案不用碰组件。
// 事实来源：仓库 README.md / AGENTS.md / docs/plugins.md / docs/extensions.md / docs/campus-api.md（2026-11）。
//
// 写文案的几条约定（踩过「像接口文档不像给人看」的坑之后定的）：
// * 先说「对你有什么用」，再补一句怎么做到；不在营销页堆实现细节（sha256 / pubspec / 目录格式属于文档页）
// * 一句话只讲一件事，能用短句就不用长句；括号里不放补充说明
// * 技术名词只在开发文档页出现；首页与介绍页说人话

export const FEATURES = [
  {
    icon: "calendar",
    title: "课程表",
    desc: "这学期上什么、今天上到第几节、下周换成什么，打开就看。课表能从教务导入，调休和日程也画在同一张表里。上过的课会自己变灰。",
    tags: ["周 / 日视图", "教务导入", "调休", "云端同步"]
  },
  {
    icon: "qr",
    title: "校园码",
    desc: "付款码会自己换，余额就在码下面。亮码的时候屏幕不会暗下去，食堂和校付宝都能刷。",
    tags: ["动态码", "余额显示", "屏幕常亮"]
  },
  {
    icon: "chart",
    title: "成绩与学业",
    desc: "成绩、绩点、学分一次看全。还能查学业情况：哪些课过了，各类学分还差多少。",
    tags: ["按学期查", "平均绩点", "学业情况"]
  },
  {
    icon: "list",
    title: "第二课堂",
    desc: "活动报名、加分明细、达标分数都在一块。想找活动直接搜，打「ty」也能搜到「体育」。",
    tags: ["活动看板", "加分明细", "拼音搜索"]
  },
  {
    icon: "bolt",
    title: "宿舍电费",
    desc: "还剩多少电、什么时候该充，看一眼就知道。充值有防重复保护，余额变化画成折线图。",
    tags: ["余额查询", "在线充值", "余额折线"]
  },
  {
    icon: "puzzle",
    title: "拓展与插件市场",
    desc: "想要的功能可以自己加。市场里的拓展都验过签名，装之前会把要用哪些权限讲清楚。",
    tags: ["拓展市场", "签名校验", "权限透明"]
  },
  {
    icon: "notifications",
    title: "流体云课程通知",
    desc: "上课前 15 分钟，手机顶部会亮起倒计时，下课了自动收起。App 没打开也会提醒。",
    tags: ["课前提醒", "常驻倒计时", "重启后仍在"]
  },
  {
    icon: "widget",
    title: "桌面卡片与快捷方式",
    desc: "桌面小组件直接显示今天前几节课和校园卡余额，不用打开 App。长按图标还有校园码和课表的快捷方式。",
    tags: ["桌面小组件", "长按快捷方式", "各家桌面通用"]
  },
  {
    icon: "scan",
    title: "扫一扫",
    desc: "扫二维码、开手电筒、从相册识图都行。扫到二课的签到码，会直接跳到签到面板。",
    tags: ["扫码", "相册识图", "签到码"]
  },
  {
    icon: "palette",
    title: "外观与手感",
    desc: "界面是玻璃质感，返回手势跟着手指走。工具卡片可以长按拖动、调大小，摆成你顺手的样子。",
    tags: ["玻璃质感", "跟手返回", "卡片整理"]
  }
];

export const PLUGIN_GROUPS = [
  {
    name: "核心 · 契约层",
    note: "公共代码都放在这里，插件都依赖它、它不依赖任何插件",
    items: ["campus_core"]
  },
  {
    name: "功能插件",
    note: "每个功能一个包，可以在「插件管理」里单独开关",
    items: ["plugin_timetable", "plugin_ecard", "plugin_grades", "plugin_exams", "plugin_score",
      "plugin_activities", "plugin_electricity", "plugin_evaluate", "plugin_scan", "plugin_ext",
      "plugin_webview", "plugin_camera", "plugin_reminder", "plugin_backup", "plugin_feedback",
      "plugin_academic", "plugin_course_select"]
  },
  {
    name: "主题插件",
    note: "换的是配色，不是功能",
    items: ["plugin_theme_glass", "plugin_theme_ink", "plugin_theme_bamboo", "plugin_appearance"]
  },
  {
    name: "AI 提供商",
    note: "一家一个包，关掉就不会出现在 AI 设置的选择器里",
    items: ["plugin_ai", "plugin_ai_deepseek", "plugin_ai_opencode_go", "plugin_ai_kimi", "plugin_ai_glm",
      "plugin_ai_qwen", "plugin_ai_gpt", "plugin_ai_gemini", "plugin_ai_mimo", "plugin_ai_minimax"]
  }
];

export const STATS = [
  { value: "37", label: "个插件文件夹（1 个契约层 + 36 个插件包）" },
  { value: "3", label: "套主题色板（玻璃 / 墨 / 竹）" },
  { value: "10", label: "家 AI 提供商，各占一个包" },
  { value: "GPL-3.0", label: "开源协议，可自建服务器" }
];

// 首页展示区：截图来自当前源码（test/site_shots_test.dart 生成），每页两套配色。
// 文件名规则见 lib/shots.js —— 站点按访客主题自动选 dark / light，不用手工换图。
export const SHOWCASE = [
  {
    id: "timetable",
    label: "课程表",
    title: "一周的课，打开就看",
    desc: "周视图按节次排开，每门课一个颜色。滑一下翻到下周，点「今天」随时跳回来。上过的课会自动变灰，调休和日程也画在同一张表里。",
    bullets: ["滑动翻周，一键回今天", "下课那格自动变灰", "调休与日程同表显示"]
  },
  {
    id: "ecard",
    label: "校园码",
    title: "付款码会自己换",
    desc: "动态码每隔一会就自动刷新，余额就在码下面。亮码时屏幕保持常亮，不用担心扫到一半变暗。",
    bullets: ["自动刷新，也能手动换", "余额随码显示", "校付宝公网可达"]
  },
  {
    id: "grades",
    label: "成绩",
    title: "成绩、绩点、学分，一次看全",
    desc: "上面是平均绩点和门数，下面一门门列着成绩、学分和绩点。按学年学期筛选，随手就能切。",
    bullets: ["按学期筛选", "平均绩点汇总", "课程类别标签"]
  },
  {
    id: "activities",
    label: "第二课堂",
    title: "想报名的活动，搜得到",
    desc: "活动看板能搜能筛，全拼和首字母都认。每条活动写着主办、名额和报名时间，能不能报一眼看清。",
    bullets: ["搜索支持拼音", "类别筛选", "报名状态分色"]
  },
  {
    id: "tools",
    label: "工具",
    title: "工具卡片，摆成你顺手的样子",
    desc: "成绩、考试、二课、学业情况、评教……常用工具都在这一屏。长按卡片可以拖动换位、调大小，排好之后一直留着。",
    bullets: ["长按拖动换位", "四种尺寸可调", "顺序自动保存"]
  },
  {
    id: "update",
    label: "检查更新",
    title: "稳定版与内测版，各看各的",
    desc: "稳定版只跟正式发布，内测版能更早拿到新功能。两个渠道各显示自己有没有更新，随时切换，也能关掉自动弹窗。",
    bullets: ["双渠道各自提示", "一键切换", "更新弹窗可关"]
  }
];

export const PRINCIPLES = [
  {
    title: "一个插件 = 一个文件夹",
    desc: "课程表、校园码、成绩各住各的文件夹，一个文件夹里还能放多个部件。想加就加一行依赖，想删就删那一行，不用改别的地方。"
  },
  {
    title: "公共代码不依赖插件",
    desc: "大家都要用的东西放在 campus_core，插件都依赖它、它不依赖任何插件。这样加多少插件都不会互相绕住。"
  },
  {
    title: "清单由脚本生成",
    desc: "插件清单和依赖关系是脚本扫源码生成的。依赖写错了，生成的时候就会报错，不用等到运行起来才发现。"
  },
  {
    title: "同一套接口，两种走法",
    desc: "可以让服务器代连校园网，也可以让 App 自己直连学校系统。接口形式一致，自己搭的服务器同样能用。"
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