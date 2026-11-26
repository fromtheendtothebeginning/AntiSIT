// 站点级常量：所有外链 / 版本信息集中在这里，改一处全站生效。
export const SITE = {
  name: "AntiSIT",
  cnName: "应小站",
  fullName: "AntiSIT · 校园服务",
  tagline: "以匠心破常规",
  host: "anticraft.top",
  baseUrl: "https://anticraft.top",
  sitePath: "/antiSIT/",
  // 仓库双源：GitHub 为主开发仓，Gitee 为国内镜像（Release 附件国内直连快）
  repos: {
    github: {
      label: "GitHub",
      url: "https://github.com/fromtheendtothebeginning/AntiSIT",
      releases: "https://github.com/fromtheendtothebeginning/AntiSIT/releases",
      desc: "主仓库 · CI 构建发布 APK"
    },
    gitee: {
      label: "Gitee",
      url: "https://gitee.com/ender123/AntiSIT",
      releases: "https://gitee.com/ender123/AntiSIT/releases",
      desc: "国内镜像 · 下载更快"
    }
  },
  // 更新源：App 内检查更新的兜底镜像（latest.json 由发版脚本同步）
  mirror: {
    latest: "https://anticraft.top/apk/latest.json",
    apkBase: "https://anticraft.top/apk/"
  },
  license: {
    spdx: "GPL-3.0",
    name: "GNU General Public License v3.0",
    cn: "GNU 通用公共许可协议 第三版",
    url: "https://www.gnu.org/licenses/gpl-3.0.html",
    translations: "https://www.gnu.org/licenses/translations.html"
  },
  apkMinAndroid: "Android 7.0 以上",
  // 分类（首页/介绍页共用的功能事实）
  tech: ["Flutter 3 / Dart 3", "Material 3", "pub 工作区", "Cordis 拓展运行时"]
};

export const NAV = [
  { id: "home", label: "主页", path: "" },
  { id: "about", label: "介绍", path: "about" },
  { id: "docs", label: "开发文档", path: "docs" },
  { id: "license", label: "开源协议", path: "license" }
];

// 路由：hash 路由（本站是纯静态目录，nginx 只做 $uri 直出，不能依赖 SPA 回退）。
// path 形如 "/"、"/about"、"/docs/xxx" —— 支持二级锚点型路径但不做深链重写。
export function parseRoute(hash) {
  const raw = (hash || "").replace(/^#/, "").replace(/^\/+/, "");
  const clean = raw.split("?")[0];
  const segs = clean.split("/").filter(Boolean);
  return {
    page: segs[0] || "home",
    sub: segs[1] || "",
    anchor: segs[2] || "",
    query: raw.includes("?") ? raw.slice(raw.indexOf("?") + 1) : ""
  };
}

export function routeHash(page, sub, anchor) {
  const parts = [];
  if (page && page !== "home") parts.push(page);
  if (sub) parts.push(sub);
  if (anchor) parts.push(anchor);
  return "#/" + parts.join("/");
}