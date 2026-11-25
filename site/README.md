# antiSIT 官网前端

AntiSIT（应小站）官方网站前端 —— 纯静态 React + Vite，四个页面：

| 页面 | 路由 | 内容 |
|---|---|---|
| 主页 | `#/` | 首屏展示、真实截图轮播、十个功能、两种接入方式 |
| 介绍 | `#/about` | 是什么 / 不是什么、四条设计原则、包结构、演进脉络、技术栈 |
| 开发文档 | `#/docs` | 总览、本地运行、仓库结构、插件、清单、Cordis 拓展、市场、接口规约、自建服务器、发版、隐私 |
| 开源协议 | `#/license` | GitHub / Gitee 双仓链接、GPL-3.0 英文原文与中文译本、权利与义务摘要 |

## 目录结构（按职责分层，页面之间互不引用）

```
src/
  lib/site.js         站点常量（外链、版本、许可信息）+ hash 路由解析
  lib/data.js         内容数据（功能、插件分组、截图、文档目录）
  lib/useReveal.js    入场动画 IntersectionObserver + 主题读写
  styles/tokens.css   设计令牌（配色、模糊、阴影、缓动）—— 换肤只改这里
  styles/base.css     基础层（reset、夜航场景、动效）
  styles/components.css 组件层（面板、按钮、选项卡、徽章、代码块、卡片）
  styles/pages.css    页面层（外壳、Hero、文档双栏、协议阅读器）
  components/         无业务状态的通用件（Icon / GlassTabs / Code / Reveal / TopBar / Footer）
  pages/              四个页面，只组合 components + lib/data
  sections/DocContent.jsx 文档各章节（纯函数组件，一个章节一个组件）
  content/            GPL-3.0 英文原文与中文译本（以 ?raw 方式导入）
public/img/           图标与截图
```

新增内容：改 `lib/data.js`；新增页：`pages/` 加文件 + `App.jsx` 注册 + `lib/site.js` 的 NAV。
调整视觉：只动 `styles/tokens.css`（深色 = 夜航玻璃、浅色 = 晨光玻璃两套令牌）。

## 开发与构建

```bash
npm install
npm run dev        # http://localhost:5173
npm run build      # 产物在 dist/，用相对 base，可整目录搬迁
npm run preview
```

调试参数（不改用户偏好）：

- `?theme=light` / `?theme=dark` 强制主题
- `#/license?lang=en` 直接打开英文原文

## 部署

站点挂在 `https://anticraft.top/antiSIT/`（服务器 `/var/www/anticraft/dist/antiSIT/`）。
因为 base 是相对的、路由都在 hash 里，**整目录 rsync 上去即可**，不需要额外的 nginx 改写：

```bash
npm run build
scp -r dist/* root@47.100.125.150:/var/www/anticraft/dist/antiSIT/
```

## 许可

本站源码随 AntiSIT 项目以 GPL-3.0 发布。
