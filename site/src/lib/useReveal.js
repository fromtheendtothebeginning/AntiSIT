import { useEffect } from "react";

// 入场动画：给 .reveal 元素挂 IntersectionObserver，进入视口后打 .revealed。
//
// 两个必须处理的边界（都踩过）：
// 1) 页面用 history.replaceState 换内容时不会触发 hashchange，effect 不会重跑 —— 新出现的
//    .reveal 节点会永远停在 opacity:0（表现就是「点了一章，内容一片空白」）。所以这里挂
//    MutationObserver：任何新插入的 .reveal 节点都会立刻被观察，不依赖父级重挂。
// 2) 观察器在极端情况（元素比视口高、观察器被节流）下可能迟迟不回调，因此再加一道定时兜底。
const REVEALED = "revealed";

function markRevealed(node) {
  node.classList.add(REVEALED);
}

export function useReveal() {
  useEffect(() => {
    const observed = new WeakSet();

    const io =
      "IntersectionObserver" in window
        ? new IntersectionObserver(
            (entries) => {
              entries.forEach((e) => {
                if (!e.isIntersecting) return;
                markRevealed(e.target);
                io.unobserve(e.target);
              });
            },
            { rootMargin: "0px 0px -2% 0px", threshold: 0.01 }
          )
        : null;

    const pick = (node) => {
      if (node.nodeType !== 1) return;
      const els = [];
      if (node.classList && node.classList.contains("reveal")) els.push(node);
      if (node.querySelectorAll) els.push(...node.querySelectorAll(".reveal"));
      els.forEach((el) => {
        if (observed.has(el) || el.classList.contains(REVEALED)) return;
        observed.add(el);
        if (io) io.observe(el);
        else markRevealed(el);
      });
    };

    pick(document.body);

    // 新插入的节点（切章节、切页、动态加载）立刻开始观察；没有观察器时直接显示。
    let mo = null;
    if (typeof MutationObserver !== "undefined") {
      mo = new MutationObserver((records) => {
        records.forEach((r) => {
          r.addedNodes.forEach(pick);
        });
      });
      mo.observe(document.body, { childList: true, subtree: true });
    }

    // 兜底：2.5 秒后仍未显示的节点直接显示（宁可没有动画，也不能让内容空着）
    const sweep = setTimeout(() => {
      document.querySelectorAll(".reveal:not(.revealed)").forEach(markRevealed);
    }, 2500);

    // 滚动 / 尺寸变化时补扫一次：部分浏览器在页面高度变化后要等下一次滚动才回调
    const onScroll = () => {
      document.querySelectorAll(".reveal:not(.revealed)").forEach((el) => {
        const box = el.getBoundingClientRect();
        if (box.top < window.innerHeight && box.bottom > 0) markRevealed(el);
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);

    return () => {
      clearTimeout(sweep);
      if (mo) mo.disconnect();
      if (io) io.disconnect();
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);
}

// 主题：优先 localStorage，其余默认深色（只有用户手动切过才记忆）
export function readTheme() {
  try {
    const saved = localStorage.getItem("stic-theme");
    if (saved === "light" || saved === "dark") return saved;
  } catch (e) {}
  return "dark";
}

// persist=false 时只改当前渲染（?theme= 调试参数不会写进用户偏好）
export function applyTheme(theme, persist = true) {
  document.documentElement.setAttribute("data-theme", theme);
  if (!persist) return;
  try { localStorage.setItem("stic-theme", theme); } catch (e) {}
}
