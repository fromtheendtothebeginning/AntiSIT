import { useEffect, useState } from "react";
import { DOC_GROUPS } from "../lib/data.js";
import { SITE } from "../lib/site.js";
import Icon from "../components/Icon.jsx";
import DocContent from "../sections/DocContent.jsx";

const ALL_IDS = DOC_GROUPS.flatMap((g) => g.items.map((i) => i.id));

export default function DocsPage({ sub }) {
  const [active, setActive] = useState(sub && ALL_IDS.includes(sub) ? sub : ALL_IDS[0]);

  // 章节以 hash 为准（#/docs/<id>）：地址栏会跟着变，刷新 / 分享 / 前进后退都对得上
  useEffect(() => {
    if (sub && ALL_IDS.includes(sub)) setActive(sub);
  }, [sub]);

  const go = (id) => {
    setActive(id);
    window.history.replaceState(null, "", "#/docs/" + id);
    const el = document.getElementById("doc-top");
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  // 手机端目录是一条可横滑的胶囊条：切换章节后把当前项滑进可视区，否则选中项可能在屏幕外
  useEffect(() => {
    const rail = document.querySelector(".doc-nav");
    const cur = rail && rail.querySelector('a[aria-current="page"]');
    if (!rail || !cur) return;
    if (rail.scrollWidth <= rail.clientWidth + 1) return;
    const left = cur.offsetLeft - rail.clientWidth / 2 + cur.offsetWidth / 2;
    rail.scrollTo({ left: Math.max(0, left), behavior: "smooth" });
  }, [active]);

  const group = DOC_GROUPS.find((g) => g.items.some((i) => i.id === active));
  const current = group?.items.find((i) => i.id === active);

  return (
    <div className="main">
      <header className="page-hero">
        <div className="hero-tags" style={{ marginBottom: 14 }}>
          <span className="badge gold"><Icon name="puzzle" size={13} /> 拓展开发教程</span>
          <span className="badge">Cordis 运行时</span>
          <span className="badge muted">行为基线 2026-11</span>
        </div>
        <h1>开发文档 · 写一个拓展</h1>
        <p className="lead">
          一个拓展就是一段跑在 App 里的 Cordis 插件：一个 <span className="mono">ext.json</span> +
          一个 <span className="mono">main.js</span>，通过 <span className="mono">ctx</span> 拿宿主的存储、网络、
          AI、通知与整套界面组件。下面按「看懂 → 写第一个 → 画界面 → 用能力 → 发布」的顺序讲完。
          仓库里 <a className="mono" href={SITE.repos.github.url + "/blob/main/docs/extensions.md"} target="_blank" rel="noreferrer">docs/extensions.md</a>
          是同一套内容的完整版。
        </p>
      </header>

      <div className="doc-shell" id="doc-top">
        <aside className="doc-nav">
          {DOC_GROUPS.map((g) => (
            <div key={g.group} style={{ display: "contents" }}>
              <div className="doc-nav-group">{g.group}</div>
              {g.items.map((it) => (
                <a
                  key={it.id}
                  href={"#/docs/" + it.id}
                  className={active === it.id ? "active" : ""}
                  aria-current={active === it.id ? "page" : undefined}
                  onClick={(e) => { e.preventDefault(); go(it.id); }}
                >
                  {it.title}
                </a>
              ))}
            </div>
          ))}
        </aside>

        <div className="doc-body">
          {current && (
            <div className="doc-crumb">
              <span>{group?.group}</span>
              <Icon name="chevron" size={13} />
              <strong>{current.title}</strong>
            </div>
          )}
          <DocContent id={active} />
        </div>
      </div>
    </div>
  );
}