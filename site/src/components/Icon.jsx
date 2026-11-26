// 线性镂空图标（stroke 描边，无填充）—— 与 App 内「line:<name>」图标语言一致。
const PATHS = {
  calendar: (
    <>
      <rect x="3" y="5" width="18" height="16" rx="3" />
      <path d="M3 10.5h18M8 3v4M16 3v4" />
      <path d="M7.5 14.5h3v3h-3z" />
    </>
  ),
  qr: (
    <>
      <path d="M4 9V6a2 2 0 0 1 2-2h3M15 4h3a2 2 0 0 1 2 2v3M20 15v3a2 2 0 0 1-2 2h-3M9 20H6a2 2 0 0 1-2-2v-3" />
      <rect x="8.5" y="8.5" width="7" height="7" rx="1.5" />
    </>
  ),
  chart: (
    <>
      <path d="M4 19.5h16" />
      <path d="M7 16V9M12 16v-4.5M17 16V6" />
      <path d="M7 7.5l5-3.5 5 3.5" />
    </>
  ),
  list: (
    <>
      <path d="M9 6h11M9 12h11M9 18h11" />
      <circle cx="4.5" cy="6" r="1.4" />
      <circle cx="4.5" cy="12" r="1.4" />
      <circle cx="4.5" cy="18" r="1.4" />
    </>
  ),
  bolt: (
    <>
      <path d="M13.5 3 6 13.5h5L10.5 21l7.5-10.5h-5z" />
    </>
  ),
  puzzle: (
    <>
      <path d="M9 4.5a2 2 0 1 1 4 0v1h3.5a1.5 1.5 0 0 1 1.5 1.5V10h1a2 2 0 1 1 0 4h-1v3.5a1.5 1.5 0 0 1-1.5 1.5H14" />
      <path d="M12 19.5H6.5A1.5 1.5 0 0 1 5 18v-3.5h-1a2 2 0 1 1 0-4h1V9a1.5 1.5 0 0 1 1.5-1.5H9" />
    </>
  ),
  notifications: (
    <>
      <path d="M18 16.5h-1.5l-1-2V9.5a3.5 3.5 0 0 0-7 0v5l-1 2H6" />
      <path d="M6 16.5h12" />
      <path d="M10 19.5a2 2 0 0 0 4 0" />
      <path d="M12 4V2.5" />
    </>
  ),
  widget: (
    <>
      <rect x="3.5" y="3.5" width="7" height="7" rx="2" />
      <rect x="13.5" y="3.5" width="7" height="7" rx="2" />
      <rect x="3.5" y="13.5" width="7" height="7" rx="2" />
      <rect x="13.5" y="13.5" width="7" height="7" rx="2" />
    </>
  ),
  scan: (
    <>
      <path d="M4 9V6a2 2 0 0 1 2-2h3M15 4h3a2 2 0 0 1 2 2v3M20 15v3a2 2 0 0 1-2 2h-3M9 20H6a2 2 0 0 1-2-2v-3" />
      <path d="M4.5 12h15" />
    </>
  ),
  palette: (
    <>
      <path d="M12 3.5a8.5 8.5 0 1 0 0 17c1.4 0 2-0.9 2-2 0-1.6-1-2-1-3 0-1 .8-1.5 2-1.5h1.5c2 0 3-1.1 3-2.8C20 6.6 16.4 3.5 12 3.5z" />
      <circle cx="8" cy="9" r="1.2" />
      <circle cx="7" cy="14" r="1.2" />
      <circle cx="12" cy="7.5" r="1.2" />
    </>
  ),
  github: (
    <>
      <path d="M9 19.5c-4.5 1.3-4.5-2.2-6-2.6M15 21v-3.2c0-1 .3-1.6.9-2.2 3-.3 5-1.5 5-5.3 0-1.3-.5-2.4-1.3-3.2.2-.6.4-1.9-.2-3.2 0 0-1-.3-3.3 1.2a11 11 0 0 0-5.6 0C7.2 4.6 6.2 4.9 6.2 4.9c-.6 1.3-.4 2.6-.2 3.2A4.6 4.6 0 0 0 4.7 11.3c0 3.7 2 4.9 5 5.3.6.6.9 1.3.9 2.2V21" />
    </>
  ),
  gitee: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M8 12h5.5a2 2 0 0 1 2 2" />
      <path d="M15.5 12a3.5 3.5 0 1 1-3.5 3.5" />
    </>
  ),
  download: (
    <>
      <path d="M12 3.5v11M12 14.5l-4-4M12 14.5l4-4" />
      <path d="M4.5 16.5v2a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-2" />
    </>
  ),
  book: (
    <>
      <path d="M4 5.5A2 2 0 0 1 6 3.5h5v17H6a2 2 0 0 0-2 2z" />
      <path d="M20 5.5A2 2 0 0 0 18 3.5h-5v17h5a2 2 0 0 1 2 2z" />
    </>
  ),
  code: (
    <>
      <path d="M9 7.5 4 12l5 4.5M15 7.5 20 12l-5 4.5" />
      <path d="M13.5 5.5l-3 13" />
    </>
  ),
  shield: (
    <>
      <path d="M12 3.5 19 6v5.5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z" />
      <path d="M9 12l2 2 4-4" />
    </>
  ),
  sun: (
    <>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6 17 7M7 17 5.6 18.4" />
    </>
  ),
  moon: (
    <>
      <path d="M20 14.5A8.5 8.5 0 0 1 9.5 4 8.5 8.5 0 1 0 10.5 20 8.4 8.4 0 0 0 20 14.5z" />
    </>
  ),
  menu: (
    <>
      <path d="M4 7h16M4 12h16M4 17h16" />
    </>
  ),
  close: (
    <>
      <path d="M6 6l12 12M18 6L6 18" />
    </>
  ),
  external: (
    <>
      <path d="M14 4.5h5.5V10" />
      <path d="M19.5 4.5 11 13" />
      <path d="M17 14v5a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5V8.5A1.5 1.5 0 0 1 5 7h5" />
    </>
  ),
  copy: (
    <>
      <rect x="8.5" y="8.5" width="11" height="11" rx="2.5" />
      <path d="M15.5 8.5V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5" />
    </>
  ),
  check: (
    <>
      <path d="M5 12.5l4.5 4.5L19 7" />
    </>
  ),
  arrow: (
    <>
      <path d="M5 12h13M13 6l6 6-6 6" />
    </>
  ),
  chevron: (
    <>
      <path d="M9 5l7 7-7 7" />
    </>
  ),
  spark: (
    <>
      <path d="M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5.1 10.5l5.1-1.9z" />
      <path d="M18.5 16.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z" />
    </>
  )
};

export default function Icon({ name, size = 20, className = "", strokeWidth = 1.6 }) {
  const body = PATHS[name] || PATHS.spark;
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {body}
    </svg>
  );
}