import { useEffect, useRef, useState } from "react";
import TopBar from "./components/TopBar.jsx";
import Footer from "./components/Footer.jsx";
import HomePage from "./pages/HomePage.jsx";
import AboutPage from "./pages/AboutPage.jsx";
import DocsPage from "./pages/DocsPage.jsx";
import LicensePage from "./pages/LicensePage.jsx";
import { NAV, parseRoute } from "./lib/site.js";
import { applyTheme, readTheme, useReveal } from "./lib/useReveal.js";

const PAGE_COMPONENTS = {
  home: HomePage,
  about: AboutPage,
  docs: DocsPage,
  license: LicensePage
};

export default function App() {
  const [route, setRoute] = useState(parseRoute(window.location.hash));
  const forced = /theme=(light|dark)/.test(window.location.search || "");
  const [theme, setTheme] = useState(() => {
    // 允许 ?theme=light / dark 强制某一套（截图与分享链接用，不写进偏好）
    const q = window.location.search || "";
    const m = q.match(/theme=(light|dark)/);
    if (m) return m[1];
    return readTheme();
  });
  const [drawerOpen, setDrawerOpen] = useState(false);
  const firstPaint = useRef(true);

  // 主题初始化 + 跟随系统（用户没手动切换过时）
  useEffect(() => {
    applyTheme(theme, !forced);
    if (!("matchMedia" in window)) return;
    const mq = window.matchMedia("(prefers-color-scheme: light)");
    const onChange = (e) => {
      let saved = null;
      try { saved = localStorage.getItem("stic-theme"); } catch (err) {}
      if (saved) return;
      setTheme(e.matches ? "light" : "dark");
    };
    mq.addEventListener ? mq.addEventListener("change", onChange) : mq.addListener(onChange);
    return () => {
      mq.removeEventListener ? mq.removeEventListener("change", onChange) : mq.removeListener(onChange);
    };
  }, [theme]);

  // hash 路由
  useEffect(() => {
    const onHash = () => {
      const next = parseRoute(window.location.hash);
      setRoute(next);
      setDrawerOpen(false);
      // 切页时滚回顶部；首次进入保留浏览器定位
      if (!firstPaint.current) window.scrollTo({ top: 0, behavior: "instant" in window ? "instant" : "auto" });
      firstPaint.current = false;
    };
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);

  useReveal(route.page + "/" + route.sub);

  const navigate = (page, sub) => {
    const target = "#/" + [page === "home" ? "" : page, sub || ""].filter(Boolean).join("/");
    if (window.location.hash === target) {
      setRoute(parseRoute(target));
    } else {
      window.location.hash = target;
    }
  };

  const Page = PAGE_COMPONENTS[route.page] || HomePage;
  const isKnown = NAV.some((n) => n.id === route.page);

  return (
    <>
      <div className="bg-grid" aria-hidden="true" />
      <div className="shell">
        <TopBar
          page={isKnown ? route.page : "home"}
          theme={theme}
          onToggleTheme={() => setTheme(theme === "dark" ? "light" : "dark")}
          onNavigate={(p) => navigate(p)}
          drawerOpen={drawerOpen}
          setDrawerOpen={setDrawerOpen}
        />

        {route.page === "docs" ? (
          <DocsPage sub={route.sub} onNavigate={navigate} />
        ) : route.page === "about" ? (
          <AboutPage onNavigate={navigate} />
        ) : route.page === "license" ? (
          <LicensePage onNavigate={navigate} />
        ) : (
          <HomePage onNavigate={navigate} />
        )}

        <Footer onNavigate={navigate} />
      </div>
    </>
  );
}