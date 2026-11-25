import { useEffect, useLayoutEffect, useRef, useState } from "react";

// 液态选项卡：滑块跟随激活项（位置由真实 DOM 计算，字体差异也不会偏）。
export default function GlassTabs({ items, value, onChange, className = "" }) {
  const trackRef = useRef(null);
  const [thumb, setThumb] = useState({ left: 0, width: 0, ready: false });

  const measure = () => {
    const track = trackRef.current;
    if (!track) return;
    const active = track.querySelector('.gtab[data-active="1"]');
    if (!active) return;
    setThumb({
      left: active.offsetLeft,
      width: active.offsetWidth,
      ready: true
    });
  };

  useLayoutEffect(() => {
    measure();
  }, [value, items.length]);

  useEffect(() => {
    const onResize = () => measure();
    window.addEventListener("resize", onResize);
    // 字体加载完宽度会变，再量一次
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(measure).catch(() => {});
    return () => window.removeEventListener("resize", onResize);
  }, []);

  return (
    <div ref={trackRef} className={"glass-tabs " + className} role="tablist">
      {thumb.ready && (
        <span
          className="slide-thumb"
          aria-hidden="true"
          style={{ left: thumb.left, width: thumb.width }}
        />
      )}
      {items.map((it) => (
        <button
          key={it.id}
          type="button"
          role="tab"
          className={"gtab" + (it.id === value ? " active" : "")}
          data-active={it.id === value ? "1" : "0"}
          aria-selected={it.id === value}
          onClick={() => onChange(it.id)}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}
