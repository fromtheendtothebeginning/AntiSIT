import { useEffect } from "react";

// 入场动画：给 .reveal 的元素挂 IntersectionObserver，进入视口后打 .revealed。
// 页面切换时重新扫描 —— 依赖 data-page 变化触发重挂。
export function useReveal(pageKey) {
  useEffect(() => {
    const nodes = Array.from(document.querySelectorAll(".reveal:not(.revealed)"));
    if (!nodes.length) return;
    if (!("IntersectionObserver" in window)) {
      nodes.forEach((n) => n.classList.add("revealed"));
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add("revealed");
            io.unobserve(e.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.1 }
    );
    nodes.forEach((n) => io.observe(n));
    // 兜底：2.5 秒后仍未进入视口的元素直接显示（避免截图工具/极端滚动下内容一直透明）
    const fallback = setTimeout(() => {
      document.querySelectorAll(".reveal:not(.revealed)").forEach((n) => n.classList.add("revealed"));
    }, 2500);
    return () => {
      clearTimeout(fallback);
      io.disconnect();
    };
  }, [pageKey]);
}

// 主题：优先 localStorage，其次系统偏好；调用时把 data-theme 写到 <html>
export function readTheme() {
  try {
    const saved = localStorage.getItem("stic-theme");
    if (saved === "light" || saved === "dark") return saved;
  } catch (e) {}
  // 站点默认是「夜航玻璃」（深色）；只有用户手动切过才记忆，系统偏好不强制覆盖品牌底色
  return "dark";
}

// persist=false 时只改当前渲染（?theme= 调试参数不会写进用户偏好）
export function applyTheme(theme, persist = true) {
  document.documentElement.setAttribute("data-theme", theme);
  if (!persist) return;
  try { localStorage.setItem("stic-theme", theme); } catch (e) {}
}