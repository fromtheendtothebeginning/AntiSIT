import Code from "../components/Code.jsx";
import Icon from "../components/Icon.jsx";
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

// 章节卡**不做入场动画**：切章节时内容必须立刻可见（历史 bug：切章后整块停在 opacity:0）。
function Chapter({ title, icon, kicker, children }) {
  return (
    <section className="doc-section">
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
    </section>
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
    <Chapter title="拓展是什么" icon="puzzle" kicker="先弄明白它是什么">
      <p>
        拓展就是你自己写的一段小程序，装进 App 里就能用，跟装浏览器插件差不多。
        它不是把网页塞进壳里：App 把存储、联网、通知这些能力打包成 <span className="mono">ctx</span>，
        你的代码只跟它打交道，碰不到别人的课表和成绩。
      </p>
      <div className="grid cols-3" style={{ marginTop: 14, alignItems: "stretch" }}>
        <div className="card"><h3>只有两个文件</h3><p>一份 <span className="mono">ext.json</span> 写清自己是谁，一份 <span className="mono">main.js</span> 放全部代码。</p></div>
        <div className="card"><h3>界面现成的</h3><p>不用自己写样式，App 提供了一套跟本体长得一样的组件，直接用。</p></div>
        <div className="card"><h3>用之前先说</h3><p>要存东西、要联网、要发通知，都得先在清单里写明白，装的时候会列给使用者看。</p></div>
      </div>
      <Note title="和改 App 本体不是一回事">
        Dart 插件是编译进 App 的，改完要发新版本；拓展是运行时装进去的，改完不用发版。
        只有想让功能成为 App 的一部分，才需要去写 Dart 插件，见附录「写 Dart 功能插件」。
      </Note>
    </Chapter>
  );
}

function First() {
  return (
    <Chapter title="第一个拓展（10 分钟）" icon="code" kicker="跟着做一遍">
      <p>做一个「记一笔」：点一下数字加一，关掉再打开还在。这是最小的完整例子。</p>
      <h3>1. 写 ext.json</h3>
      <Code title="ext.json" badge="清单" text={CODE.EXT_JSON}>{CODE.EXT_JSON}</Code>
      <KV k="id">拓展的唯一名字，只能用小写字母、数字和 <span className="mono">. _ -</span>，3 到 64 个字符。不同拓展不能重名。</KV>
      <KV k="name / desc">名字和一句话简介，分别不超过 20 字和 60 字。</KV>
      <KV k="version">版本号。改了内容就要升，别人靠它判断有没有更新。</KV>
      <KV k="main">代码文件名，必须是 <span className="mono">.js</span>。</KV>
      <KV k="permissions">要用到哪些能力，写在这里。漏写了调用会直接失败，见「权限声明与授权」。</KV>
      <h3>2. 写 main.js</h3>
      <Code title="main.js" badge="Cordis" text={CODE.EXT_JS}>{CODE.EXT_JS}</Code>
      <p>记住这三点就够了：</p>
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
    <Chapter title="生命周期与 ctx.effect" icon="refresh" kicker="别忘了收尾">
      <p>
        打开页面时跑 <span className="mono">apply</span>，关掉页面时得把你开的东西收干净。
        所以凡是定时器、事件监听、订阅，都写进 <span className="mono">ctx.effect()</span>——
        它会帮你记住怎么撤销，页面一关自动清理。
      </p>
      <Code title="main.js" badge="effect" text={CODE.EFFECT}>{CODE.EFFECT}</Code>
      <KV k="返回值">一个「怎么收尾」的函数。没什么要收的就别返回。</KV>
      <KV k="顺序">按注册的倒序清理。</KV>
      <KV k="async">apply 可以写成 async。就算 await 到一半页面被关掉，已经注册的也会被清掉。</KV>
      <Note title="为什么要这么麻烦">
        手机上拓展会被反复开关。漏掉一个定时器，它就一直挂在后台耗电。
        把「开」和「关」写在相邻两行，最省心。
      </Note>
    </Chapter>
  );
}
function UiKit() {
  return (
    <Chapter title="AntiUI 组件" icon="widget" kicker="不用自己写样式">
      <p>
        别自己写样式。App 已经准备好一套组件，叫 <strong>AntiUI</strong>，长得跟本体一模一样——
        按钮、卡片、列表、开关、弹层都有，直接用就行。深浅色也自动跟着切换。
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
      <KV k="想手写也行">直接用这些 class：.au-page · .au-card · .au-btn（.au-btn--primary）· .au-list · .au-row · .au-field · .au-input · .au-seg · .au-chip · .au-empty · .au-spinner</KV>
    </Chapter>
  );
}

function ThemeKit() {
  return (
    <Chapter title="主题与夜间模式" icon="palette" kicker="深浅色自动跟随">
      <p>
        深浅色不用你操心。App 把当前配色写成一组 CSS 变量，组件直接读它们。
        用户切到夜间模式，你的页面立刻跟着变，不用重画、不用刷新。
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
      <h3>要在代码里读颜色</h3>
      <Code title="main.js" badge="theme" text={CODE.THEME}>{CODE.THEME}</Code>
      <KV k="theme.wells">{'场景光斑数组（{x, y, radius, color}，x/y 为 -1..1 的对齐坐标）；只有自绘 canvas 背景时才需要'}</KV>
      <Note title="别忘了取消">
        <span className="mono">onThemeChange</span> 返回的是「取消订阅」函数，记得放进 <span className="mono">ctx.effect</span>，
        不然页面关了回调还在跑。
      </Note>
    </Chapter>
  );
}

function Nav() {
  return (
    <Chapter title="页面栈与返回" icon="arrow" kicker="多页怎么翻">
      <p>
        一个拓展可以有多个页面：<span className="mono">ctx.ui.push({'{onPop}'})</span> 叠一层全屏子页，返回
        <span className="mono">{'{root, close}'}</span>。系统返回键 / 左上角箭头先退一层，栈空了才关闭整个拓展。
      </p>
      <Code title="main.js" badge="push" text={CODE.PUSH}>{CODE.PUSH}</Code>
      <KV k="onPop">这一层被退出时触发，适合在这儿收尾、存数据。</KV>
      <KV k="根页">先把第一页画好再叠新的。叠完之后别再整块改 <span className="mono">ctx.ui.root</span>，会把下面的页面一起冲掉。</KV>
      <KV k="其它">pop() 手动退一层，depth 看有几层，canGoBack 判断还能不能退。</KV>
    </Chapter>
  );
}

function Storage() {
  return (
    <Chapter title="存储与凭据" icon="shield" kicker="存东西">
      <p>
        存数据用 <span className="mono">ctx.storage</span>，每个拓展各存各的，互不干扰。
        存密码、Cookie 这类敏感东西用 <span className="mono">ctx.secrets</span>，它会走系统加密。
      </p>
      <Code title="main.js" badge="storage" text={CODE.STORAGE}>{CODE.STORAGE}</Code>
      <div className="kv"><div className="kv-k">storage</div><div className="kv-v">明文键值，适合设置、历史、缓存；需 storage 权限</div></div>
      <div className="kv"><div className="kv-k">secrets</div><div className="kv-v">加密存储，按拓展隔离；需 secrets 权限</div></div>
      <Note kind="warn" title="这里没有 localStorage">
        拓展页里用不了 <span className="mono">localStorage</span>，写了会直接报错。
        登录态这类敏感信息，用 <span className="mono">ctx.login</span> 拿到的 Cookie 配 <span className="mono">ctx.secrets</span> 保存。
      </Note>
    </Chapter>
  );
}

function Net() {
  return (
    <Chapter title="联网：https 与校内 http" icon="link" kicker="怎么联网">
      <p>
        网页里直接 <span className="mono">fetch</span> 会被跨域拦、也带不上 Cookie。
        所以 App 给了两条原生通道，一条走公网 https，一条走校内 http。
      </p>
      <Code title="main.js" badge="net" text={CODE.NET}>{CODE.NET}</Code>
      <div className="kv"><div className="kv-k">net.request</div><div className="kv-v">走公网 https。访问不到本机和内网地址；一次响应最多 2 MB、30 秒超时。需要 network 权限</div></div>
      <div className="kv"><div className="kv-k">net.campus</div><div className="kv-v">走校内 http，给实验系统这类没有证书的站点准备的。不会自动跟着跳转。需要 campus_net 权限</div></div>
      <div className="kv"><div className="kv-k">第一次问用户</div><div className="kv-v">每个新域名第一次访问会弹窗问一句，同意后按「拓展 + 域名」记住，可以在拓展菜单里撤掉</div></div>
      <div className="kv"><div className="kv-k">setCookies</div><div className="kv-v">这一路收到的所有 Set-Cookie，方便你自己维护登录态</div></div>
      <KV k="几个头不用管">Host、Content-Length、Connection 由底层接管，传了也会被忽略</KV>
    </Chapter>
  );
}
function Ai() {
  return (
    <Chapter title="调用 AI" icon="spark" kicker="不用自己申请 Key">
      <p>
        想让拓展用上 AI？不用自己申请 Key。<span className="mono">ctx.ai</span> 走的是用户在「AI 设置」里配好的模型，
        Key 一直在 App 里，你的代码拿不到。
      </p>
      <p>三种用法：一问一答最省事；要让 AI 自己调工具用 <span className="mono">chatTools</span>；
        想一个字一个字往外蹦用流式版本。</p>
      <Code title="main.js" badge="ai" text={CODE.AI}>{CODE.AI}</Code>
      <KV k="流式">{'ctx.ai.chatToolsStream({streamId, messages, tools})，增量从 antiSIT.on("ai.stream", cb) 推过来，返回值还是完整回复'}</KV>
      <KV k="费用">调用会产生费用，所以要 ai 权限。没配好 AI 或没写权限，调用会直接失败，不会悄悄返回空字符串。</KV>
    </Chapter>
  );
}

function Notify() {
  return (
    <Chapter title="通知" icon="notifications" kicker="发提醒">
      <p>
        通知走 App 自己的渠道，不依赖「上课提醒」那个插件。
        定时通知交给系统闹钟，<strong>App 没打开也会准时弹</strong>。
      </p>
      <Code title="main.js" badge="notify" text={CODE.NOTIFY}>{CODE.NOTIFY}</Code>
      <div className="kv"><div className="kv-k">show</div><div className="kv-v">立刻发一条。同一个 key 会覆盖上一条。第一次用会申请通知权限</div></div>
      <div className="kv"><div className="kv-k">popup</div><div className="kv-v">在屏幕顶部弹横幅。第一次用会问一次</div></div>
      <div className="kv"><div className="kv-k">schedule</div><div className="kv-v">定时发。at 填时间（必须是将来的）</div></div>
      <div className="kv"><div className="kv-k">cancel / cancelAll</div><div className="kv-v">撤掉一条 / 撤掉本拓展排过的全部（不会动上课提醒）</div></div>
      <Note title="前台后台不用你判断">
        用户正开着 App 时，系统会压掉横幅，这时 App 会改成在页面顶部弹一条；退到后台就走系统通知。
        这些兜底 App 已经做好了，你照常调用就行。
      </Note>
    </Chapter>
  );
}

function Misc() {
  return (
    <Chapter title="剪贴板 · 文件 · 登录 · 保活" icon="copy" kicker="其它能力">
      <Code title="main.js" badge="misc" text={CODE.MISC}>{CODE.MISC}</Code>
      <div className="kv"><div className="kv-k">clipboard.read</div><div className="kv-v">读剪贴板算敏感动作，第一次会弹窗问一句，拒绝就调用失败</div></div>
      <div className="kv"><div className="kv-k">files</div><div className="kv-v">只能读用户自己在系统选择器里选中的文件。拿不到路径、不能翻目录。单个最多 8 MB</div></div>
      <div className="kv"><div className="kv-k">login.open</div><div className="kv-v">弹出一个登录页让用户登录，登录完把 Cookie 给你</div></div>
      <div className="kv"><div className="kv-k">login.clear</div><div className="kv-v">退出登录，清掉这些域的 Cookie</div></div>
      <div className="kv"><div className="kv-k">background.keepAlive</div><div className="kv-v">让拓展在后台继续跑（会显示一条常驻通知）。需要 background 权限，开启前会问一次</div></div>
      <div className="kv"><div className="kv-k">card</div><div className="kv-v">改拓展在列表里显示的名字、简介和图标</div></div>
    </Chapter>
  );
}

function Perm() {
  return (
    <Chapter title="权限声明与授权" icon="shield" kicker="先说清楚再用">
      <p>
        要用到敏感能力，得先在 <span className="mono">ext.json</span> 里写清楚。
        安装时 App 会翻成人话列给使用者看，由他决定装不装。
      </p>
      <Code title="ext.json" badge="permissions" text={CODE.PERM}>{CODE.PERM}</Code>
      <div className="kv"><div className="kv-k">storage</div><div className="kv-v">在本机存数据。不写就用不了 ctx.storage</div></div>
      <div className="kv"><div className="kv-k">network</div><div className="kv-v">联网。市场装的拓展默认不让联网，写了才放开</div></div>
      <div className="kv"><div className="kv-k">campus_net</div><div className="kv-v">访问校内的 http 站点（实验系统、报告系统这类）</div></div>
      <div className="kv"><div className="kv-k">ai</div><div className="kv-v">调用 AI。用的是用户的模型，可能产生费用</div></div>
      <div className="kv"><div className="kv-k">notification</div><div className="kv-v">发通知，包括定时通知</div></div>
      <div className="kv"><div className="kv-k">secrets</div><div className="kv-v">加密保存 Cookie、Token 这类凭据</div></div>
      <div className="kv"><div className="kv-k">clipboard / files / login / background</div><div className="kv-v">读写剪贴板 / 读用户选中的文件 / 弹登录页 / 后台保活</div></div>
      <Note kind="warn" title="没问到 ≠ 用户拒绝">
        授权框只在 App 开着、页面在的时候弹。后台定时器触发、页面刚好关掉这些时刻是问不到的，
        这时只拒绝这一次，<strong>不会记成「已拒绝」</strong>，下次有机会还会再问。
      </Note>
      <KV k="被拒之后">调用会整个失败，报「这条拓展没有声明…权限」。记得 catch 住，给用户一句人话提示。</KV>
    </Chapter>
  );
}
function Pack() {
  return (
    <Chapter title="打包、自检、安装" icon="download" kicker="打包给别人">
      <p>
        把两个文件打个 zip 就行。如果所有文件都在同一个文件夹里，解压时会自动去掉那一层。
        根目录必须有 <span className="mono">ext.json</span>。
      </p>
      <Code title="bash" badge="package" text={CODE.PACK}>{CODE.PACK}</Code>
      <div className="kv"><div className="kv-k">体积</div><div className="kv-v">最多 200 个文件，解压后不超过 8 MB</div></div>
      <div className="kv"><div className="kv-k">安全</div><div className="kv-v">包里带绝对路径或 <span className="mono">..</span> 的条目会被直接丢掉，不会写到目录外面</div></div>
      <div className="kv"><div className="kv-k">装在哪</div><div className="kv-v">应用目录 / ext / 你的拓展 id。卸载拓展时整个目录一起删</div></div>
      <h3>怎么装进去</h3>
      <ul>
        <li>「拓展」页 → 添加拓展 → 导入压缩包；</li>
        <li>扫安装码（一段 JSON，只认 https，必须带 sha256）；</li>
        <li>在「拓展工坊」里直接预览、安装自己写的草稿。</li>
      </ul>
      <Note title="先自检一遍">
        <span className="mono">dart run tool/market_tool.dart check</span> 会帮你揪出用错 <span className="mono">localStorage</span>、
        没声明 <span className="mono">network</span> 却引外链这类问题，省得装上去才发现。
      </Note>
    </Chapter>
  );
}

function Market() {
  return (
    <Chapter title="发布到市场 / 第三方源" icon="external" kicker="让别人也能装上">
      <p>
        想让别人也装上？两条路：投稿到官方市场，或者自己发。
      </p>
      <p>
        <strong>不投稿也能发。</strong>你在自己仓库里签名打包，别人在「添加第三方源」里填上仓库名、
        核对一下指纹就能装。第三方条目会标注「未审核」，同一个拓展只能由一个源来管。
      </p>
      <Code title="bash" badge="market" text={CODE.MARKET}>{CODE.MARKET}</Code>
      <div className="kv"><div className="kv-k">仓库里放什么</div><div className="kv-v">源码、打包好的 zip、目录文件和它的签名</div></div>
      <div className="kv"><div className="kv-k">签名</div><div className="kv-v">第一次发布时在你手机上生成密钥，私钥只进系统加密存储。清了 App 数据或换手机，密钥会换</div></div>
      <div className="kv"><div className="kv-k">更新</div><div className="kv-v">更新会保留拓展自己存的数据，卸载才一起清掉</div></div>
      <Note title="工坊里点「发布」就行">
        「拓展工坊」顶栏的「发布」：填上 Token 和仓库（必须公开），它帮你推上去，
        还会给出<b>直装二维码</b>（别人扫一下就装）和<b>源二维码</b>（别人扫一下加源）。
      </Note>
    </Chapter>
  );
}

function Migrate() {
  return (
    <Chapter title="旧 html 拓展迁移" icon="refresh" kicker="老包怎么办">
      <ul>
        <li>老式的 html 包不再运行，列表里会标成「旧版网页拓展（需迁移）」；</li>
        <li>怎么迁：把页面逻辑改写到 <span className="mono">main.js</span> 里，<span className="mono">ext.json</span> 填好 id 和权限，重新打包导入；</li>
        <li>懒得改：在「拓展工坊」里让 Agent 帮你重写一遍；</li>
        <li>老拓展存的数据还在，只要 id 不变，迁完照样能读。</li>
      </ul>
      <Note kind="warn" title="市场里的包也改了">
        现在市场里的拓展必须标明是新版格式，包里必须是 <span className="mono">ext.json</span> +
        <span className="mono">main.js</span>。还是老格式的条目会提示「请等作者升级后再装」。
      </Note>
    </Chapter>
  );
}

function Safety() {
  return (
    <Chapter title="安全边界" icon="shield" kicker="哪些碰不得">
      <ul>
        <li>用不了 <span className="mono">localStorage</span>、<span className="mono">document.cookie</span>，写了会报错；</li>
        <li>市场装的拓展默认不能联网，声明了 network 才放开；</li>
        <li>文件只能读用户自己选中的，拿不到路径、翻不了目录；</li>
        <li>不能引外部脚本——审过的代码就是手机上跑的那份；</li>
        <li>学号、课表、成绩、凭据这些不在接口里。权限这道门防的是误用，不是完整沙箱。</li>
      </ul>
    </Chapter>
  );
}

function AppDev() {
  return (
    <Chapter title="附录：写 Dart 功能插件" icon="code" kicker="拓展做不了时才写">
      <p>
        拓展做不到的（要加底栏页、要加新配色、要接新的 AI 厂商）才需要改 App 本体：
        一个插件就是一个 Dart 包，加进工作区，写清楚它贡献什么就行。
      </p>
      <Code title="dart" badge="plugin" text={CODE.APPDEV}>{CODE.APPDEV}</Code>
      <KV k="加一个插件">新建包 → 在根 pubspec 的列表里加一行 → 跑生成器 → 跑 analyze</KV>
      <KV k="生成器">dart run tool/gen_plugins.dart。依赖写了不存在的 id、自己依赖自己、依赖成环，它会直接报错</KV>
      <KV k="注意">插件不能反过来引用主程序的页面（会绕成环）。要跳回主界面，用主程序注入的回调</KV>
      <p style={{ marginTop: 12 }}>
        完整说明见 <a className="mono" href={SITE.repos.github.url + "/blob/main/docs/plugins.md"} target="_blank" rel="noreferrer">docs/plugins.md</a>。
      </p>
    </Chapter>
  );
}

function ApiSpec() {
  return (
    <Chapter title="附录：开放接口规约" icon="link" kicker="自己搭服务器">
      <p>
        服务器模式下，地址可以填你自己搭的服务器。只要接口形式对得上，用什么语言写都行。
      </p>
      <Code title="http" badge="login" text={CODE.API}>{CODE.API}</Code>
      <div className="kv"><div className="kv-k">怎么带令牌</div><div className="kv-v">请求头里加 Authorization: Bearer &lt;令牌&gt;</div></div>
      <div className="kv"><div className="kv-k">成功</div><div className="kv-v">{'各接口自己定义，但都会带 "ok": true（登录和续期除外）'}</div></div>
      <div className="kv"><div className="kv-k">出错</div><div className="kv-v">{'统一返回 {"detail":"中文说明"}。参数校验失败时 detail 是数组，会指明哪个字段不对'}</div></div>
      <div className="kv"><div className="kv-k">限流</div><div className="kv-v">按 IP 计数，超了返回 429</div></div>
      <div className="kv"><div className="kv-k">探活</div><div className="kv-v">GET /api/health，不用令牌</div></div>
      <p style={{ marginTop: 12 }}>
        完整规约见 <a className="mono" href={SITE.repos.github.url + "/blob/main/docs/campus-api.md"} target="_blank" rel="noreferrer">docs/campus-api.md</a>。
      </p>
    </Chapter>
  );
}