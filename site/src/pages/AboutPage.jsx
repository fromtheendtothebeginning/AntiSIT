import { PLUGIN_GROUPS, PRINCIPLES } from "../lib/data.js";
import { SITE } from "../lib/site.js";
import Icon from "../components/Icon.jsx";
import Reveal from "../components/Reveal.jsx";

const MILESTONES = [
  { when: "定位", title: "为什么做这个 App", desc: "教务系统网页版只适配桌面、二课活动要一页页翻、余额和电费散在三个入口。把每天都要用的查询收进一块屏幕，是开发的起点。" },
  { when: "形态", title: "一个插件 = 一个 Dart 包", desc: "宿主只负责壳、设置、插件管理与清单组装；课程表、校园码、成绩……各自独立成包，删掉一个功能只去掉一行依赖。" },
  { when: "边界", title: "凭据只在它该在的地方", desc: "服务器模式不存校园密码；直连模式的凭据明文存本机、不上传，手动退出即清除。目录与拓展包都过签名 / sha256 校验。" },
  { when: "持续", title: "每天在用的东西，得每天能修", desc: "发版走 tag → CI 构建 → GitHub Release → Gitee 镜像 → 自建镜像一条链，普通用户下次检查更新就能拿到。" }
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
          {SITE.name}（中文名 {SITE.cnName}）是面向上海应用技术大学学生的校园服务客户端，
          用 Flutter 写成 Android / Windows 双端。它不替你改成绩，也不替你抢课之外做任何决定——
          它只是把散落在各个系统里的信息，排成一块看得懂的界面。
        </p>
      </header>

      <section className="section" style={{ paddingTop: 28 }}>
        <div className="grid cols-2">
          <Reveal className="panel" delay={1}>
            <h3>它是什么</h3>
            <div className="doc-prose" style={{ marginTop: 8 }}>
              <p>
                一个 Flutter 客户端 + 一套开放接口。客户端把课程表、校园码、成绩、学业情况、第二课堂、
                宿舍电费、考试安排、学生评教、拓展市场这些功能装进底栏的几个页面里；
                接口由任意部署了同一套规约的服务器提供，也可以完全不用服务器。
              </p>
              <p>
                界面语言是「玻璃」：深墨夜景底 + 大半径柔光，面板半透明模糊、边缘一道高光；
                强调色只有两种——月光钢蓝负责信息，香槟金负责「需要你看见」的那一个点。
              </p>
            </div>
          </Reveal>
          <Reveal className="panel" delay={2}>
            <h3>它不是什么</h3>
            <div className="doc-prose" style={{ marginTop: 8 }}>
              <p>
                不是学校官方产品，也不是把网页塞进壳里的套壳 App：每个页面都是原生 Flutter 绘制，
                与学校系统之间只做协议对接。
              </p>
              <p>
                不收集你的信息：页面本身没有任何统计埋点；App 本地只存登录 token、课表、界面设置与
                直连模式 Cookie，可一键清除。
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
            <p className="section-sub">整个仓库的拆法都由这四条决定，写新代码前值得先看一眼。</p>
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
            <h2>一个宿主，三十多个包</h2>
            <p className="section-sub">
              全部包在同一 pub workspace 里，根目录一次 <span className="mono">flutter pub get</span> 解析完。
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
          <p>{SITE.tech.join(" · ")} —— 本地持久化 shared_preferences，网络 http + JWT，</p>
          <p>直连模式把服务端校园对接链路整体搬进 App（pointycastle 提供 AES / RSA，SM4 纯 Dart 实现）。</p>
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
