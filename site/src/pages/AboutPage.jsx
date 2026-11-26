import { PLUGIN_GROUPS, PRINCIPLES } from "../lib/data.js";
import { SITE } from "../lib/site.js";
import Icon from "../components/Icon.jsx";
import Reveal from "../components/Reveal.jsx";

const MILESTONES = [
  { when: "起因", title: "为什么做这个 App", desc: "教务系统只有电脑版好用，二课活动要一页页翻，余额和电费又分在三个地方。想查点东西得来回切，于是干脆自己做一个。" },
  { when: "做法", title: "每个功能各自独立", desc: "课表、校园码、成绩……各住各的包，互不牵扯。想删掉某个功能，去掉一行就行，不会带坏别的。" },
  { when: "分寸", title: "密码放在该放的地方", desc: "让服务器代连时，校园密码只填在服务器网站上；直连时，凭据只存在你自己手机里，退出登录就清掉。" },
  { when: "维护", title: "每天在用的东西，得能天天修", desc: "发版走一条自动化流水线，改完推上去，用户下次点「检查更新」就能拿到。" }
];

export default function AboutPage({ onNavigate }) {
  return (
    <div className="main">
      <header className="page-hero">
        <div className="hero-tags" style={{ marginBottom: 14 }}>
          <span className="badge gold"><Icon name="spark" size={13} /> {SITE.tagline}</span>
          <span className="badge">Flutter 3 / Material 3</span>
        </div>
        <h1>介绍 · {SITE.name}</h1>
        <p className="lead">
          {SITE.name}（中文名 {SITE.cnName}）是给上海应用技术大学同学做的校园助手，
          手机上和电脑上都能跑。它不替你做任何决定，只是把散在各个系统里的信息，
          收拢成一块看得懂的屏幕。
        </p>
      </header>

      <section className="section" style={{ paddingTop: 28 }}>
        <div className="grid cols-2">
          <Reveal className="panel" delay={1}>
            <h3>它是什么</h3>
            <div className="doc-prose" style={{ marginTop: 8 }}>
              <p>
                一个手机 App，加上一套公开的取数接口。课表、校园码、成绩、学业情况、第二课堂、
                宿舍电费、考试安排、评教、拓展市场，都收在底栏几个页面里。
              </p>
              <p>
                界面是玻璃质感：深色底子配上柔光，面板半透明、边缘有一道高光。
                颜色只用两种——钢蓝负责信息，香槟金负责「这个要点你」。
              </p>
            </div>
          </Reveal>
          <Reveal className="panel" delay={2}>
            <h3>它不是什么</h3>
            <div className="doc-prose" style={{ marginTop: 8 }}>
              <p>
                不是学校做的官方应用，也不是把网页套个壳：每个页面都是原生画的，
                跟学校系统之间只做数据对接。
              </p>
              <p>
                不收集你的信息：App 里没有埋点，本地只存登录状态、课表和界面设置，
                「我的」页点一下就能清空。
              </p>
            </div>
          </Reveal>
        </div>
      </section>

      <section className="section">
        <div className="section-head">
          <div>
            <span className="eyebrow">Architecture</span>
            <h2>四条设计原则</h2>
            <p className="section-sub">代码怎么拆，都由这四条决定。</p>
          </div>
        </div>
        <div className="grid cols-2">
          {PRINCIPLES.map((p, i) => (
            <Reveal key={p.title} className="card" delay={(i % 2) + 1}>
              <h3>{p.title}</h3>
              <p>{p.desc}</p>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="section">
        <div className="section-head">
          <div>
            <span className="eyebrow">Packages</span>
            <h2>一个主程序，三十多个包</h2>
            <p className="section-sub">
              所有包放在同一套工作区里，一次 <span className="mono">flutter pub get</span> 就全部装好。
            </p>
          </div>
        </div>
        <div className="grid cols-2">
          {PLUGIN_GROUPS.map((g, i) => (
            <Reveal key={g.name} className="card" delay={(i % 2) + 1}>
              <h3>{g.name}</h3>
              <p>{g.note}</p>
              <div className="card-foot">
                {g.items.map((it) => (
                  <span key={it} className="badge muted mono" style={{ fontFamily: "var(--mono)", fontSize: 11 }}>{it}</span>
                ))}
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="section">
        <div className="section-head">
          <div>
            <span className="eyebrow">Timeline</span>
            <h2>它是怎么长成这样的</h2>
            <p className="section-sub">从「想查点东西」到「天天在改」，中间发生了什么。</p>
          </div>
        </div>
        <div className="steps">
          {MILESTONES.map((m, i) => (
            <Reveal key={m.title} className="step" delay={(i % 4) + 1}>
              <div className="step-no">{String(i + 1).padStart(2, "0")}</div>
              <div className="step-body">
                <h4>{m.title} <span className="badge muted" style={{ marginLeft: 6, fontSize: 11 }}>{m.when}</span></h4>
                <p>{m.desc}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      <Reveal className="cta-band">
        <div>
          <h3>技术栈</h3>
          <p>{SITE.tech.join(" · ")}。数据存在本机，联网走 JWT 令牌。</p>
          <p>直连模式把连学校系统的那套流程整个搬进了 App，加解密都在本地做。</p>
        </div>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          <button type="button" className="btn" onClick={() => onNavigate("docs")}>
            开发文档 <Icon name="arrow" size={15} />
          </button>
          <button type="button" className="btn ghost" onClick={() => onNavigate("license")}>
            开源协议
          </button>
        </div>
      </Reveal>
    </div>
  );
}