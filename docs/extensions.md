# 拓展（Cordis 插件）

「拓展」是底栏的一个页面（插件 id `ext`）：**默认开启**、硬依赖 WebView 内核
（`webview`），装好即可用；关掉内核会把「拓展」一起关掉，不需要它也可以在
「插件管理」里关掉。

本版本的拓展运行时已经换成 **[Cordis](https://github.com/cordiverse/cordis)**
（DSH 同款插件框架）：一个拓展就是一段在 WebView 里运行的 Cordis 插件，
通过 `inject` 声明自己要用的服务，通过 `ctx.effect()` 注册可逆副作用。
App 不再执行任意 `index.html`；旧的 html 压缩包会标成「旧版网页拓展（需迁移）」。

App 内置一个 **「拓展工坊」**（`builtin.workshop`）：它本身也是一个 Cordis 拓展，
用 Agent 帮你写新的 Cordis 拓展（见下文）。

## 加法

| 方式 | 说明 |
|---|---|
| 填写网址 | 名称 + `http(s)` 网址，作为网页书签打开；不跑 Cordis，也不注入拓展服务 |
| 导入 Cordis 压缩包 | zip 根目录放 `ext.json` + `main.js`（可选 `style.css`），导入后解压到本地 |
| 导入 JSON | 粘贴网页书签（单条或数组）；Cordis 拓展请用压缩包 |
| 扫码添加 | 「拓展」页右上角扫一扫：普通网址 →「添加链接」；规定格式的安装码 →「下载拓展」 |
| 编译前固定 | 在 `packages/plugin_ext/lib/builtin_extensions.dart` 的 `kBuiltinExtensions` 里加 |
| 拓展工坊 | 在「拓展」页打开内置工坊，用自然语言让 Agent 写一个 Cordis 拓展 |

拓展卡片默认按添加先后排列；「我的」标题栏的**排序**入口可以拖动自定义顺序，
「恢复默认」回原始顺序。排序结果存在本机，重启 App 不变；新加的拓展排在最后。

在「我的」页**长按卡片**也能整理：按住不放卡片抬起跟手拖动换位（落点处留出占位空位），
松手后停在整理态、并选中这张卡。整理态里**拖右下角弧线**调大小：卡片本体跟着手指连续缩放，
虚线框标出松手后会落到的那一档——尺寸名按**行×列**读：**1×1**（只显示图标的小方格）、
**1×3**（半屏宽横条）、**2×2**（2 行 2 列，1/3 屏宽竖卡）、**2×3**（2 行 3 列，原来的默认大小）。
缩小时邻居按最近的较小档位靠过来、放大时按最近的大档位提前让开；
缩放期间图标与文字贴左上角不动，内容随大小自动换排版（过长文字省略）。
页面下方（导航栏上方）的尺寸条也能直接切四档。尺寸与顺序分开存（`plugin.ext.order` / `plugin.ext.sizes`），
重启后都还在；排序页右上角的「重置大小」把所有卡片恢复成 2×3。整理态点空白处或标题栏「完成」退出。

### 扫码添加

从「拓展」页右上角进入的扫一扫会把结果带回来，按码型给**不同颜色 / 文字**的按钮：

* **普通 http(s) 网址** → 绿色「**添加链接**」：把网址作为 web 拓展加进来，
  名称默认用域名，确认弹窗里仍可改；
* **拓展安装码** → 主题强调色「**下载拓展**」：二维码内容必须是一段 JSON：

```json
{
  "antisit": "ext",
  "url": "https://example.com/sit.my-tool.zip",
  "sha256": "64 位十六进制（小写 / 大写都行）",
  "name": "可选，仅安装前展示",
  "id": "可选；写了就必须与包里的 ext.json 一致"
}
```

安装码只认 **https**，并且必须带 sha256：下载后先核对内容，对不上连解压都不做；
校验通过后把包里的名称 / id / 版本 / 权限列给用户，确认后才解压入列。
已存在同 id / 与内置拓展冲突会拒绝（先卸载或让作者换 id）。
生成二维码时把上面这段 JSON 直接编码即可，不需要 App 专用 scheme。

* **第三方插件源安装码** → 主题强调色「**添加插件源**」：二维码内容是一段 JSON：

```json
{
  "antisit": "source",
  "repo": "所有者/仓库（或完整 https 目录地址）",
  "fingerprint": "XXXX-XXXX-XXXX（可选；写了就必须与源公钥一致）",
  "branch": "可选，仅展示",
  "name": "可选，仅展示"
}
```

扫到后 App 会先拉一次 `market.json`、验签，再核对指纹；一致才弹「添加第三方源」
的确认框。入口有两个：**拓展页右上角扫一扫**，或**市场 → 插件源 → 扫一扫添加源**。
`repo` 支持 `所有者/仓库`（自动走 jsDelivr）和完整 https 目录地址。

### Cordis 压缩包的约定

* 打包方式随意：`zip -r myapp.zip myapp/` 这种「所有文件都在同一个顶层目录里」的，
  解压时会自动去掉那一层；
* **入口**：根目录必须有 `ext.json`，其中 `main` 指向入口 `.js`；
* **安全**：绝对路径、`..`、盘符这类条目整条丢弃，绝不写到解压目录外面（zip-slip）；
  最多 200 个文件 / 解压后 8 MB；
* 解压位置：`<应用文档目录>/ext/<拓展 id>/`；删除这条拓展时会连同目录一起清掉。

`ext.json`：

```json
{
  "id": "sit.my-tool",
  "name": "我的工具",
  "desc": "一句话简介",
  "version": "1.0.0",
  "main": "main.js",
  "style": "style.css",
  "permissions": ["storage"],
  "minAppVersion": "1.25.0"
}
```

* `id`：小写字母 / 数字 / `. _ -`，3–64 位；安装目录与存储隔离都按它；
* `name` ≤ 20 字，`desc` ≤ 60 字；
* `version` 改动内容后必须升，市场靠它判断更新；
* `permissions` 见下文「权限」；
* `minAppVersion` 低于它的 App 会显示「需要升级 App」。

## 写一个 Cordis 拓展

`main.js` 必须 `export default` 一个 Cordis 插件（函数，或带 `apply` 的对象）：

```js
export default {
  name: 'my-tool',
  inject: ['ui', 'storage'],
  async apply(ctx) {
    const count = (await ctx.storage.get('count')) ?? 0;

    ctx.ui.root.innerHTML = `
      <main style="padding:20px;font-family:system-ui">
        <h1>记一笔</h1>
        <p>已经记了 <b id="n">${count}</b> 次</p>
        <button id="add">记一笔</button>
      </main>`;

    const button = ctx.ui.root.querySelector('#add');
    const onClick = async () => {
      const next = ((await ctx.storage.get('count')) ?? 0) + 1;
      await ctx.storage.set('count', next);
      ctx.ui.root.querySelector('#n').textContent = String(next);
      ctx.ui.toast('已记 ' + next);
    };
    button.addEventListener('click', onClick);

    // 可逆副作用：页面关闭 / 插件 reload 时自动执行
    ctx.effect(() => () => button.removeEventListener('click', onClick));
  },
};
```

* `inject` 里的服务没就绪时，插件会等待；服务被卸载时插件也会跟着停；
* 所有注册（事件、DOM、定时器）都应放进 `ctx.effect(() => disposer)`，
  这样页面关闭时不会留下泄漏；
* 插件是单文件 `main.js`，不支持 `import` 其他本地文件；需要多文件时在打包前自己合并；
* 页面根节点是 `ctx.ui.root`，直接往里画；`style.css` 会被自动加载。

### 宿主服务

| 服务 | 方法 / 字段 | 说明 |
|---|---|---|
| `ctx.ui` | `root` | 页面根元素（一个 `div`） |
| | `toast(text)` | 弹一条 App 风格提示 |
| | `close()` | 关闭当前拓展页 |
| | `push({onPop})` | 叠一层子页面，返回 `{root, close}`；往 `root` 里画这层的内容，`close()` = 退回上一层 |
| | `pop()` / `depth` / `canGoBack` | 退回上一层 / 当前栈深 / 栈里有没有页面 |
| | `kit` / `confirm(opts)` / `sheet(opts)` | 统一组件（同全局 `AntiUI`）/ 确认框 / 底部弹层 |
| | `theme` | 当前配色的完整令牌：`isDark` / `themeId` / `bg` / `card` / `menuBg` / `inputFill` / `overlay` / `gold` / `radiusCard` / `wells` …（见「主题与夜间模式」） |
| | `onThemeChange(fn)` | 订阅主题 / 夜间模式切换（返回取消订阅函数）；AntiUI 自己会跟 CSS 变量走，不用手动重画 |
| `ctx.storage` | `get(key)` / `set(key, value)` / `remove(key)` | 按拓展 id 隔离的本地存储，返回 Promise |
| `ctx.secrets` | `get(key)` / `set(key, value)` / `remove(key)` | 加密凭据（Keystore / Keychain），按拓展隔离；需 `secrets` 权限 |
| `ctx.net` | `request({method?, url, headers?, body?, bodyBase64?})` | 原生 HTTPS 代理，不受 CORS 限制、可带 Cookie；需 `network` 权限 |
| `ctx.clipboard` | `read()` / `write(text)` | 读写剪贴板；`read` 需 `clipboard` 权限并会弹窗确认 |
| `ctx.files` | `pick({accept?, multiple?, encoding?})` / `save({name, text?, base64?, mime?})` | 读写用户通过系统文件选择器明确选中的文件；需 `files` 权限，单文件 ≤ 8 MB |
| `ctx.login` | `open({url, cookieUrls, title?, successUrlPrefix?, successCookie?, userAgent?})` | 打开可见登录页；返回 `{cookies, cookieHeader}`；需 `login` 权限并会弹窗确认 |
| | `clear({cookieUrls})` | 退出登录：删掉这些域在系统 CookieStore 里的 Cookie（只删自己的凭据的话，下次登录页仍是已登录状态）；需 `login` 权限 |
| `ctx.background` | `keepAlive({enabled, title?, text?})` | 开启 / 关闭后台保活（前台服务 + 常驻通知）；需 `background` 权限并会弹窗确认 |
| `ctx.card` | `setName(text)` / `setDesc(text)` / `setIcon(text)` | 改拓展列表卡片上的显示值 |
| `ctx.ai` | `chat(prompt, {system, maxTokens})` | 走用户在「AI 设置」里配置的模型；Key 不出 App |
| | `chatTools({messages, tools, maxTokens})` | 多轮 + OpenAI 兼容 function calling（拓展工坊用） |
| | `chatToolsStream({streamId, messages, tools, maxTokens})` | 流式版；增量通过 `antiSIT.on('ai.stream')` 推下来，返回值仍是完整回复 |
| `ctx.notify` | `show({title, body?, key?, popup?})` | 立即发一条本地通知；同 `key` 覆盖上一条；首次调用会申请系统通知权限 |
| | `popup({title, body?, key?})` | 高优先级弹窗通知（屏幕横幅）；首次使用会弹一次运行时确认 |
| | `schedule({key, title, body?, at, popup?})` | 定时通知，`at` 是 ISO 8601 时间或毫秒时间戳（必须是未来）；App 没开也能到点弹出；`popup: true` 到点弹横幅 |
| | `cancel(key)` / `cancelAll()` | 撤销一条 / 撤销这条拓展排过的全部通知（不影响上课提醒） |
| `ctx.permissions` | `request({name, host?})` / `status({name, host?})` | 显式申请 / 查询运行时授权（`notification.popup` / `clipboard.read` / `background.keepalive` / `net.host` / `login.open`）；返回 `{name, granted}` |
| `ctx.app` | `id` / `name` / `version` / `permissions` / `close()` | 当前拓展信息 |
| `ctx.workshop` | `list` / `create` / `deleteDraft` / `files` / `read` / `write` / `remove` / `validate` / `install` / `preview` / `publish` | **只给内置「拓展工坊」**，其他拓展调用会被拒。`read` 返回 `{content, version}`；`write` / `remove` 要带 `expectedVersion`（读后写）；`publish` 打开原生发布页 |
| | `listConversations` / `createConversation` / `deleteConversation` / `loadSession` / `saveSession` | 一个草稿多段对话；`saveSession` 带 `conversationId` |
| | `listSkills` / `readSkill` / `installSkill` / `deleteSkill` | Agent 技能库（可复用指令文档，全局共享） |
| | `setFullAccess(enabled)` | 完全访问：写入 / 删除 / 安装不再逐次弹原生确认 |

底层仍然有 `window.antiSIT.call(method, args)` 原始通道；上面的服务只是它的
Cordis 包装。`theme` / `toast` / `close` / `card` 是基础接口，不声明权限也放行。
流式事件用 `antiSIT.on(事件名, 回调)` 订阅（返回取消订阅函数），例如：

```js
antiSIT.on('ai.stream', (e) => {
  if (e.streamId !== myStreamId) return;
  if (e.kind === 'reasoning') showThinking(e.delta);
  else showText(e.delta);
});
```

**页面栈**：`ctx.ui.push()` 叠上去的子页面会全屏盖住当前页；系统返回键 / 左上角返回箭头
先退一层，栈空了才关闭整个拓展。`onPop` 在那层页面退出后回调，适合收尾定时器或写回数据。
根页面先画好再 push；push 之后不要再整块改 `ctx.ui.root.innerHTML`，否则会把栈容器一起冲掉。

### 界面组件（AntiUI）

每个拓展页都会自动注入一套 **AntiUI** 组件（CSS + 全局 `AntiUI` 对象），颜色、圆角、
按压和弹层动效都跟 App 一致，不用自己写一套样式。`ctx.ui.kit` 也指向它。

```js
export default {
  name: 'my-tool',
  inject: ['ui', 'files'],
  apply(ctx) {
    const list = AntiUI.el('div', { class: 'au-stack' });
    const page = AntiUI.page({
      title: '我的文件',
      subtitle: '只读取你在系统选择器里选中的文件',
      children: [
        AntiUI.button('选择文件', { variant: 'primary', block: true, onClick: pick }),
        list,
      ],
    });
    ctx.ui.root.appendChild(page);

    async function pick() {
      const { files } = await ctx.files.pick({ accept: ['text/plain', '.md'], multiple: true });
      if (!files.length) return;
      list.replaceChildren(AntiUI.list(files.map((f) => ({
        title: f.name,
        desc: `${AntiUI.formatBytes(f.size)} · ${f.text.length} 字`,
        icon: 'file',
        chevron: true,
        onClick: () => ctx.ui.toast(f.name),
      }))));
      page.querySelector('.au-subtitle').textContent = `共 ${files.length} 个文件`;
    }
  },
};
```

常用构造器：

| 构造器 | 说明 |
|---|---|
| `AntiUI.page({title, subtitle, topbar?, children})` | 整页容器：安全区内边距 + 纵向间距 |
| `AntiUI.topbar({title, subtitle, onBack, actions})` | 吸顶栏：返回键 + 标题 + 右侧动作 |
| `AntiUI.card({title, desc, children, actions, onClick})` | 卡片（和 App 的 `AppCard` 同款高光 / 描边 / 阴影） |
| `AntiUI.button(label, {variant, icon, block, onClick})` | `variant`：`primary` / `soft` / `danger` / `ghost`；`icon` 见下表 |
| `AntiUI.iconButton(name, {label, onClick})` | 圆形图标按钮 |
| `AntiUI.list([row...])` / `AntiUI.row({title, desc, icon, side, chevron, onClick})` | 列表 / 行 |
| `AntiUI.switchRow({title, desc, checked, onChange})` | 带开关的行 |
| `AntiUI.field({label, hint, control})` / `input(...)` / `textarea(...)` | 表单 |
| `AntiUI.segmented({items, index, onChange})` | 分段选择（滑块跟手动画） |
| `AntiUI.chips(items, {value, onChange})` | 胶囊筛选 |
| `AntiUI.empty({icon, title, desc, action})` | 空态 |
| `AntiUI.spinner()` / `loading(text)` / `progress(value)` | 加载与进度 |
| `AntiUI.sheet({title, desc, content, actions})` | 底部弹层，返回 `{root, close}` |
| `AntiUI.confirm({title, text, confirmText, danger})` | 确认框，返回 `Promise<boolean>` |
| `AntiUI.actions({title, items})` | 动作面板，返回 `Promise<value|null>` |
| `AntiUI.toast(text)` / `copy(text)` / `formatBytes(n)` | 提示 / 复制 / 体积格式化 |

图标：`back` / `chevron` / `close` / `check` / `plus` / `search` / `file` / `folder` /
`download` / `upload` / `trash` / `info` / `refresh` / `copy` / `send` / `sparkles` /
`link` / `clock` / `more`。底层是 `AntiUI.icon(name, size)`，返回一个内联 SVG。

也可以只用 class 写 HTML：`.au-page` / `.au-card` / `.au-btn`（配 `.au-btn--primary`）/
`.au-list` / `.au-row` / `.au-field` / `.au-input` / `.au-seg` / `.au-chip` / `.au-empty` / `.au-spinner`。
颜色变量是 `--antisit-accent` / `--antisit-bg` / `--antisit-card` / `--antisit-border` /
`--antisit-text-muted` / `--antisit-danger`，深浅色切换由宿主负责。

### 主题与夜间模式

拓展页和原生界面**共用同一套色板**，不是近似色：宿主色板的每个令牌都会以 `--antisit-*`
注入页面，AntiUI 直接消费它们。夜间模式切换时宿主会同时改 `html.dark`、`color-scheme`
和全部变量，AntiUI 组件即时换色，不需要重画。

常用变量：

| CSS 变量 | 对应原生令牌 | 用途 |
|---|---|---|
| `--antisit-bg` | `SemColors.bg` | 页面底色 |
| `--antisit-card` / `--antisit-card-solid` | `card` / 合成实底 | 玻璃卡面 / 需要实底的卡内控件 |
| `--antisit-card-elevated` | `cardElevated` | 分栏、分段控件轨道 |
| `--antisit-menu-bg` | `menuBg` | 弹窗 / 底栏 / SnackBar 近实底 |
| `--antisit-border` / `--antisit-border-strong` | `border` / `borderStrong` | 描边 |
| `--antisit-input-fill` | `inputFill` | 输入框填充 |
| `--antisit-fg` / `--antisit-text-secondary` / `--antisit-text-muted` | 文字三级 | 文字 |
| `--antisit-accent` / `--antisit-accent-soft` / `--antisit-accent-strong` | 强调色 | 主按钮 / 选中态 |
| `--antisit-gold` / `--antisit-gold-soft` | 香槟金 | 主 CTA、警告、输入聚焦 |
| `--antisit-success` / `--antisit-danger` | 语义色 | 成功 / 危险 |
| `--antisit-on-accent` | `isDark ? bg : white` | 强调色上的文字 / 图标 |
| `--antisit-overlay` | `overlay` | 弹层遮罩 |
| `--antisit-shadow` | `shadow` | 卡片 / 弹层投影色 |
| `--antisit-thumb` | `thumb` | 分段滑块的滑块面 |
| `--antisit-radius-card` / `control` / `button` / `dialog` / `sheet` / `pill` | 16 / 12 / 16 / 24 / 24 / 999 | 圆角 |
| `--antisit-wells` | 主题光斑 | 玻璃主题的场景光斑（CSS 渐变） |
| `--antisit-theme-id` | 主题 id | 需要按主题做特调时用（如 `theme.glass`） |

需要 JS 里读主题（比如画 canvas、生成图表）时用 `ctx.ui.theme` / `ctx.ui.onThemeChange`：

```js
function render(theme) {
  // theme.isDark / theme.bg / theme.card / theme.menuBg / theme.wells …
}
render(ctx.ui.theme);
const off = ctx.ui.onThemeChange(render);
ctx.effect(() => off); // 页面关闭时取消订阅
```

`theme.wells` 是场景光斑数组（`{x, y, radius, color}`，`x/y` 为 -1..1 的对齐坐标）；
非玻璃主题（墨白 / 竹青）返回空数组，页面就是纯色底。宿主已经把光斑画在页面背景上，
只有在 canvas / 全屏图层里自己画背景时才需要用它。

### AI 调用

`ctx.ai` 已经可用，三种写法按需要选：

```js
// 一问一答：最省事，适合总结 / 改写 / 分类
const text = await ctx.ai.chat('把下面这段课表说明压缩成三行：\n' + raw, {
  system: '你是一个简洁的助手',
  maxTokens: 512,
});

// 多轮 + function calling：自己实现 Agent 循环时用
const reply = await ctx.ai.chatTools({
  messages: [{ role: 'user', content: '帮我看下这两门课冲突吗' }],
  tools: [{
    name: 'course_info',
    description: '按课程名查时间地点',
    parameters: { type: 'object', properties: { name: { type: 'string' } } },
  }],
});
// reply = { text, reasoning, toolCalls, usedTools, finishReason }

// 流式：增量从 antiSIT.on('ai.stream') 推下来，返回值仍是完整回复
const streamId = 's' + Date.now();
antiSIT.on('ai.stream', (e) => {
  if (e.streamId !== streamId) return;
  if (e.kind === 'text') appendText(e.delta);
});
const full = await ctx.ai.chatToolsStream({
  streamId,
  messages: [{ role: 'user', content: '写一句校园卡余额提醒' }],
});
```

需要 `ai` 权限（市场拓展），Key / 模型都在 App 侧，网页拿不到；没配好 AI 或没声明权限
会直接 reject，不会静默返回空串。

**通知**：`ctx.notify` 走 App 自己的本地通知渠道（`ext_notify`），不依赖「上课提醒」插件；
`cancelAll()` 只撤当前拓展排过的通知，不会动课表提醒。没授权「精确闹钟」的机型上定时通知
可能晚几分钟，但不会被丢掉。

`ctx.notify.popup(...)` / `ctx.notify.show({popup: true})` / `ctx.notify.schedule({..., popup: true})`
走单独的 `ext_popup` 高优先级渠道，会在屏幕上弹横幅（部分机型还要用户允许「悬浮通知」）。
首次使用会弹一次运行时确认；插件也可以先用 `ctx.permissions.request({name: 'notification.popup'})`
显式申请。需要 `notification` 权限。

### 权限管理

拓展菜单 →「权限」：上半部分是 `ext.json` 里**安装时声明**的权限（只读），
下半部分是**运行时授权**，逐项开关：

* 关闭后，插件下次用到这项能力会重新询问或直接拒绝；
* 弹窗通知关闭后立即不再弹横幅；
* 「全部重置」会清掉记录，下次使用重新询问；
* `notification.popup` / `clipboard.read` / `background.keepalive` 会在插件声明了对应静态权限时预先列出来，即使还没申请过。

`ctx.ui.push` / `ctx.notify` 是 **1.34.0** 起的新接口；`ctx.files` 与 AntiUI 是
**1.40.2** 起的新接口（主题 / 夜间模式实时同步是 **1.40.3** 起）。要发到市场的拓展请把 `ext.json` 的 `minAppVersion` 设为
用到的最高版本，旧版 App 会提示升级而不是运行到一半报「未知接口」。

## 权限

市场装的拓展要在 `ext.json` 里声明敏感接口，安装弹窗会翻成人话列给用户：

| 权限 | 说明 |
|---|---|
| `storage` | 在本机保存数据（记设置、记历史）；不声明就调用 `ctx.storage` → Promise reject |
| `network` | 运行时联网。**市场装的拓展默认禁网**（CSP `connect-src 'none'`），声明后才放开 `https:` |
| `ai` | 调用 AI（`ctx.ai.*`，走用户的模型与 Key，可能产生费用）；不声明就拒 |
| `notification` | 给你发通知（即时 / 定时，App 没开也能收到）；不声明就调用 `ctx.notify.*` → Promise reject |
| `secrets` | 在本机保存 Cookie / Token 这类登录凭据（系统加密存储，按拓展隔离）；不声明就调用 `ctx.secrets.*` → Promise reject |
| `clipboard` | 读写剪贴板；读取时会在首次 / 未记住时再弹一次确认 |
| `files` | 通过系统文件选择器读取 / 保存用户选中的文件；不扫描本机、不拿路径 |
| `login` | 打开可见登录页并读取拓展声明域名的 Cookie；打开前会再弹一次确认 |
| `background` | 在后台保持运行（前台服务 + 常驻通知）；开启前会再弹一次确认 |

用户自己填网址 / 自己导入的压缩包不受这条限制——来源是他自己选的。
权限门是**防误用**，不是沙箱；App 的用户数据（学号、课表、成绩、凭据）不在接口里。

### 凭据与原生 HTTPS 代理

学校系统的接口通常要带登录态，而网页直接 `fetch` 既受 CORS 限制、也不能设置 `Cookie` 头。
所以给拓展两个通用接口，App 本身**不认识任何学校**：

| 方法 | 参数 | 返回 |
|---|---|---|
| `secrets.get` | `{key}` | 本拓展的加密凭据字符串；没有则 null |
| `secrets.set` | `{key, value}` | true；值走 Android Keystore / iOS Keychain |
| `secrets.remove` | `{key}` | true |
| `net.request` | `{method?, url, headers?, body?, bodyBase64?}` | `{status, url, headers, setCookies, text, truncated, bytes}` |

`net.request` 的约束：

* 只允许 **https**，拒绝 `localhost` / `内网 / 链路本地 / 保留地址`（每次重定向都会重新校验）；
* `Host` / `Content-Length` / `Connection` 这类头由底层接管，传了会被忽略；
* 响应最多 2 MB、超时 30 秒；
* `setCookies` 是这一路重定向里所有 `Set-Cookie` 原文的数组，方便拓展自己维护 Cookie 罐子；
* **逐域授权**：每个新域名（含重定向）第一次访问会弹窗，文案由 App 生成；
  允许 / 拒绝会按「拓展 + 域名」记住，可在拓展菜单「运行时授权」里全部撤销；
* 需要 `network` 权限；`secrets.*` 需要 `secrets` 权限；`clipboard.*` 需要 `clipboard` 权限。

### 剪贴板

`ctx.clipboard.read()` 读文本，`ctx.clipboard.write(text)` 写文本。读取属于敏感动作：
第一次（或用户还没记住选择时）会弹「读取剪贴板」确认框，拒绝后本次调用 reject。

### 文件读写

拓展不能按任意路径读写本机文件；要碰文件，只能通过系统选择器让用户明确选：

```js
// 选文件：accept 支持扩展名（'.csv' / 'csv'）和 MIME（'text/csv' / 'image/*'）
const { files } = await ctx.files.pick({
  accept: ['text/csv', '.json'],
  multiple: false,
  encoding: 'text',        // 缺省 text；图片 / 压缩包这类用 'base64'
});
// files = [{ name, size, mime, text }] 或 [{ name, size, mime, base64 }]
// 用户取消时 files 为空数组

// 存文件：系统「保存到」里选位置，取消返回 false
await ctx.files.save({
  name: '成绩导出.csv',
  mime: 'text/csv',
  text: csv,
});

// 二进制
await ctx.files.save({ name: '图表.png', base64: pngBase64, mime: 'image/png' });
```

约束：

* 需要 `files` 权限（市场拓展）；用户自己加的拓展不受静态权限门限制；
* 单文件 ≤ 8 MB，一次最多 10 个、合计 ≤ 16 MB，超了直接报错，不截断；
* 只返回文件内容，不返回路径；保存也只能写用户选中的那一个位置；
* Android 走 `ACTION_CREATE_DOCUMENT` / 系统文件选择器，不需要存储权限；
* 拓展页里的 `<a download href="blob:...">` / `data:...` 会自动转成
  `files.save`（需声明 `files` 权限）；http(s) 下载由 App 的 DownloadManager 接管（见下）。

### 网页里的上传与下载

「拓展」里打开的**网址型**页面也会做浏览器该做的事：

* `<input type="file">` 点开时弹出系统文件选择器，选完把文件交给网页（Android）；
* 点击下载链接（`Content-Disposition: attachment`、直链文件等）交给系统
  DownloadManager：通知栏有进度，下载完可以直接点开；会带上 WebView 的 Cookie
  和 User-Agent，登录后才能下载的链接也能用；
* `blob:` / `data:` 生成的下载在网址型页面里暂时不接管，需要这类能力的拓展
  请用 Cordis 形态并调用 `ctx.files.save`。

网页上传 / 下载接管目前只在 **Android** 生效（iOS 的 WebView 没有开放文件选择回调）；
`ctx.files` 这两条接口本身在 Android / iOS 都能用，保存文件在 iOS 上暂不支持。

### 通用登录页

`ctx.login.open({url, cookieUrls})` 打开一个**可见的** WebView 登录页（只允许 https），
完成后返回拓展声明的那些域名的 Cookie：

```js
const { cookieHeader } = await ctx.login.open({
  url: 'https://passport2.example.com/login',
  cookieUrls: [
    'https://example.com',
    'https://passport2.example.com',
    'https://api.example.com',
  ],
  successCookie: '_uid',            // 可选：检测到这个 Cookie 就自动完成
  successUrlPrefix: 'https://example.com/', // 可选：离开登录页后自动完成
});
```

* `cookieUrls` 必须与登录地址**同站**（最后两段域名一致），否则直接拒绝；
* 进入登录页前会弹一次授权框，页面底部始终显示当前域名；
* App 只读用户声明的域名的 Cookie，不保存账号密码；
* 没有命中成功条件时，用户点右上角「完成」手动结束。

### 后台保活

`ctx.background.keepAlive({enabled: true, title, text})` 会启动一个**前台服务**并显示
常驻通知，让插件页在退到后台后继续跑自己的定时器；`enabled: false` 停止。

* 它**不执行隐藏页面**：插件页本身仍在 WebView 里，刷新频率由插件自己的定时器决定；
* 只有用户「退到后台」且没有关掉拓展页时继续；关掉拓展页 / 点通知回 App 后可停止；
* 开启前会弹一次授权框，可在拓展菜单「运行时授权」里撤销；
* 仅 Android。
* 这是**前台**能力：页面打开时才能发请求。App 不提供"插件在后台自己跑"的轮询；
  到点提醒请用 `ctx.notify.schedule`（本地通知，App 没开也能弹）。

## 插件市场

「拓展」页顶部两个标签：**我的** 与 **市场**。市场目录由维护者签名，App 验签通过才显示；
每个 zip 还带 sha256，对不上就不解压。

**本版本起，市场里的 `type: "bundle"` 条目必须带 `"runtime": "cordis"`**，
并且 zip 里必须是 `ext.json` + `main.js`。旧目录（没有 `runtime`）的 bundle 条目
会提示「还是旧版网页格式，请等作者升级后再装」，不会再执行旧 html。
`type: "web"` 的网址型条目不受影响，仍然只是打开一个网址。

投稿流程、目录格式与签名工具在独立仓库 `AntiSIT-market`；打包前用
`dart run tool/market_tool.dart check` 自检（会拦下 `localStorage` / `document.cookie`
与未声明 `network` 却引外链资源这类写法）。

## 拓展工坊（Agent）

「拓展工坊」是 App 内置的 Cordis 拓展（id `builtin.workshop`），内部是一个轻量版的
**DSH Agent 架构**：会话是 append-only 事件日志，模型请求从日志派生，而不是维护一份
随时可能和界面不同步的 `messages` 数组。

### 一次运行

1. `send` 把你说的话放进 inbox；空闲时开一个新 turn，运行中则排到下一步（steering）。
2. 每个 step 先拼 system prompt 和 runtime context（草稿 id / 权限 / 文件树 / 技能清单），
   再按日志派生消息，带工具 schema 请求模型。模型输出走**流式**：正文和推理过程
   边收边显示，思考过程默认折叠，点开可看全文。
3. 模型返回的 assistant message（含 reasoning）和每个 `tool/call` / `tool/result`
   都写进日志；连续的只读工具（`list_files` / `read_file` / `validate_extension`）可以并发，
   写入 / 删除 / 安装 / 预览形成独占屏障。工具卡片运行中自动展开，结束后收起，
   随时可以点开回看参数与结果。
4. 模型不再调工具就结束 turn；期间插的话会在下一步被 claim，不会丢。
5. 对话日志落在 `<草稿>/.workshop/sessions/<对话 id>.json`（旧版 `session.json` 仍可读，
   显示为默认对话）。**一个草稿可以有多段对话**，用切换面板切换、「⋯」里新建 / 删除；
   重新打开会恢复上次那段。上次崩溃留下的未闭合 turn、没有结果的 tool call 会自动补一条
   错误结果，保持请求历史合法。

### 模式

* **计划模式**：只读分析，不写文件、不安装。Agent 只拿到只读工具，最后给出一份
  可执行计划；关掉后可以直接让它按计划执行。
* **完全访问**：写入 / 删除 / 安装 / 安装技能不再逐次弹原生确认（开启时仍会确认一次）。
* 两者**互不冲突**：可以同时开启。计划模式下仍然没有写操作；完全访问只影响确认框，
  不影响计划模式的只读工具集。

### 界面

按 DSH Go 那套移动端 Agent 的排版：顶栏是「返回 / 标题（对话名 + 拓展）/ 发布 / 更多」，
下面两个下划线页签 **对话 / 文件**；消息区是扁平的 markdown 流（标题 / 列表 / 行内代码，
围栏代码块带语言标签与「复制」）；连续的几次工具调用收成一行「已执行 N 个操作」，
点开逐条看参数与结果；思考过程折叠成一行「深度思考」。底部是卡片式输入框，
里面放「计划 / 完全访问」开关与发送键，下面一行小字显示对话数、文件数或运行状态。

* 点左上角返回或标题：打开**切换面板**，上面是拓展、下面是当前拓展的对话，点一下切过去。
* 顶栏「发布」：连接 GitHub / Gitee 发布当前草稿。
* 右上角「⋯」：技能 / 预览拓展 / 安装拓展 / **连接 GitHub / Gitee 发布** / 新建对话 / 新建拓展 /
  重命名当前对话 / 重命名当前拓展 / 删除当前对话 / 删除当前拓展。
* 「文件」页签列出拓展里的文件，点开预览全文。

### 拓展与技能

* 「⋯」→「重命名当前拓展」只改 `ext.json` 的 name（已安装的卡片一起改名）；
  「重命名当前对话」只改会话文件里的标题，不影响聊天记录。
* 「⋯」→「删除当前拓展」可以删除**未安装**的拓展（已安装的会提示先去「拓展」页卸载）；
  删除会连同该拓展的全部对话记录一起清掉，删前弹原生确认。
* **技能**（skill）是可复用的指令文档，不是可执行代码：Agent 用 `install_skill` 把
  一段方法论存进全局技能库，之后用 `list_skills` / `read_skill` 按需读取；「⋯」→
  「技能」抽屉可以查看和删除已安装技能。

### 工具

| 工具 | 说明 |
|---|---|
| `list_files` | 看草稿文件树 |
| `read_file` | 读文本文件，支持 `offset` / `limit`；返回内容和版本号 |
| `write_file` | 创建或整文件覆盖；已有文件必须先读过，写入带版本校验 |
| `edit_file` | 按字面量替换（默认要求唯一匹配），比整文件覆盖更安全 |
| `delete_file` | 删除文件；必须先读过 |
| `validate_extension` | 自检清单、入口、`localStorage`、未声明 `network` 却 `fetch` 等 |
| `preview_extension` | 用当前草稿打开 App 内预览 |
| `install_extension` | 复制到正式拓展目录；只有你明确要求时才调用 |
| `list_skills` / `read_skill` | 列出 / 读取技能库；read 支持按 id 或名称 |
| `install_skill` | 安装或更新一条技能（同名覆盖）；弹原生确认，完全访问时跳过 |
| `delete_skill` | 删除一条技能 |

写入、删除、安装都会弹**原生确认**。读后写由 Dart 层按内容 sha256 校验：没读过、
或读完之后文件被别处改过，都会拒绝写入，Agent 必须重新读。草稿位置与文件限制不变：
`<应用文档目录>/ext-workshop/<id>/`，只能读写 `js/json/css/html/md/txt`，单文件 ≤ 256 KB。
`.workshop/` 是隐藏目录，不会出现在文件树、也不会被安装。

工坊自己也是一个 Cordis 拓展：它的 `workshop.*` 接口只对 `builtin.workshop` 开放，
别的拓展即使知道方法名也会被拒。

模型调用走用户在「AI 设置」里的提供商，优先用原生 function calling；提供商不支持 tools 时
自动退回「每次输出一个 JSON 工具调用」的文本协议，不需要用户改配置。

### 发布到 GitHub / Gitee

工坊顶栏「发布」或「⋯」→「连接 GitHub / Gitee 发布…」把当前草稿发成别人能装的拓展。

* 平台：GitHub / Gitee，填 Personal Access Token（只存系统加密存储）。
  GitHub 需要 `public_repo`（私有 / 更新用 `repo`）权限；Gitee 需要仓库 / projects 权限。
* 仓库：填 `所有者/仓库`，也可以粘贴仓库网址。仓库必须**公开**；不存在时 App
  会问你是否新建（GitHub 支持个人 / 组织，Gitee 只支持当前账号）。
* 分支可空（默认分支）。发布物：`ext/<id>/`（源码，方便别人查看或继续用 CLI）、
  `dist/<id>/<版本>.zip`、`market.json` 与 `market.json.sig`。
* 签名：App 首次发布时在本机生成 Ed25519 密钥，私钥只进 Keystore；目录里内嵌公钥，
  别人添加源时核对指纹。**清除 App 数据 / 换机会换密钥**，别人需要重新添加源。
* 同一仓库可以放多条拓展：发布时读取已有目录（先验签）并合并，不会覆盖别的条目。
* 结果页显示：
  * **直装二维码**：别人用「拓展 → 扫一扫」扫一下，点「下载拓展」即可安装；
  * **源二维码**：别人在「市场 → 插件源 → 扫一扫添加源」扫一下，App 拉目录、
    核对公钥指纹后添加源，可接收后续更新；
  * **源地址 + 公钥指纹**：也可以手动在「市场 → 添加第三方源」里填。

### 与 DSH 的差异

这套实现借用了 DSH 的 session / turn / step / inbox / tool registry / runtime context
结构，并补上了流式输出、思考折叠、多对话、技能库与计划 / 完全访问模式；仍然没有搬
subagent、compaction 和 provider 中间件。单轮最多 40 step，日志超过约 400 条事件会按
完整 turn 丢弃最旧的一段。「停止」会在当前模型请求返回后生效（WebView ↔ App 的 AI
通道没有取消令牌），不是 DSH 那种立刻 abort 网络请求。移动端 WebView 里这些取舍是为了
可控的包体和可解释的行为。

## 旧拓展迁移

* 旧 html 压缩包（`index.html` 三件套）不再执行，列表里标「旧版网页拓展（需迁移）」；
* 迁移方式：把页面逻辑改成 `main.js` 里的 Cordis 插件，`ext.json` 填好 id / 权限，
  重新打成 zip 导入；或者直接在拓展工坊里让 Agent 重写；
* 旧拓展的键值数据（`plugin.ext.data.<id>.*`）仍按 id 保留；迁移后 id 不变就能接着读。

## 安全边界

* 内联页是 opaque origin：`localStorage` / `sessionStorage` / `document.cookie` 会抛错，
  请用 `ctx.storage`；
* 市场包默认禁网；声明 `network` 才允许 `https:` 的 fetch / 图片 / 字体；
* 文件访问只经过系统选择器：拓展拿不到路径、不能扫描目录，也拿不到用户没选的文件；
* 不引外部脚本：审核过的代码就是手机上跑的那份；
* 拓展工坊的写文件 / 删除 / 安装全部经过 App 原生确认，模型不能静默改你的拓展；
  写已有文件必须先读，Dart 层再用 sha256 版本校验拦截「拿旧内容覆盖」；
* 工坊会话日志在草稿的隐藏目录 `.workshop/`，模型不能访问，也不会被安装进正式拓展；
* 网页本身仍跑在 WebView 里，权限门防的是误用，不是完整沙箱。
