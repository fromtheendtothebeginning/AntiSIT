import { useEffect, useMemo, useState } from "react";
import { SITE } from "../lib/site.js";
import Icon from "../components/Icon.jsx";
import GlassTabs from "../components/GlassTabs.jsx";
import Reveal from "../components/Reveal.jsx";
import enText from "../content/license-gpl3-en.txt?raw";
import zhText from "../content/license-gpl3-zh.txt?raw";

// 中文译本的分节标题（原文一、二、……十七、与〇、定义）——高亮成小标题，长文才有结构感
const ZH_SECTION = /^[〇一二三四五六七八九十]+、/;
const ZH_HEADER = /^【.*】$/;

function renderZh(text) {
  let lines = text.split("\n");
  // 源文件开头重复了一次标题（网页 h1 + 正文 h2），这里只留一份
  const titleIdx = lines.findIndex((l) => l.trim() === "GNU通用公共许可协议");
  if (titleIdx >= 0) {
    const second = lines.findIndex((l, i) => i > titleIdx && l.trim() === "GNU通用公共许可协议");
    if (second >= 0) lines = [...lines.slice(0, second), ...lines.slice(second + 1)];
  }
  return lines.map((line, i) => {
    const t = line.trim();
    if (!t) return null;
    if (ZH_HEADER.test(t)) return <div key={i} className="lp-h" style={{ color: "var(--accent-2)" }}>{t}</div>;
    if (ZH_SECTION.test(t) && t.length <= 22) return <div key={i} className="lp-h">{t}</div>;
    return <p key={i} className="lp-para">{t}</p>;
  });
}

function renderEn(text) {
  // 英文原文按 GPLv3 的段落规范排版：保持 \n 换行，仅把全大写小节标题加粗提亮
  const chunks = text.split(/\n{2,}/);
  return chunks.map((chunk, i) => {
    const t = chunk.trim();
    if (!t) return null;
    const isHeader = /^[\d\s]*[A-Z][A-Z \-,.]{4,}$/.test(t.split("\n")[0] || "");
    return <div key={i} className={"lp-para" + (isHeader ? " lp-h" : "")}>{t}</div>;
  });
}

export default function LicensePage() {
  // 允许 ?lang=en 直接打开英文原文（分享链接 / 截图用）
  const initial = () => {
    const src = (window.location.hash || "") + "&" + (window.location.search || "");
    const m = src.match(/lang=(zh|en)/);
    return m ? m[1] : "zh";
  };
  const [lang, setLang] = useState(initial);

  const rendered = useMemo(() => {
    return lang === "zh" ? renderZh(zhText) : renderEn(enText);
  }, [lang]);

  return (
    <div className="main">
      <header className="page-hero">
        <div className="hero-tags" style={{ marginBottom: 14 }}>
          <span className="badge gold"><Icon name="shield" size={13} /> {SITE.license.spdx}</span>
          <span className="badge">可商用 · 可修改 · 可再分发</span>
        </div>
        <h1>开源协议</h1>
        <p className="lead">
          {SITE.name} 以 GNU 通用公共许可协议第三版（GPL-3.0）发布。下面给出两个代码托管地址、
          协议中文译本与英文原文；译文仅供理解参考，
          <strong style={{ color: "var(--text-primary)" }}>以英文原文为准</strong>。
        </p>
      </header>

      <section className="license-layout">
        <Reveal className="license-toolbar">
          <div className="license-meta">
            <span className="badge muted">{SITE.license.cn}</span>
            <span className="badge muted">SPDX: {SITE.license.spdx}</span>
            <a className="badge" href={SITE.license.url} target="_blank" rel="noreferrer">
              官方原文 <Icon name="external" size={12} />
            </a>
          </div>
          <GlassTabs
            items={[
              { id: "zh", label: "中文译本" },
              { id: "en", label: "English (Official)" }
            ]}
            value={lang}
            onChange={setLang}
          />
        </Reveal>

        <Reveal delay={1}>
          <div className="license-side">
            {[
              { key: "github", icon: "github", repo: SITE.repos.github },
              { key: "gitee", icon: "gitee", repo: SITE.repos.gitee }
            ].map(({ key, icon, repo }) => (
              <a key={key} className="repo-card" href={repo.url} target="_blank" rel="noreferrer">
                <div className="repo-card-main">
                  <div className="repo-icon"><Icon name={icon} size={19} /></div>
                  <div style={{ minWidth: 0 }}>
                    <div className="repo-name">AntiSIT on {repo.label}</div>
                    <div className="repo-desc">{repo.desc}</div>
                  </div>
                </div>
                <span className="repo-go">仓库 <Icon name="external" size={12} /></span>
              </a>
            ))}
          </div>
        </Reveal>

        <Reveal delay={2}>
          <div className={"license-paper" + (lang === "en" ? " is-mono" : "")}>
            {lang === "zh" && (
              <div className="lp-sub">
                译者：阮坤良 &lt;peterrk@pku.edu.cn&gt; · 非官方译本，不替代原文的法律效力；
                本译本依 GPL 译文发布条款转载，来源 <a href={SITE.license.translations} target="_blank" rel="noreferrer" style={{ color: "var(--accent-1)" }}>gnu.org/licenses/translations</a>。
              </div>
            )}
            {lang === "en" && (
              <div className="lp-sub">
                Verbatim copy of the license text shipped in the repository LICENSE file ·
                canonical source <a href={SITE.license.url} target="_blank" rel="noreferrer" style={{ color: "var(--accent-1)" }}>www.gnu.org/licenses/gpl-3.0</a>.
              </div>
            )}
            {rendered}
          </div>
        </Reveal>

        <Reveal className="grid cols-2" delay={3}>
          <div className="panel">
            <h3>你能做什么</h3>
            <ul className="shot-bullets" style={{ marginTop: 8 }}>
              <li>商业使用 —— 在公司、收费服务里用都不需要额外授权</li>
              <li>修改源码 —— 想改哪就改哪，不必向作者报备</li>
              <li>再分发 —— 原件或修改版都能发，可以收费，但要给接收者同样自由</li>
              <li>私人使用 —— 在自己设备上跑、私下改，不受分发条款约束</li>
            </ul>
          </div>
          <div className="panel">
            <h3>你需要注意</h3>
            <ul className="shot-bullets" style={{ marginTop: 8 }}>
              <li>分发修改版必须同样以 GPL-3.0 开源，并提供对应源码</li>
              <li>不得附加额外限制：不能把 GPL 授权再收窄一层</li>
              <li>分发须保留版权声明与「无担保」声明</li>
              <li>专利：贡献者授予你专利许可；你不得用专利反过来限制他人</li>
            </ul>
          </div>
        </Reveal>

        <Reveal className="cta-band" delay={4}>
          <div>
            <h3>下载 / 参与</h3>
            <p>Release 页提供签好名的 APK 与 .sha256；想提交代码请走 PR，改动只碰自己的插件包最省事。</p>
          </div>
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <a className="btn" href={SITE.repos.gitee.releases} target="_blank" rel="noreferrer">
              <Icon name="download" size={16} /> 下载 APK
            </a>
            <a className="btn ghost" href={SITE.repos.github.url} target="_blank" rel="noreferrer">
              <Icon name="github" size={16} /> 去 GitHub
            </a>
          </div>
        </Reveal>
      </section>
    </div>
  );
}