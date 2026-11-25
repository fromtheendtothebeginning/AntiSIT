import { SITE } from "../lib/site.js";
import Icon from "./Icon.jsx";

export default function Footer({ onNavigate }) {
  return (
    <footer className="footer">
      <div className="footer-inner">
        <div style={{ display: "grid", gap: 10 }}>
          <div className="footer-brand">
            <img src="./img/sit-mark-512.png" alt="" />
            <span>
              {SITE.name} · {SITE.cnName} — 校园服务客户端，源码以 {SITE.license.spdx} 开源
            </span>
          </div>
          <span style={{ fontSize: 12, color: "var(--text-muted)" }}>
            学生自己做的非官方项目 · 跟学校系统只做数据对接 · 这个页面不收集任何信息
          </span>
        </div>
        <div style={{ display: "grid", gap: 10 }}>
          <div className="footer-links">
            <button type="button" onClick={() => onNavigate("home")} style={{ background: "none", border: 0, color: "inherit", cursor: "pointer", font: "inherit" }}>主页</button>
            <button type="button" onClick={() => onNavigate("about")} style={{ background: "none", border: 0, color: "inherit", cursor: "pointer", font: "inherit" }}>介绍</button>
            <button type="button" onClick={() => onNavigate("docs")} style={{ background: "none", border: 0, color: "inherit", cursor: "pointer", font: "inherit" }}>开发文档</button>
            <button type="button" onClick={() => onNavigate("license")} style={{ background: "none", border: 0, color: "inherit", cursor: "pointer", font: "inherit" }}>开源协议</button>
          </div>
          <div className="footer-links">
            <a href={SITE.repos.github.url} target="_blank" rel="noreferrer">GitHub <Icon name="external" size={12} /></a>
            <a href={SITE.repos.gitee.url} target="_blank" rel="noreferrer">Gitee <Icon name="external" size={12} /></a>
            <a href={SITE.mirror.latest} target="_blank" rel="noreferrer">版本信息</a>
          </div>
        </div>
      </div>
    </footer>
  );
}