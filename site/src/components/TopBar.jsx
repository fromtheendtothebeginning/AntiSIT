import { NAV, SITE } from "../lib/site.js";
import Icon from "./Icon.jsx";

export default function TopBar({ page, theme, onToggleTheme, onNavigate, drawerOpen, setDrawerOpen }) {
  return (
    <>
      <header className="topbar">
        <div className="brand" onClick={() => onNavigate("home")} role="button" tabIndex={0}
             onKeyDown={(e) => { if (e.key === "Enter") onNavigate("home"); }}>
          <img className="brand-logo" src="./img/sit-mark-512.png" alt="AntiSIT 图标" />
          <div className="brand-text">
            <span className="brand-title">{SITE.name}</span>
            <span className="brand-sub">Campus Service · {SITE.tagline}</span>
          </div>
        </div>

        <nav className="nav" aria-label="主导航">
          {NAV.map((n) => (
            <button
              key={n.id}
              type="button"
              className={"nav-link" + (page === n.id ? " active" : "")}
              onClick={() => onNavigate(n.id)}
            >
              {n.label}
            </button>
          ))}
        </nav>

        <div className="topbar-actions">
          <button
            type="button"
            className="icon-btn"
            onClick={onToggleTheme}
            aria-label={theme === "dark" ? "切换到浅色" : "切换到深色"}
            title={theme === "dark" ? "晨光玻璃（浅色）" : "夜航玻璃（深色）"}
          >
            <Icon name={theme === "dark" ? "sun" : "moon"} size={17} />
          </button>
          <a className="icon-btn" href={SITE.repos.github.url} target="_blank" rel="noreferrer"
             aria-label="GitHub 仓库" title="GitHub 仓库">
            <Icon name="github" size={17} />
          </a>
          <button
            type="button"
            className="icon-btn menu-btn"
            onClick={() => setDrawerOpen((v) => !v)}
            aria-label="菜单"
          >
            <Icon name={drawerOpen ? "close" : "menu"} size={18} />
          </button>
        </div>
      </header>

      <div className={"drawer" + (drawerOpen ? " open" : "")}>
        {NAV.map((n) => (
          <button
            key={n.id}
            type="button"
            className={"nav-link" + (page === n.id ? " active" : "")}
            onClick={() => { setDrawerOpen(false); onNavigate(n.id); }}
          >
            {n.label}
          </button>
        ))}
        <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
          <a className="btn ghost small" href={SITE.repos.github.url} target="_blank" rel="noreferrer">
            <Icon name="github" size={14} /> GitHub
          </a>
          <a className="btn ghost small" href={SITE.repos.gitee.url} target="_blank" rel="noreferrer">
            <Icon name="gitee" size={14} /> Gitee
          </a>
        </div>
      </div>
    </>
  );
}