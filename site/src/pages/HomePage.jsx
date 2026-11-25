import { useState } from "react";
import { FEATURES, SHOWCASE, STATS } from "../lib/data.js";
import { SITE } from "../lib/site.js";
import { shotSrc } from "../lib/shots.js";
import Icon from "../components/Icon.jsx";
import Reveal from "../components/Reveal.jsx";

function PhoneFrame({ src, alt, className = "phone" }) {
  return (
    <div className={className}>
      <div className="phone-screen">
        <img src={src} alt={alt} loading="lazy" />
      </div>
    </div>
  );
}

export default function HomePage({ onNavigate, theme }) {
  const [shot, setShot] = useState(SHOWCASE[0].id);
  const active = SHOWCASE.find((s) => s.id === shot) || SHOWCASE[0];

  return (
    <div className="main">
      {/* ---------- Hero ---------- */}
      <section className="hero">
        <div className="hero-copy reveal">
          <div className="hero-tags">
            <span className="badge gold"><Icon name="spark" size={13} /> Campus Service</span>
            <span className="badge">Flutter · Android / Windows</span>
            <span className="badge green">{SITE.license.spdx} 开源</span>
          </div>
          <h1>
            校园里要查的，<br />
            <span className="accent">打开就有</span>
          </h1>
          <p className="hero-lead">
            {SITE.name}（{SITE.cnName}）是给上海应用技术大学同学做的校园助手。
            课表、校园码、成绩、第二课堂、宿舍电费，不用再一个个找入口，打开 App 就在。
            它也不碰你的校园密码——让服务器代连时，密码留在服务器上；直连时，数据只走你自己的手机。
          </p>
          <div className="hero-actions">
            <a className="btn" href={SITE.repos.gitee.releases} target="_blank" rel="noreferrer">
              <Icon name="download" size={16} /> 下载 APK
            </a>
            <button type="button" className="btn ghost" onClick={() => onNavigate("docs")}>
              <Icon name="book" size={16} /> 看开发文档
            </button>
          </div>
          <div className="hero-stats">
            {STATS.map((s) => (
              <div key={s.label}>
                <div className="stat-value">{s.value}</div>
                <div className="stat-label">{s.label}</div>
              </div>
            ))}
          </div>
        </div>

        <div className="hero-visual reveal" data-delay="2">
          <span className="hero-orb a" />
          <span className="hero-orb b" />
          <PhoneFrame src={shotSrc("timetable", theme)} alt="AntiSIT 课程表界面" />
        </div>
      </section>

      {/* ---------- 展示区 ---------- */}
      <section className="section">
        <Reveal className="section-head">
          <div>
            <span className="eyebrow">Showcase</span>
            <h2>先看看它长什么样</h2>
            <p className="section-sub">
              下面是真实运行截图（不是效果图）：配色与当前站点同步（深色 / 浅色各一套），换标签即可切换页面。
            </p>
          </div>
          <span className="badge muted">真实截图 · 示例数据</span>
        </Reveal>

        <Reveal className="showcase" delay={1}>
          <div className="showcase-stage">
            <div className="showcase-phone" key={active.id + theme}>
              <div className="phone-screen">
                <img src={shotSrc(active.id, theme)} alt={active.title} />
              </div>
            </div>
          </div>
          <div className="showcase-info">
            <div className="shot-tabs">
              {SHOWCASE.map((s) => (
                <button
                  key={s.id}
                  type="button"
                  className={"shot-tab" + (s.id === shot ? " active" : "")}
                  onClick={() => setShot(s.id)}
                >
                  {s.label}
                </button>
              ))}
            </div>
            <div className="shot-desc">
              <h3>{active.title}</h3>
              <p>{active.desc}</p>
            </div>
            <ul className="shot-bullets">
              {active.bullets.map((b) => <li key={b}>{b}</li>)}
            </ul>
          </div>
        </Reveal>
      </section>

      {/* ---------- 功能网格 ---------- */}
      <section className="section">
        <Reveal className="section-head">
          <div>
            <span className="eyebrow">Features</span>
            <h2>你要查的，基本都在这儿</h2>
            <p className="section-sub">
              课表、成绩这些每天要看的之外，还有上课提醒、桌面小组件、拓展市场这些顺手的小东西。
              不想要哪个，去「插件管理」关掉就行。
            </p>
          </div>
        </Reveal>
        <div className="grid cols-3">
          {FEATURES.map((f, i) => (
            <Reveal key={f.title} className="card" delay={(i % 3) + 1}>
              <div className="card-icon"><Icon name={f.icon} size={19} /></div>
              <h3>{f.title}</h3>
              <p>{f.desc}</p>
              <div className="card-foot">
                {f.tags.map((t) => <span key={t} className="badge muted">{t}</span>)}
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      {/* ---------- 两种接入方式 ---------- */}
      <section className="section">
        <Reveal className="section-head">
          <div>
            <span className="eyebrow">Connection</span>
            <h2>数据怎么来，你说了算</h2>
            <p className="section-sub">
              两种走法，在「我的 → 连接设置」里随时换。自己搭的服务器也能用，只要接口形式对得上。
            </p>
          </div>
        </Reveal>
        <div className="grid cols-2">
          <Reveal className="card" delay={1}>
            <div className="card-icon"><Icon name="shield" size={19} /></div>
            <h3>服务器模式（推荐）</h3>
            <p>
              填服务器地址和账号就能用。校园密码只填在服务器网站上，由服务器去连校内网，App 从头到尾不碰它。
              课表也能在手机和网站之间同步。
            </p>
            <div className="card-foot">
              <span className="badge green">App 不碰校园密码</span>
              <span className="badge muted">课表云端同步</span>
            </div>
          </Reveal>
          <Reveal className="card" delay={2}>
            <div className="card-icon"><Icon name="code" size={19} /></div>
            <h3>直连模式</h3>
            <p>
              让 App 自己拿着你的凭据去问学校系统，不经任何第三方服务器。适合在校园网里用，
              验证码要自己输一次。退出登录时，保存的密码会一起清掉。
            </p>
            <div className="card-foot">
              <span className="badge muted">数据不经第三方</span>
              <span className="badge muted">抢课要用这个模式</span>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- CTA ---------- */}
      <Reveal className="cta-band">
        <div>
          <h3>想改点什么？代码都在这儿</h3>
          <p>整个项目以 GPL-3.0 开源，你可以随便改、随便发给别人用。改完的版本也要同样开源。</p>
        </div>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          <a className="btn" href={SITE.repos.github.url} target="_blank" rel="noreferrer">
            <Icon name="github" size={16} /> 开源仓库
          </a>
          <button type="button" className="btn ghost" onClick={() => onNavigate("license")}>
            读一读协议 <Icon name="arrow" size={15} />
          </button>
        </div>
      </Reveal>
    </div>
  );
}