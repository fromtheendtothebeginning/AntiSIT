import Code from "../components/Code.jsx";
import Icon from "../components/Icon.jsx";
import Reveal from "../components/Reveal.jsx";
import { SITE } from "../lib/site.js";

// 每章一个纯组件：只渲染文本 + Code；增删章节改这里与 lib/data.js。
export default function DocContent({ id }) {
  const map = {
    what: <What />,
    first: <First />,
    life: <Life />,
    ui: <UiKit />,
    theme: <ThemeKit />,
    nav: <Nav />,
    storage: <Storage />,
    net: <Net />,
    ai: <Ai />,
    notify: <Notify />,
    misc: <Misc />,
    perm: <Perm />,
    pack: <Pack />,
    market: <Market />,
    migrate: <Migrate />,
    safety: <Safety />,
    appdev: <AppDev />,
    api: <ApiSpec />
  };
  return map[id] || map.what;
}
/* ------------------------------------------------------------------ 复用件 */

const NL = "\n";
const lines = (arr) => arr.join(NL);

function Chapter({ title, icon, kicker, children }) {
  return (
    <Reveal className="doc-section">
      <div className="doc-card">
        <div className="doc-card-head">
          <span className="repo-icon" style={{ width: 32, height: 32, borderRadius: 11 }}>
            <Icon name={icon} size={16} />
          </span>
          <div>
            {kicker && <div className="doc-kicker">{kicker}</div>}
            <h2>{title}</h2>
          </div>
        </div>
        <div className="doc-prose">{children}</div>
      </div>
    </Reveal>
  );
}

function Note({ kind = "tip", title, children }) {
  return (
    <div className={"doc-note " + kind}>
      <strong>{title}</strong>
      <div>{children}</div>
    </div>
  );
}

function KV({ k, children }) {
  return (
    <div className="kv">
      <div className="kv-k">{k}</div>
      <div className="kv-v">{children}</div>
    </div>
  );
}

/* ------------------------------------------------------------------ 代码样例 */

const CODE = {
  EXT_JSON: lines([
    "{",
    "  \"id\": \"sit.counter\",",
    "  \"name\": \"记一笔\",",
    "  \"desc\": \"演示用的最小拓展\",",
    "  \"version\": \"1.0.0\",",
    "  \"main\": \"main.js\",",
    "  \"permissions\": [\"storage\"]",
    "}",
  ]),
  EXT_JS: lines([
    "export default {",
    "  name: 'sit.counter',",
    "  inject: ['ui', 'storage'],",
    "",
    "  async apply(ctx) {",
    "    const count = (await ctx.storage.get('count')) ?? 0;",
    "",
    "    const page = AntiUI.page({",
    "      title: '记一笔',",
    "      subtitle: '每点一下加一，关掉再打开还在',",
    "      children: [",
    "        AntiUI.card({",
    "          title: '已经记了 ' + count + ' 次',",
    "          children: [AntiUI.button('记一笔', { variant: 'primary', block: true, onClick: bump })],",
    "        }),",
    "      ],",
    "    });",
    "    ctx.ui.root.appendChild(page);",
    "",
    "    async function bump() {",
    "      const next = ((await ctx.storage.get('count')) ?? 0) + 1;",
    "      await ctx.storage.set('count', next);",
    "      page.querySelector('.au-card-title').textContent = '已经记了 ' + next + ' 次';",
    "      ctx.ui.toast('已记 ' + next);",
    "    }",
    "  },",
    "};",
  ]),
  EFFECT: lines([
    "ctx.effect(() => {",
    "  const timer = setInterval(poll, 30000);      // 注册",
    "  return () => clearInterval(timer);            // 页面关闭 / 插件 reload 时自动执行",
    "});",
    "",
    "// 事件监听同理：addEventListener 之后一定要在 disposer 里 removeEventListener",
    "ctx.effect(() => {",
    "  const onClick = () => ctx.ui.toast('点击');",
    "  document.addEventListener('click', onClick);",
    "  return () => document.removeEventListener('click', onClick);",
    "});",
  ]),
  PUSH: lines([
    "// 根页先画好，再叠子页；push 之后不要再整块改 ctx.ui.root.innerHTML",
    "const detail = ctx.ui.push({",
    "  onPop: () => { /* 子页退出后收尾：停定时器、写回数据 */ }",
    "});",
    "detail.root.appendChild(AntiUI.page({ title: '详情', topbar: AntiUI.topbar({ title: '详情', onBack: () => detail.close() }) }));",
  ]),
  UIKIT: lines([
    "const page = AntiUI.page({",
    "  title: '我的文件',",
    "  subtitle: '只读取你在系统选择器里选中的文件',",
    "  children: [",
    "    AntiUI.button('选择文件', { variant: 'primary', block: true, onClick: pick }),",
    "    list,",
    "  ],",
    "});",
    "ctx.ui.root.appendChild(page);",
  ]),
  THEME: lines([
    "function render(theme) {",
    "  // theme.isDark / theme.bg / theme.card / theme.menuBg / theme.wells …",
    "  ctx.ui.root.style.background = theme.bg;",
    "}",
    "render(ctx.ui.theme);",
    "const off = ctx.ui.onThemeChange(render);",
    "ctx.effect(() => off);   // 页面关闭时取消订阅",
  ]),
  STORAGE: lines([
    "await ctx.storage.set('count', 3);",
    "const count = await ctx.storage.get('count');   // 没有则 null",
    "await ctx.storage.remove('count');",
    "",
    "// 凭据（Cookie / Token）走系统加密存储，需 secrets 权限",
    "await ctx.secrets.set('sid', sid);",
    "const sid = await ctx.secrets.get('sid');",
  ]),
  NET: lines([
    "// 普通 https：不受 CORS 限制，可带自定义头；需 network 权限",
    "const res = await ctx.net.request({",
    "  method: 'POST',",
    "  url: 'https://example.com/api/login',",
    "  headers: { 'Content-Type': 'application/json' },",
    "  body: JSON.stringify({ user, pass }),",
    "});",
    "// res = { status, url, headers, setCookies, text, truncated, bytes }",
    "",
    "// 校内明文 http（实验系统这类没有证书的站点）：需 campus_net 权限",
    "const res2 = await ctx.net.campus({",
    "  method: 'POST',",
    "  url: 'http://210.35.98.35:8003/Login/RemoteUserLogin',",
    "  body: 'userId=xxx&userPass=xxx',",
    "  proxy: 'http://anticraft.top:10004',   // 可选：服务器模式的校园隧道",
    "});",
  ]),
  AI: lines([
    "const text = await ctx.ai.chat('把这段课表说明压缩成三行：\\\\n' + raw, {",
    "  system: '你是一个简洁的助手',",
    "  maxTokens: 512,",
    "});",
    "",
    "const reply = await ctx.ai.chatTools({",
    "  messages: [{ role: 'user', content: '这两门课冲突吗' }],",
    "  tools: [{ name: 'course_info', description: '按课名查时间地点',",
    "            parameters: { type: 'object', properties: { name: { type: 'string' } } } }],",
    "});",
    "// reply = { text, reasoning, toolCalls, usedTools, finishReason }",
  ]),
  NOTIFY: lines([
    "ctx.notify.show({ title: '同步完成', body: '课表已更新' });",
    "ctx.notify.popup({ title: '下课提醒', body: '下一节课在二号楼' });   // 屏幕横幅",
    "ctx.notify.schedule({",
    "  key: 'pre-class',",
    "  title: '还有 15 分钟上课',",
    "  at: Date.now() + 15 * 60 * 1000,   // 毫秒时间戳或 ISO 8601，必须是未来",
    "  popup: true,",
    "});",
    "ctx.notify.cancel('pre-class');",
  ]),
  MISC: lines([
    "await ctx.clipboard.write(url);",
    "const text = await ctx.clipboard.read();            // 需 clipboard 权限并弹窗确认",
    "",
    "const { files } = await ctx.files.pick({ accept: ['text/csv', '.json'], multiple: true });",
    "await ctx.files.save({ name: '导出.csv', mime: 'text/csv', text: csv });",
    "",
    "const { cookieHeader } = await ctx.login.open({",
    "  url: 'https://jwxt.sit.edu.cn',",
    "  cookieUrls: ['https://jwxt.sit.edu.cn'],",
    "  successUrlPrefix: 'https://jwxt.sit.edu.cn/framework',",
    "});",
    "",
    "await ctx.background.keepAlive({ enabled: true, title: '同步中', text: '正在拉取课表' });",
  ]),
  PERM: lines([
    "// ext.json 里声明的静态权限（安装时展示给用户）",
    "\"permissions\": [\"storage\", \"network\", \"notification\"]",
    "",
    "// 运行时授权：显式申请 / 查询",
    "await ctx.permissions.request({ name: 'notification.popup' });",
    "const { granted } = await ctx.permissions.status({ name: 'net.host', host: 'example.com' });",
  ]),
  PACK: lines([
    "# 打包：zip 根目录放 ext.json + main.js（可选 style.css）",
    "zip -r sit.counter.zip ext.json main.js",
    "",
    "# 自检（拦下 localStorage / document.cookie / 未声明 network 却引外链等写法）",
    "dart run tool/market_tool.dart check",
  ]),
  APPDEV: lines([
    "// packages/plugin_*/lib/xxx_plugin.dart",
    "class MyPlugin extends FeaturePlugin {",
    "  @override",
    "  String get id => 'my';",
    "  @override",
    "  String get name => '我的功能';",
    "  @override",
    "  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) => [",
    "    PluginNavItem(icon: Icons.widgets_outlined, label: '我的', order: 40,",
    "                  build: (_) => const MyPage()),",
    "  ];",
    "}",
  ]),
  MARKET: lines([
    "# 发布到市场 / 第三方源（工坊「发布」页生成的就是这些）",
    "ext/<id>/                 # 源码，方便别人查看或继续改",
    "dist/<id>/<版本>.zip        # 安装包，带 sha256",
    "market.json             # 目录",
    "market.json.sig         # Ed25519 签名（公钥内嵌在目录里）",
  ]),
  API: lines([
    "POST /api/login",
    "Content-Type: application/json",
    "",
    "{ \"username\": \"demo\", \"password\": \"***\" }",
    "",
    "200 -> {",
    "  \"access_token\": \"<令牌>\",",
    "  \"token_type\": \"bearer\",",
    "  \"user\": { \"id\": 126, \"username\": \"demo\", \"role\": \"user\" }",
    "}",
  ]),
};

/* ------------------------------------------------------------------ 章节 */

function What() {
  return (
    <Chapter title="拓展是什么" icon="puzzle" kicker="先搞清对象">
      <p>
        App 里的「拓展」不是网页套壳：它是一段在 WebView 里运行的 <strong>Cordis 插件</strong>。
        一个插件就是一个对象，声明自己要用的服务（<span className="mono">inject</span>），
        在 <span className="mono">apply(ctx)</span> 里画界面、注册副作用。宿主把能力挂成
        <span className="mono">ctx</span> 上的服务，插件只跟这些服务打交道，不直接碰 App 的用户数据。
      </p>
      <div className="grid cols-3" style={{ marginTop: 14, alignItems: "stretch" }}>
        <div className="card"><h3>文件只有两个</h3><p><span className="mono">ext.json</span> 描述自己，<span className="mono">main.js</span> 是全部代码（单文件，不能用 import 引本地文件）。</p></div>
        <div className="card"><h3>跑在 WebView 里</h3><p>页面根节点是 <span className="mono">ctx.ui.root</span>；<span className="mono">style.css</span> 会被自动加载。</p></div>
        <div className="card"><h3>能力按权限给</h3><p>存储、联网、AI、通知、文件……都要在清单里声明，安装时列给用户看。</p></div>
      </div>
      <Note title="和 Dart 插件不是一回事">
        Dart 插件（<span className="mono">packages/plugin_*</span>）编译进 App，改它要发版；拓展是运行时装进去的，
        改内容不用发版。想把功能做成 App 的一部分才写 Dart 插件，见附录「写 Dart 功能插件」。
      </Note>
    </Chapter>
  );
}

function First() {
  return (
    <Chapter title="第一个拓展（10 分钟）" icon="code" kicker="动手">
      <p>做一个「记一笔」计数器：点一下加一，关掉再打开数字还在。它只用两个服务：
        <span className="mono">ui</span> 与 <span className="mono">storage</span>。</p>
      <h3>1. 写 ext.json</h3>
      <Code title="ext.json" badge="清单" text={CODE.EXT_JSON}>{CODE.EXT_JSON}</Code>
      <KV k="id">小写字母 / 数字 / <span className="mono">. _ -</span>，3–64 位。存储隔离与安装目录都按它。</KV>
      <KV k="name / desc">name ≤ 20 字，desc ≤ 60 字。</KV>
      <KV k="version">改内容后必须升，市场靠它判断更新。</KV>
      <KV k="main">入口文件，必须是 <span className="mono">.js</span>。</KV>
      <KV k="permissions">见「权限声明与授权」；没声明就用不了对应服务，调用会整个 reject。</KV>
      <h3>2. 写 main.js</h3>
      <Code title="main.js" badge="Cordis" text={CODE.EXT_JS}>{CODE.EXT_JS}</Code>
      <p>三件事值得记住：</p>
      <ul>
        <li><span className="mono">export default</span> 一个对象（或函数），带 <span className="mono">apply(ctx)</span>。</li>
        <li><span className="mono">inject</span> 里的服务没就绪时会等，服务被卸载时插件跟着停。</li>
        <li>界面直接往 <span className="mono">ctx.ui.root</span> 里画；<span className="mono">AntiUI</span> 是自动注入的全局对象。</li>
      </ul>
      <h3>3. 装进来看效果</h3>
      <p>打包成 zip → 「拓展」页 → 添加拓展 → 导入压缩包；或者直接在「拓展工坊」里让 Agent 写。</p>
      <Code title="bash" badge="打包">{CODE.PACK}</Code>
      <Note kind="warn" title="几个常见坑">
        <ul>
          <li><span className="mono">localStorage</span> / <span className="mono">document.cookie</span> 在拓展页会直接抛错（opaque origin），用 <span className="mono">ctx.storage</span>。</li>
          <li>单文件限制：不能用 <span className="mono">import</span> 引别的本地 js，多文件请在打包前自己合并。</li>
          <li>忘了在清单声明权限 → 调用整次 reject，而不是「少一半功能」。</li>
        </ul>
      </Note>
    </Chapter>
  );
}

function Life() {
  return (
    <Chapter title="生命周期与 ctx.effect" icon="refresh" kicker="别留泄漏">
      <p>
        插件加载时执行 <span className="mono">apply</span>；页面关闭、用户停用、热重载时，Cordis 会执行你注册过的
        disposer。所以<strong>所有注册都放进 <span className="mono">ctx.effect(() =&gt; disposer)</span></strong>：
        定时器、事件监听、订阅都算。
      </p>
      <Code title="main.js" badge="effect" text={CODE.EFFECT}>{CODE.EFFECT}</Code>
      <KV k="返回值">disposer 函数；不返回或返回 undefined 表示没有要清理的东西。</KV>
      <KV k="顺序">按注册的逆序执行；父服务的 effect 会先于依赖它的插件清理。</KV>
      <KV k="async">apply 可以是 async；await 到一半被卸载时，已经注册的 effect 仍会被清理。</KV>
      <Note title="为什么强调这个">
        拓展在真机上会反复开关，泄漏一次就是一份后台定时器。写的时候把「注册」和「清理」写在相邻两行，
        是这套运行时最省心的习惯。
      </Note>
    </Chapter>
  );
}
function UiKit() {
  return (
    <Chapter title="AntiUI 组件" icon="widget" kicker="画得跟 App 一样">
      <p>
        每个拓展页都自动注入一套 <strong>AntiUI</strong>（CSS + 全局 <span className="mono">AntiUI</span> 对象）。
        颜色、圆角、按压和弹层动效都跟 App 一致，不用自己写一套样式。<span className="mono">ctx.ui.kit</span> 也指向它。
      </p>
      <Code title="main.js" badge="page" text={CODE.UIKIT}>{CODE.UIKIT}</Code>
      <div className="kv"><div className="kv-k">AntiUI.page</div><div className="kv-v">{'({title, subtitle, topbar?, children})'} → 整页容器（安全区内边距 + 纵向间距）</div></div>
      <div className="kv"><div className="kv-k">AntiUI.topbar</div><div className="kv-v">{'({title, subtitle, onBack, actions})'} → 吸顶栏：返回键 + 标题 + 右侧动作</div></div>
      <div className="kv"><div className="kv-k">AntiUI.card</div><div className="kv-v">{'({title, desc, children, actions, onClick})'} → 与 App 的 AppCard 同款高光描边</div></div>
      <div className="kv"><div className="kv-k">AntiUI.button</div><div className="kv-v">{'(label, {variant, icon, block, onClick})'}；variant = primary / soft / danger / ghost</div></div>
      <div className="kv"><div className="kv-k">AntiUI.list / row</div><div className="kv-v">列表与行：title / desc / icon / side / chevron / onClick</div></div>
      <div className="kv"><div className="kv-k">AntiUI.switchRow</div><div className="kv-v">{'({title, desc, checked, onChange})'} → 带开关的行</div></div>
      <div className="kv"><div className="kv-k">AntiUI.field / input / textarea</div><div className="kv-v">表单控件（label / hint / control）</div></div>
      <div className="kv"><div className="kv-k">AntiUI.segmented / chips</div><div className="kv-v">分段选择（滑块跟手）/ 胶囊筛选</div></div>
      <div className="kv"><div className="kv-k">AntiUI.sheet / confirm / actions</div><div className="kv-v">底部弹层 / 确认框（返回 Promise&lt;boolean&gt;）/ 动作面板</div></div>
      <div className="kv"><div className="kv-k">AntiUI.empty / spinner / loading / progress</div><div className="kv-v">空态、加载与进度</div></div>
      <div className="kv"><div className="kv-k">AntiUI.toast / copy / formatBytes / icon</div><div className="kv-v">提示 / 复制 / 体积格式化 / 内联 SVG 图标</div></div>
      <KV k="图标名">back · chevron · close · check · plus · search · file · folder · download · upload · trash · info · refresh · copy · send · sparkles · link · clock · more</KV>
      <KV k="也可以纯写 CSS">.au-page · .au-card · .au-btn（.au-btn--primary）· .au-list · .au-row · .au-field · .au-input · .au-seg · .au-chip · .au-empty · .au-spinner</KV>
    </Chapter>
  );
}

function ThemeKit() {
  return (
    <Chapter title="主题与夜间模式" icon="palette" kicker="不是近似色">
      <p>
        拓展页和原生界面<strong>共用同一套色板</strong>：宿主把每个令牌以 <span className="mono">--antisit-*</span> 注入页面，
        AntiUI 直接消费它们。切换夜间模式时宿主同时改 <span className="mono">html.dark</span>、<span className="mono">color-scheme</span>
        与全部变量，组件即时换色，不用重画。
      </p>
      <div className="kv"><div className="kv-k">--antisit-bg</div><div className="kv-v">页面底色（SemColors.bg）</div></div>
      <div className="kv"><div className="kv-k">--antisit-card / -card-elevated / -card-solid</div><div className="kv-v">玻璃卡面 / 次级玻璃面 / 需要实底的控件</div></div>
      <div className="kv"><div className="kv-k">--antisit-border / -border-strong</div><div className="kv-v">描边两档</div></div>
      <div className="kv"><div className="kv-k">--antisit-fg / -text-secondary / -text-muted</div><div className="kv-v">文字三级</div></div>
      <div className="kv"><div className="kv-k">--antisit-accent / -accent-soft / -accent-strong</div><div className="kv-v">月光钢蓝：链接、激活、次要高亮</div></div>
      <div className="kv"><div className="kv-k">--antisit-gold / -gold-soft</div><div className="kv-v">香槟金：主 CTA、关键数字、警告</div></div>
      <div className="kv"><div className="kv-k">--antisit-success / -danger</div><div className="kv-v">语义色</div></div>
      <div className="kv"><div className="kv-k">--antisit-radius-*</div><div className="kv-v">card 16 / control 12 / button 16 / dialog 24 / sheet 24 / pill 999</div></div>
      <div className="kv"><div className="kv-k">--antisit-wells</div><div className="kv-v">玻璃主题的场景光斑（CSS 渐变）；墨白 / 竹青返回空数组</div></div>
      <h3>JS 里读主题</h3>
      <Code title="main.js" badge="theme" text={CODE.THEME}>{CODE.THEME}</Code>
      <KV k="theme.wells">{'场景光斑数组（{x, y, radius, color}，x/y 为 -1..1 的对齐坐标）；只有自绘 canvas 背景时才需要'}</KV>
      <Note title="一个坑">
        <span className="mono">ctx.ui.onThemeChange</span> 返回的是取消订阅函数，记得 <span className="mono">ctx.effect(() =&gt; off)</span>，
        否则页面关掉后回调还会跑。
      </Note>
    </Chapter>
  );
}

function Nav() {
  return (
    <Chapter title="页面栈与返回" icon="arrow" kicker="子页怎么叠">
      <p>
        一个拓展可以有多个页面：<span className="mono">ctx.ui.push({'{onPop}'})</span> 叠一层全屏子页，返回
        <span className="mono">{'{root, close}'}</span>。系统返回键 / 左上角箭头先退一层，栈空了才关闭整个拓展。
      </p>
      <Code title="main.js" badge="push" text={CODE.PUSH}>{CODE.PUSH}</Code>
      <KV k="onPop">那层页面退出后回调：适合收尾定时器或写回数据。</KV>
      <KV k="根页">先画好根页再 push；push 之后不要再整块改 <span className="mono">ctx.ui.root.innerHTML</span>，否则会把栈容器一起冲掉。</KV>
      <KV k="其他方法">pop() / depth / canGoBack —— 手动退栈与判断栈深。</KV>
    </Chapter>
  );
}

function Storage() {
  return (
    <Chapter title="存储与凭据" icon="shield" kicker="数据存在哪">
      <p>
        <span className="mono">ctx.storage</span> 是按拓展 id 隔离的键值存储，返回 Promise；
        <span className="mono">ctx.secrets</span> 走系统加密存储（Keystore / Keychain），用来放 Cookie、Token。
      </p>
      <Code title="main.js" badge="storage" text={CODE.STORAGE}>{CODE.STORAGE}</Code>
      <div className="kv"><div className="kv-k">storage</div><div className="kv-v">明文键值，适合设置、历史、缓存；需 storage 权限</div></div>
      <div className="kv"><div className="kv-k">secrets</div><div className="kv-v">加密存储，按拓展隔离；需 secrets 权限</div></div>
      <Note kind="warn" title="别存能立刻作恶的东西">
        浏览器侧没有 <span className="mono">localStorage</span>，也不该把密码直接塞进 storage。
        登录态优先用 <span className="mono">ctx.login</span> 拿到的 Cookie + <span className="mono">ctx.secrets</span> 保存。
      </Note>
    </Chapter>
  );
}

function Net() {
  return (
    <Chapter title="联网：https 与校内 http" icon="link" kicker="绕过 CORS">
      <p>
        网页里直接 <span className="mono">fetch</span> 既受 CORS 限制、也带不上 Cookie，所以有两个原生通道。
      </p>
      <Code title="main.js" badge="net" text={CODE.NET}>{CODE.NET}</Code>
      <div className="kv"><div className="kv-k">net.request</div><div className="kv-v">只允许 https；拒本机 / 内网 / 链路本地 / 保留地址（每次重定向都重校验）；响应 ≤ 2 MB、超时 30 秒；需 network 权限</div></div>
      <div className="kv"><div className="kv-k">net.campus</div><div className="kv-v">只允许 http，目标可以是内网（仍拒本机 / 回环 / CGNAT）；不跟随重定向；需 campus_net 权限</div></div>
      <div className="kv"><div className="kv-k">逐域授权</div><div className="kv-v">每个新域名（含重定向）第一次访问会弹窗，按「拓展 + 域名」记住，可在拓展菜单撤销</div></div>
      <div className="kv"><div className="kv-k">setCookies</div><div className="kv-v">这一路重定向里所有 Set-Cookie 原文，方便自己维护 Cookie 罐子</div></div>
      <KV k="Host / Content-Length / Connection">这类头由底层接管，传了会被忽略</KV>
    </Chapter>
  );
}
function Ai() {
  return (
    <Chapter title="调用 AI" icon="spark" kicker="走用户的模型">
      <p>
        <span className="mono">ctx.ai</span> 走用户在「AI 设置」里配置的模型，Key 不出 App，网页拿不到。
        一问一答最省事；要 Agent 循环用 <span className="mono">chatTools</span>；要打字机效果用流式版本。
      </p>
      <Code title="main.js" badge="ai" text={CODE.AI}>{CODE.AI}</Code>
      <KV k="流式">{'ctx.ai.chatToolsStream({streamId, messages, tools})；增量从 antiSIT.on("ai.stream", cb) 推下来，返回值仍是完整回复'}</KV>
      <KV k="费用">调用可能产生费用，所以需要 ai 权限；没配好 AI 或没声明权限会直接 reject，不会静默返回空串。</KV>
    </Chapter>
  );
}

function Notify() {
  return (
    <Chapter title="通知" icon="notifications" kicker="即时 / 定时 / 横幅">
      <p>
        通知走 App 自己的本地通知渠道（<span className="mono">ext_notify</span>），不依赖「上课提醒」插件；
        定时通知由系统闹钟在进程外拉起，<strong>App 没开也能到点弹出</strong>。
      </p>
      <Code title="main.js" badge="notify" text={CODE.NOTIFY}>{CODE.NOTIFY}</Code>
      <div className="kv"><div className="kv-k">show</div><div className="kv-v">立即发一条；同 key 覆盖上一条；首次调用会申请通知权限</div></div>
      <div className="kv"><div className="kv-k">popup</div><div className="kv-v">高优先级横幅（ext_popup 渠道）；首次使用弹一次运行时确认</div></div>
      <div className="kv"><div className="kv-k">schedule</div><div className="kv-v">at 为 ISO 8601 或毫秒时间戳（必须是未来）；App 没开也能到点弹</div></div>
      <div className="kv"><div className="kv-k">cancel / cancelAll</div><div className="kv-v">撤销一条 / 撤销本拓展排过的全部（不动课表提醒）</div></div>
      <Note title="前台 / 后台是两条路，插件不用管">
        App 在前台时 Android 会压掉自己发的横幅，所以这时改为页内顶部横幅（同 key 覆盖，最多 3 条，6 秒自动收起），
        系统通知照旧发一条静音的留通知栏；退到后台只有系统通知。这条兜底由内核负责。
      </Note>
    </Chapter>
  );
}

function Misc() {
  return (
    <Chapter title="剪贴板 · 文件 · 登录 · 保活" icon="copy" kicker="剩下的能力">
      <Code title="main.js" badge="misc" text={CODE.MISC}>{CODE.MISC}</Code>
      <div className="kv"><div className="kv-k">clipboard.read</div><div className="kv-v">敏感动作：首次或未记住时弹「读取剪贴板」确认，拒绝则 reject</div></div>
      <div className="kv"><div className="kv-k">files</div><div className="kv-v">只经系统文件选择器；不返回路径、不能扫描目录；单文件 ≤ 8 MB，一次 ≤ 10 个 / 合计 ≤ 16 MB</div></div>
      <div className="kv"><div className="kv-k">login.open</div><div className="kv-v">可见登录页，返回 cookies / cookieHeader；给了 successUrlPrefix 必须真的跳到该前缀才算成功</div></div>
      <div className="kv"><div className="kv-k">login.clear</div><div className="kv-v">清这些域的 Cookie；ok=false 表示没清干净，应提示用户清应用数据</div></div>
      <div className="kv"><div className="kv-k">background.keepAlive</div><div className="kv-v">前台服务 + 常驻通知；需 background 权限并会弹确认</div></div>
      <div className="kv"><div className="kv-k">card</div><div className="kv-v">setName / setDesc / setIcon —— 改拓展列表卡片上的显示值</div></div>
    </Chapter>
  );
}

function Perm() {
  return (
    <Chapter title="权限声明与授权" icon="shield" kicker="安装时就要说清">
      <p>
        敏感接口要在 <span className="mono">ext.json</span> 里声明，安装弹窗会翻成人话列给用户；
        其中几项还需要运行时授权（逐项开关）。
      </p>
      <Code title="ext.json" badge="permissions" text={CODE.PERM}>{CODE.PERM}</Code>
      <div className="kv"><div className="kv-k">storage</div><div className="kv-v">本机保存数据；不声明就调用 ctx.storage → reject</div></div>
      <div className="kv"><div className="kv-k">network</div><div className="kv-v">运行时联网；市场拓展默认禁网（CSP connect-src 'none'）</div></div>
      <div className="kv"><div className="kv-k">campus_net</div><div className="kv-v">校内明文 http 站点（net.campus）</div></div>
      <div className="kv"><div className="kv-k">ai</div><div className="kv-v">调用 AI（走用户模型与 Key，可能产生费用）</div></div>
      <div className="kv"><div className="kv-k">notification</div><div className="kv-v">即时 / 定时通知</div></div>
      <div className="kv"><div className="kv-k">secrets</div><div className="kv-v">加密保存 Cookie / Token</div></div>
      <div className="kv"><div className="kv-k">clipboard / files / login / background</div><div className="kv-v">剪贴板 / 文件选择器 / 可见登录页 / 后台保活</div></div>
      <Note kind="warn" title="问不到用户 ≠ 用户拒绝">
        授权框只在 App 前台且页面可用时弹；后台定时器、页面刚关掉这些时刻问不到，此时内核只拒绝这一次调用，
        <strong>不记录</strong>成「已拒绝」，下次能问时还会再问。
      </Note>
      <KV k="拒绝后的样子">受保护调用整次 reject（"这条拓展没有声明…权限（background），接口已拒"），插件要自己 catch 并给出人话提示。</KV>
    </Chapter>
  );
}
function Pack() {
  return (
    <Chapter title="打包、自检、安装" icon="download" kicker="交给别人装">
      <p>
        打包方式随意：<span className="mono">zip -r myapp.zip myapp/</span> 这种所有文件都在同一顶层目录的，
        解压时会自动去掉那一层。根目录必须有 <span className="mono">ext.json</span>。
      </p>
      <Code title="bash" badge="package" text={CODE.PACK}>{CODE.PACK}</Code>
      <div className="kv"><div className="kv-k">体积</div><div className="kv-v">最多 200 个文件 / 解压后 8 MB</div></div>
      <div className="kv"><div className="kv-k">安全</div><div className="kv-v">绝对路径、<span className="mono">..</span>、盘符这类条目整条丢弃（zip-slip），绝不写到解压目录外</div></div>
      <div className="kv"><div className="kv-k">解压位置</div><div className="kv-v">&lt;应用文档目录&gt;/ext/&lt;拓展 id&gt;/；删除这条拓展时连同目录一起清掉</div></div>
      <h3>三种装法</h3>
      <ul>
        <li>「拓展」页 → 添加拓展 → 导入压缩包；</li>
        <li>扫一扫安装码（<span className="mono">{'{"antisit":"ext","url":"https://…/x.zip","sha256":"…"}'}</span>，只认 https 且必须带 sha256）；</li>
        <li>在「拓展工坊」里直接预览 / 安装自己写的草稿。</li>
      </ul>
      <Note title="自检能提前撞上常见错误">
        <span className="mono">dart run tool/market_tool.dart check</span> 会拦下 <span className="mono">localStorage</span>、
        <span className="mono">document.cookie</span>、未声明 <span className="mono">network</span> 却引外链资源这类写法；
        工坊保存草稿时「自检」查同一张表。
      </Note>
    </Chapter>
  );
}

function Market() {
  return (
    <Chapter title="发布到市场 / 第三方源" icon="external" kicker="别人怎么装到">
      <p>
        市场目录由维护者签名，App 验签通过才显示；每个 zip 还带 sha256，对不上就不解压。
        <strong>不需要官方收录也能发</strong>：作者在自己仓库用同一套工具签名打包，别人在「添加第三方源」里粘贴
        仓库名 + 核对公钥指纹即可安装，第三方条目明确标注「未审核」，同一个 id 只能由一个源管。
      </p>
      <Code title="bash" badge="market" text={CODE.MARKET}>{CODE.MARKET}</Code>
      <div className="kv"><div className="kv-k">目录结构</div><div className="kv-v">ext/&lt;id&gt;/（源码）+ dist/&lt;id&gt;/&lt;版本&gt;.zip + market.json + market.json.sig</div></div>
      <div className="kv"><div className="kv-k">签名</div><div className="kv-v">首次发布时本机生成 Ed25519 密钥，私钥只进 Keystore；清除 App 数据 / 换机会换密钥</div></div>
      <div className="kv"><div className="kv-k">更新</div><div className="kv-v">保留拓展自己的数据；卸载一并清掉</div></div>
      <Note title="工坊里点「发布」就能完成">
        「拓展工坊」顶栏「发布」或「⋯ → 连接 GitHub / Gitee 发布…」：填 Token 与 <span className="mono">所有者/仓库</span>，
        仓库必须公开；发布后给出<b>直装二维码</b>（扫一扫直接装）与<b>源二维码</b>（添加第三方源）。
      </Note>
    </Chapter>
  );
}

function Migrate() {
  return (
    <Chapter title="旧 html 拓展迁移" icon="refresh" kicker="从三件套过来">
      <ul>
        <li>旧 html 压缩包（<span className="mono">index.html</span> 三件套）不再执行，列表里标「旧版网页拓展（需迁移）」；</li>
        <li>迁移方式：把页面逻辑改成 <span className="mono">main.js</span> 里的 Cordis 插件，<span className="mono">ext.json</span> 填好 id / 权限，重新打成 zip 导入；</li>
        <li>或者直接在「拓展工坊」里让 Agent 重写；</li>
        <li>旧拓展的键值数据（<span className="mono">plugin.ext.data.&lt;id&gt;.*</span>）仍按 id 保留，迁移后 id 不变就能接着读。</li>
      </ul>
      <Note kind="warn" title="市场里的 bundle 也变了">
        本版本起市场 <span className="mono">type: "bundle"</span> 条目必须带 <span className="mono">"runtime": "cordis"</span>，
        zip 里必须是 <span className="mono">ext.json</span> + <span className="mono">main.js</span>；旧目录条目会提示「还是旧版网页格式，请等作者升级后再装」。
      </Note>
    </Chapter>
  );
}

function Safety() {
  return (
    <Chapter title="安全边界" icon="shield" kicker="知道红线在哪">
      <ul>
        <li>内联页是 opaque origin：<span className="mono">localStorage</span> / <span className="mono">sessionStorage</span> / <span className="mono">document.cookie</span> 会抛错；</li>
        <li>市场包默认禁网，声明 <span className="mono">network</span> 才允许 <span className="mono">https:</span> 的 fetch / 图片 / 字体；</li>
        <li>文件访问只经过系统选择器：拿不到路径、不能扫描目录、拿不到用户没选的文件；</li>
        <li>不引外部脚本：审核过的代码就是手机上跑的那份；</li>
        <li>App 的用户数据（学号、课表、成绩、凭据）不在接口里，权限门防的是误用，不是完整沙箱。</li>
      </ul>
    </Chapter>
  );
}

function AppDev() {
  return (
    <Chapter title="附录：写 Dart 功能插件" icon="code" kicker="改 App 本体">
      <p>
        拓展做不了的功能（新的底栏页、新的主题色板、新的 AI 提供商）才需要写 Dart 插件：
        一个插件 = 一个 Dart 包，加进 pub workspace，重写贡献方法即可。
      </p>
      <Code title="dart" badge="plugin" text={CODE.APPDEV}>{CODE.APPDEV}</Code>
      <KV k="加一个插件">新建包 → 根 pubspec 的 workspace 列表加一行 → 需要时登册 → 跑生成器 → 跑 analyze</KV>
      <KV k="生成器">dart run tool/gen_plugins.dart；依赖引用不存在的 id / 自依赖 / 硬依赖成环会直接报错退出</KV>
      <KV k="往上跳">插件不能引用宿主页面（会成环）；登录成功回主壳这类需求改成宿主注入的回调</KV>
      <p style={{ marginTop: 12 }}>
        完整说明见 <a className="mono" href={SITE.repos.github.url + "/blob/main/docs/plugins.md"} target="_blank" rel="noreferrer">docs/plugins.md</a>。
      </p>
    </Chapter>
  );
}

function ApiSpec() {
  return (
    <Chapter title="附录：开放接口规约" icon="link" kicker="自建后端">
      <p>
        服务器模式的地址可以是任意部署了同一套开放接口的服务器。只看规约就能用任意语言实现出相同接口形式的服务端：
        路径、方法、请求 / 响应结构、状态码、错误语义一致。
      </p>
      <Code title="http" badge="login" text={CODE.API}>{CODE.API}</Code>
      <div className="kv"><div className="kv-k">鉴权头</div><div className="kv-v">Authorization: Bearer &lt;access_token&gt;</div></div>
      <div className="kv"><div className="kv-k">成功字段</div><div className="kv-v">{'各接口自定义，但均含 "ok": true（登录 / 续期除外）'}</div></div>
      <div className="kv"><div className="kv-k">错误</div><div className="kv-v">{'统一 {"detail":"<中文说明>"}；422 校验错误时 detail 是数组，loc 指明字段路径'}</div></div>
      <div className="kv"><div className="kv-k">限流</div><div className="kv-v">{'按客户端 IP 计数，超限统一 429 {"detail":"请求过于频繁，请稍后再试"}'}</div></div>
      <div className="kv"><div className="kv-k">健康检查</div><div className="kv-v">GET /api/health（免鉴权）</div></div>
      <p style={{ marginTop: 12 }}>
        完整规约见 <a className="mono" href={SITE.repos.github.url + "/blob/main/docs/campus-api.md"} target="_blank" rel="noreferrer">docs/campus-api.md</a>。
      </p>
    </Chapter>
  );
}