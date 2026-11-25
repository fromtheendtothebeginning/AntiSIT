import { useState } from "react";
import Icon from "./Icon.jsx";

// 代码块：标题栏 + 拷贝。内容只做纯文本，不做语法高亮（保证可整段复制）。
export default function Code({ title, badge, children, text }) {
  const [copied, setCopied] = useState(false);
  const raw = text != null ? text : String(children ?? "");

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(raw);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch (e) {
      // 剪贴板被拒（非 https / 无权限）时退化为选中文本
      const sel = window.getSelection();
      if (sel) {
        const range = document.createRange();
        range.selectNodeContents(document.getElementById("clip-" + (title || "x")) || document.body);
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }
  };

  return (
    <div className="code">
      <div className="code-head">
        <span className="code-title">{title || "shell"}</span>
        <span style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {badge && <span className="code-badge">{badge}</span>}
          <button
            type="button"
            className="icon-btn"
            style={{ width: 26, height: 26, borderRadius: 9 }}
            onClick={copy}
            aria-label="复制代码"
            title={copied ? "已复制" : "复制"}
          >
            <Icon name={copied ? "check" : "copy"} size={14} />
          </button>
        </span>
      </div>
      <pre>{children}</pre>
    </div>
  );
}
