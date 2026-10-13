# 拓展（网页形态的小功能）

「拓展」是底栏的一个页面（插件 id `ext`）：**默认关闭**、**硬依赖 WebView 内核**
（`webview`），所以在「插件管理」里打开「拓展」时内核会被一起打开，关掉内核会把
「拓展」一起关掉（关系图上是那条实线）。

App 端默认**没有内置拓展**——清单从空开始。加法有四种，见下。

## 四种加法

| 方式 | 说明 |
|---|---|
| 填写网址 | 名称 + `http(s)` 网址（没写协议按 `https` 补全，`tools.example.com` → `https://tools.example.com`） |
| 导入压缩包 | 选一个 zip（html / js / css 三件套），**导入后自动解压**并内联成一份自包含页面 |
| 导入 JSON | 粘贴单条或数组，字段见下 |
| 编译前固定 | 发行方在 `packages/plugin_ext/lib/builtin_extensions.dart` 的 `kBuiltinExtensions` 里加，随包发布 |

导入 JSON 的字段：

```json
[
  {
    "name": "我的工具",                     // 可省，缺省用域名
    "url": "https://example.com/tool",
    "desc": "一句话简介，显示在卡片名称下方",   // 可省
    "icon": "https://example.com/icon.png",  // 可省：图片网址或 emoji；空 = 用网站 favicon
  },
  {"url": "tools.example.com/another"}
]
```

### 压缩包的约定

* 打包方式随意：`zip -r myapp.zip myapp/` 这种「所有文件都在同一个顶层目录里」的，
  解压时会自动去掉那一层；
* **入口**：根目录的 `index.html`；没有就取根目录排序后第一个 `*.html`；
  一个 html 都没有 → 报错（消息会说明）；
* **打开方式**：入口页里同目录的 `<link href="x.css">` 与 `<script src="x.js"></script>`
  会被**内联**进 html，再当自包含页面交给内核打开——这样不依赖 WebView 的 `file://`
  权限，也不会撞上新版 Android 的文件访问限制；
  代价是**图片 / 字体这类相对路径资源不会被内联**（部分平台可能加载不出来），
  所以三件套请写自包含；外链（`http(s)` / `//`）原样保留；
* **安全**：绝对路径、`..`、盘符这类条目整条丢弃，绝不写到解压目录外面（zip-slip）；
* 解压位置：`<应用文档目录>/ext/<拓展 id>/`；在列表里删除这条拓展时会连同目录一起清掉。

### 内置（编译前固定）的拓展

在 `packages/plugin_ext/lib/builtin_extensions.dart` 里加一行就多一条，随包发布：

```dart
const List<ExtensionItem> kBuiltinExtensions = [
  ExtensionItem(
    id: 'builtin.demo',                 // 全局唯一，别改（改了等于换了一条）
    name: '示例拓展',
    url: 'https://example.com/app',
    desc: '一句话简介',
  ),
];
```

内置项不落盘（用户清单里没有它们），所以改完清单升级 App 就生效；用户端它们带
「内置」标记、**不能删也不能改**（只能看详情）——但它们的网页仍可用 `card.*` 接口
改自己卡片上的显示值（那层覆盖值另存，源码清单里的定义不动）。

## 卡片长什么样

* **图标**：默认取**网站图标**——先抓一次页面，按 `apple-touch-icon`（PNG，通常
  180×180，最清楚）→ `rel="icon"` 里的位图 → 显式声明的 `.ico` 的顺序找，都没有就退到
  站点根 `/favicon.ico`；`.ico` 里嵌的 PNG 帧会被抠出来用（**Flutter 的图片解码器不认
  `.ico`**，直接 `Image.network('.../favicon.ico')` 在多数站点上必然失败）；
  可以在编辑里换成图片网址或 emoji；拿不到（或本地压缩包）就用名称首字——尺寸与
  「工具」宫格一致（8 内边距的圆角色块 + 24 的图标）；
* 名称下面一行是**简介**（可空）——用户在编辑里填，**拓展网页也能用
  `antiSIT.call('card.setName' / 'card.setDesc' / 'card.setIcon', {text})` 自己改**
  （见下表），再下面是**网址**；
  标题栏右边那个**总开关**（睁眼 / 闭眼图标）管的是**全部**拓展：关掉后所有卡片上的
  网址那一行都直接不显示，编辑 / 详情里始终看得到。开关状态记在本地
  （`plugin.ext.hide_urls`），下次进来还是它；
* 点卡片：打开对应网页（应用内浏览器：标题 + 加载进度 + 出错提示）；
* 卡片角落「⋮」：详情 / 编辑 / 删除（内置的只有详情）。

## 网页里能用的接口（`antiSIT`）

打开拓展时内核会注入一段垫片，网页里就有 `window.antiSIT`：

```js
// 需要返回值：call 返回 Promise
const theme = await antiSIT.call('theme');
document.body.style.background = theme.bg;

// 不需要返回值：post（内部吞掉错误，别拿它做需要确认的事）
antiSIT.post('toast', { text: '已保存' });
```

| 方法 | 参数 | 返回 |
|---|---|---|
| `theme` | — | 当前配色：`isDark` / `accent` / `accentSoft` / `bg` / `card` / `border` / `textPrimary` / `textSecondary` / `textMuted` / `danger` / `success`，颜色是 `#RRGGBB` |
| `toast` | `{text}` | `true`（弹一条 App 风格的提示） |
| `close` | — | `true`（关掉当前网页，回到拓展列表） |
| `card.setName` | `{text}` | `true`（换卡片上的名称，≤ 20 字；**id 不变**，存储与隔离仍按 id） |
| `card.setDesc` | `{text}` | `true`（换卡片上的**简介**；空串 = 卡片上不显示简介） |
| `card.setIcon` | `{text}` | `true`（换卡片上的图标：`http(s)` 图片网址，或 ≤ 4 字的文字 / emoji；空串 = 回到网站 favicon / 首字） |
| `storage.get` | `{key}` | 该拓展自己存的值（任意 JSON），没有则 `null` |
| `storage.set` | `{key, value}` | `true` |
| `storage.remove` | `{key}` | `true` |

约定：

* 未知方法 / 参数不对会以 **Promise reject** 回给网页（不静默失败），消息里带原因，
  方便拓展作者调试；
* `card.setName` / `setDesc` / `setIcon` 改的是拓展列表里那张卡片**显示出来的字段**，
  改完落盘，回到列表即可见；长度上限为 20 / 60 / 4（简介、图标都可空 = 不显示那一项），
  超出直接 reject（**不截断**）。用户自己加的拓展与内置拓展都能改：前者直接改清单条目
  （和用户在 App 里编辑的是同一条数据，**后写的生效**），内置项的改动记在一层覆盖值里
  （它在源码清单里仍是原样，用户端本来就看不到编辑入口）；
* `storage` 按拓展 id 隔离：读不到别的拓展的数据；
* **App 里的用户数据（学号、课表、成绩、凭据）不在接口里**，也不会被注入到网页 ——
  拓展是用户自己填的网址，不该默认可信；以后真要放开某类数据，也应走「拓展声明权限 +
  用户同意」那套，而不是直接塞进网页。

## 一个最小可用的拓展

```html
<!doctype html>
<meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font-family:system-ui;padding:16px">
  <h3 id="t">你好</h3>
  <button onclick="save()">记一笔</button>
  <script>
    async function read() {
      return (await antiSIT.call('storage.get', {key: 'count'})) ?? 0;
    }
    (async () => {
      const theme = await antiSIT.call('theme');   // 跟着 App 配色走
      document.body.style.background = theme.bg;
      document.body.style.color = theme.textPrimary;
      document.getElementById('t').textContent = '记了 ' + (await read()) + ' 次';
    })();
    async function save() {
      const n = (await read()) + 1;
      await antiSIT.call('storage.set', {key: 'count', value: n});
      await antiSIT.call('card.setDesc', {text: '已记 ' + n + ' 次'});  // 卡片简介跟着数据走
      document.getElementById('t').textContent = '记了 ' + n + ' 次';
      antiSIT.post('toast', {text: '已记 ' + n});
    }
  </script>
</body>
```

三件套版：把 html / js / css 放进一个 zip（根目录放 `index.html`），在「拓展」页
「导入压缩包」即可——改网页内容不用重发 App。

## 实现位置与扩展点

* **前端**（底栏页、清单、导入、接口实现）：`packages/plugin_ext`；
  清单落在 `plugin.ext.items`，每个拓展的数据落在 `plugin.ext.data.<id>.*`，
  压缩包解压在 `<文档目录>/ext/<id>/`。
* **内核**（网页视图、垫片注入、Promise 回填）：`packages/plugin_webview`；
  通道契约 `WebBridge`（`call(method, args)`）定义在 `campus_core`，所以别的插件
  也能直接复用这套网页通道。
* **加新接口**：在 `packages/plugin_ext/lib/ext_bridge.dart` 的 `call` 里加一个
  `case`，更新上面的表即可——内核不用动。
* **平台**：内核只覆盖 Android / iOS；桌面端打开拓展会提示「当前平台不支持」。
