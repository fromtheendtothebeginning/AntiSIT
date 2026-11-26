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
          {SITE.name} 用的是 GPL-3.0，也就是 GNU 通用公共许可协议第三版。
          简单说：你可以免费用、随便改、拿去卖也行，但改完的版本也要同样开源。
        </p>
        <p className="lead" style={{ marginTop: 10 }}>
          下面是两个代码仓库的地址，以及协议的中文译本和英文原文。
          中文只是帮你理解，<strong style={{ color: "var(--text-primary)" }}>真要较真，以英文原文为准</strong>。
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
              { id: "en", label: "英文原文" }
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
                <span className="repo-go">去看看 <Icon name="external" size={12} /></span>
              </a>
            ))}
          </div>
        </Reveal>

        <Reveal delay={2}>
          <div className={"license-paper" + (lang === "en" ? " is-mono" : "")}>
            {lang === "zh" && (
              <div className="lp-sub">
                译者：阮坤良 &lt;peterrk@pku.edu.cn&gt;。这是非官方译本，只用来帮你理解，
                法律效力以英文原文为准。来源 <a href={SITE.license.translations} target="_blank" rel="noreferrer" style={{ color: "var(--accent-1)" }}>gnu.org/licenses/translations</a>。
              </div>
            )}
            {lang === "en" && (
              <div className="lp-sub">
                这份就是仓库 LICENSE 文件的原文，也是唯一有法律效力的版本 ·
                出处 <a href={SITE.license.url} target="_blank" rel="noreferrer" style={{ color: "var(--accent-1)" }}>www.gnu.org/licenses/gpl-3.0</a>。
              </div>
            )}
            {rendered}
          </div>
        </Reveal>

        <Reveal className="grid cols-2" delay={3}>
          <div className="panel">
            <h3>你可以</h3>
            <ul className="shot-bullets" style={{ marginTop: 8 }}>
              <li>拿去商用 —— 在公司里用、做成收费服务，都不用另外申请</li>
              <li>随便改 —— 想改哪改哪，不用跟作者打招呼</li>
              <li>发给别人 —— 原件或你改过的版本都能发，可以收钱，但拿到的人也要有同样的自由</li>
              <li>自己用 —— 在自己设备上跑、私下改，不受这些条款限制</li>
            </ul>
          </div>
          <div className="panel">
            <h3>但要注意</h3>
            <ul className="shot-bullets" style={{ marginTop: 8 }}>
              <li>你发出去的修改版，也得用 GPL-3.0 开源，并把源码一起给出</li>
              <li>不能加额外限制 —— 不能把这份自由再收窄一层</li>
              <li>要保留原作者的版权声明和「没有担保」这句话</li>
              <li>专利：贡献者把专利许可给了你，你也不能拿专利反过来卡别人</li>
            </ul>
          </div>
        </Reveal>

        <Reveal className="cta-band" delay={4}>
          <div>
            <h3>下载 / 参与</h3>
            <p>Release 页有签好名的安装包。想改代码就提 PR，只动自己那个包最省事。</p>
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