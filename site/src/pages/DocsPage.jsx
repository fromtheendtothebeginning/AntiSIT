import { useEffect, useState } from "react";
import { DOC_GROUPS } from "../lib/data.js";
import { SITE } from "../lib/site.js";
import Icon from "../components/Icon.jsx";
import Reveal from "../components/Reveal.jsx";
import DocContent from "../sections/DocContent.jsx";

const ALL_IDS = DOC_GROUPS.flatMap((g) => g.items.map((i) => i.id));

export default function DocsPage({ sub, onNavigate }) {
  const [active, setActive] = useState(sub && ALL_IDS.includes(sub) ? sub : ALL_IDS[0]);

  useEffect(() => {
    if (sub && ALL_IDS.includes(sub)) setActive(sub);
  }, [sub]);

  const go = (id) => {
    setActive(id);
    // 滚动到文档区顶部（有 sticky 顶栏，用 scroll-margin 兜住）
    const el = document.getElementById("doc-top");
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  return (
    <div className="main">
      <header className="page-hero">
        <div className="hero-tags" style={{ marginBottom: 14 }}>
          <span className="badge"><Icon name="book" size={13} /> Developer Docs</span>
          <span className="badge muted">行为基线 2026-11</span>
        </div>
        <h1>开发文档</h1>
        <p className="lead">
          从「把它跑起来」到「写一个插件」再到「自建后端」。所有接口与目录格式都在仓库里开源，
          这里给的是上手路径与关键约定；细节请以仓库内
          <a className="mono" href={SITE.repos.github.url + "/blob/main/docs"} target="_blank" rel="noreferrer"> docs/ </a>
          为准。
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
                  onClick={(e) => { e.preventDefault(); go(it.id); }}
                >
                  {it.title}
                </a>
              ))}
            </div>
          ))}
        </aside>

        <div className="doc-body">
          <DocContent id={active} onNavigate={onNavigate} />
        </div>
      </div>
    </div>
  );
}

// 供各章节复用的代码块捷径
export function Term({ title, children }) {
  return <Code title={"bash"}>{children}</Code>;
}