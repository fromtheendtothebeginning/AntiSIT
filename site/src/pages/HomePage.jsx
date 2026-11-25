import { useState } from "react";
import { FEATURES, SHOWCASE, STATS } from "../lib/data.js";
import { SITE } from "../lib/site.js";
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

export default function HomePage({ onNavigate }) {
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
            把校园装进<br />
            <span className="accent">一块玻璃</span>
          </h1>
          <p className="hero-lead">
            {SITE.name}（{SITE.cnName}）是上海应用技术大学的校园服务客户端：课程表、校园码、成绩、
            第二课堂、宿舍电费与拓展市场，一个 App 收齐。界面用 Flutter 手绘玻璃质感，
            数据走开放接口——服务器模式不碰你的校园密码，直连模式则完全不经第三方服务器。
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
          <PhoneFrame src="./img/shots/03_timetable-900.jpg" alt="AntiSIT 课程表界面" />
        </div>
      </section>

      {/* ---------- 展示区 ---------- */}
      <section className="section">
        <Reveal className="section-head">
          <div>
            <span className="eyebrow">Showcase</span>
            <h2>先看看它长什么样</h2>
            <p className="section-sub">
              下面是真实运行截图（不是效果图）：换页时切换标签即可，图取自 App 的课程表、校园码、成绩、
              第二课堂与拓展五个界面。
            </p>
          </div>
          <span className="badge muted">真实截图 · 演示数据</span>
        </Reveal>

        <Reveal className="showcase" delay={1}>
          <div className="showcase-stage">
            <div className="showcase-phone" key={active.id}>
              <div className="phone-screen">
                <img src={"./" + active.file} alt={active.title} />
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
            <h2>十个功能，一个入口</h2>
            <p className="section-sub">
              除了教务、二课这些「必须准」的查询，还有拓展市场、通知、桌面卡片这些日常用得到的小东西。
              每一项都能在「插件管理」里单独启停。
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
            <h2>服务器模式，还是直连模式</h2>
            <p className="section-sub">
              同一套接口形式，两种数据通路。「我的 → 连接设置」里随时切换，任意实现同一套开放接口的
              自建服务器都能用。
            </p>
          </div>
        </Reveal>
        <div className="grid cols-2">
          <Reveal className="card" delay={1}>
            <div className="card-icon"><Icon name="shield" size={19} /></div>
            <h3>服务器模式（推荐）</h3>
            <p>
              填服务器地址 + 该服务器账号密码即可用。校园凭据在服务器网站配置一次，由服务器代连校内网，
              App 全程不接触你的校园密码；401 自动续期，隧道类请求串行排队。
            </p>
            <div className="card-foot">
              <span className="badge green">不接触校园密码</span>
              <span className="badge muted">课表云端同步</span>
            </div>
          </Reveal>
          <Reveal className="card" delay={2}>
            <div className="card-icon"><Icon name="code" size={19} /></div>
            <h3>直连模式</h3>
            <p>
              用本机凭据直接访问学校系统，不走任何服务器，适合校内直连或自建服务器不可用时。
              需要设备在校园网 / 校内 VPN 内，验证码手动输入；凭据明文存本机，手动退出即清除。
            </p>
            <div className="card-foot">
              <span className="badge muted">数据不经第三方</span>
              <span className="badge muted">抢课仅此模式</span>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- CTA ---------- */}
      <Reveal className="cta-band">
        <div>
          <h3>想改点什么？整个仓库都在你手里</h3>
          <p>功能按 Dart 包拆开、清单由脚本生成，GPL-3.0 允许你自由修改与再分发（衍生作品需同样开源）。</p>
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