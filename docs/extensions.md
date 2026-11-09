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
| 编译前固定 | 在 `packages/plugin_ext/lib/builtin_extensions.dart` 的 `kBuiltinExtensions` 里加 |
| 拓展工坊 | 在「拓展」页打开内置工坊，用自然语言让 Agent 写一个 Cordis 拓展 |

拓展卡片默认按添加先后排列；「我的」标题栏的**排序**入口可以拖动自定义顺序，
「恢复默认」回原始顺序。排序结果存在本机，重启 App 不变；新加的拓展排在最后。

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
| | `theme` | 当前配色：`isDark` / `accent` / `bg` / `card` / `border` / `textPrimary` …（`#RRGGBB`） |
| `ctx.storage` | `get(key)` / `set(key, value)` / `remove(key)` | 按拓展 id 隔离的本地存储，返回 Promise |
| `ctx.card` | `setName(text)` / `setDesc(text)` / `setIcon(text)` | 改拓展列表卡片上的显示值 |
| `ctx.ai` | `chat(prompt, {system, maxTokens})` | 走用户在「AI 设置」里配置的模型；Key 不出 App |
| | `chatTools({messages, tools, maxTokens})` | 多轮 + OpenAI 兼容 function calling（拓展工坊用） |
| | `chatToolsStream({streamId, messages, tools, maxTokens})` | 流式版；增量通过 `antiSIT.on('ai.stream')` 推下来，返回值仍是完整回复 |
| `ctx.app` | `id` / `name` / `version` / `permissions` / `close()` | 当前拓展信息 |
| `ctx.workshop` | `list` / `create` / `deleteDraft` / `files` / `read` / `write` / `remove` / `validate` / `install` / `preview` | **只给内置「拓展工坊」**，其他拓展调用会被拒。`read` 返回 `{content, version}`；`write` / `remove` 要带 `expectedVersion`（读后写） |
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

## 权限

市场装的拓展要在 `ext.json` 里声明敏感接口，安装弹窗会翻成人话列给用户：

| 权限 | 说明 |
|---|---|
| `storage` | 在本机保存数据（记设置、记历史）；不声明就调用 `ctx.storage` → Promise reject |
| `network` | 运行时联网。**市场装的拓展默认禁网**（CSP `connect-src 'none'`），声明后才放开 `https:` |
| `ai` | 调用 AI（`ctx.ai.*`，走用户的模型与 Key，可能产生费用）；不声明就拒 |

用户自己填网址 / 自己导入的压缩包不受这条限制——来源是他自己选的。
权限门是**防误用**，不是沙箱；App 的用户数据（学号、课表、成绩、凭据）不在接口里。

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

按 DSH Go 那套移动端 Agent 的排版：顶栏是「返回 / 标题（对话名 + 草稿）/ 更多」，
下面两个下划线页签 **对话 / 文件**；消息区是扁平的 markdown 流（标题 / 列表 / 行内代码，
围栏代码块带语言标签与「复制」）；连续的几次工具调用收成一行「已执行 N 个操作」，
点开逐条看参数与结果；思考过程折叠成一行「深度思考」。底部是卡片式输入框，
里面放「计划 / 完全访问」开关与发送键，下面一行小字显示对话数、文件数或运行状态。

* 点左上角返回或标题：打开**切换面板**，上面是草稿、下面是当前草稿的对话，点一下切过去。
* 右上角「⋯」：技能 / 预览草稿 / 安装草稿 / 新建对话 / 新建草稿 / 删除当前对话 / 删除当前草稿。
* 「文件」页签列出草稿里的文件，点开预览全文。

### 草稿与技能

* 「⋯」→「删除当前草稿」可以删除**未安装**的草稿（已安装的会提示先去「拓展」页卸载）；
  删除会连同该草稿的全部对话记录一起清掉，删前弹原生确认。
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
* 不引外部脚本：审核过的代码就是手机上跑的那份；
* 拓展工坊的写文件 / 删除 / 安装全部经过 App 原生确认，模型不能静默改你的拓展；
  写已有文件必须先读，Dart 层再用 sha256 版本校验拦截「拿旧内容覆盖」；
* 工坊会话日志在草稿的隐藏目录 `.workshop/`，模型不能访问，也不会被安装进正式拓展；
* 网页本身仍跑在 WebView 里，权限门防的是误用，不是完整沙箱。
