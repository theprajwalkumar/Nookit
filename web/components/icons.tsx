import type { SVGProps } from "react";

const P = {
  play: <path d="M8 5.5v13l10-6.5-10-6.5Z" />,
  wave: (
    <>
      <path d="M3 12h2l2-6 3 12 3-14 3 16 2-8h3" />
    </>
  ),
  image: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2.5" />
      <circle cx="8.5" cy="9.5" r="1.6" />
      <path d="m4 17 5-5 4 4 3-3 4 4" />
    </>
  ),
  doc: (
    <>
      <path d="M6 3.5h8l4 4V20a1.5 1.5 0 0 1-1.5 1.5h-10A1.5 1.5 0 0 1 5 20V5a1.5 1.5 0 0 1 1-1.5Z" />
      <path d="M14 3.5V8h4M8.5 12h7M8.5 15.5h7M8.5 8.5H11" />
    </>
  ),
  text: (
    <>
      <path d="M4 6V4h16v2M12 4v16M8.5 20h7" />
    </>
  ),
  folder: (
    <>
      <path d="M3 7.5A1.5 1.5 0 0 1 4.5 6h4l2 2.5h9A1.5 1.5 0 0 1 21 10v8.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5v-11Z" />
    </>
  ),
  mac: (
    <>
      <rect x="3" y="4.5" width="18" height="12" rx="2" />
      <path d="M1.5 20h21M9 16.5 8 20M15 16.5 16 20" />
    </>
  ),
  code: (
    <>
      <path d="m8 8-4 4 4 4M16 8l4 4-4 4M13.5 5l-3 14" />
    </>
  ),
  mic: (
    <>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9 21h6" />
    </>
  ),
  calendar: (
    <>
      <rect x="3.5" y="5" width="17" height="16" rx="2.5" />
      <path d="M3.5 10h17M8 3v4M16 3v4" />
      <circle cx="8" cy="14.5" r="1" fill="currentColor" stroke="none" />
      <circle cx="12" cy="14.5" r="1" fill="currentColor" stroke="none" />
      <circle cx="16" cy="14.5" r="1" fill="currentColor" stroke="none" />
    </>
  ),
  display: (
    <>
      <rect x="2.5" y="4" width="19" height="13" rx="2" />
      <path d="M8 21h8M12 17v4" />
    </>
  ),
  wifi: (
    <>
      <path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.7 16a5 5 0 0 1 6.6 0" />
      <circle cx="12" cy="19.5" r="1.2" fill="currentColor" stroke="none" />
    </>
  ),
  sparkles: (
    <>
      <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z" />
      <path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2Z" />
    </>
  ),
  arrowDownCircle: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v10M8 13.5l4 4 4-4" />
    </>
  ),
  arrowRight: <path d="M4 12h15M13 6l6 6-6 6" />,
  arrowUpRight: <path d="M7 17 17 7M8 7h9v9" />,
  check: <path d="m4.5 12.5 5 5 10-11" />,
  plus: <path d="M12 5v14M5 12h14" />,
  minus: <path d="M5 12h14" />,
  close: <path d="m6 6 12 12M18 6 6 18" />,
  search: (
    <>
      <circle cx="11" cy="11" r="6.5" />
      <path d="m16 16 4.5 4.5" />
    </>
  ),
  command: (
    <path d="M9 6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6Z" />
  ),
  lock: (
    <>
      <rect x="5" y="10.5" width="14" height="10" rx="2.5" />
      <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
    </>
  ),
  shield: (
    <>
      <path d="M12 3l7 3v5.5c0 4.6-3 8-7 9.5-4-1.5-7-4.9-7-9.5V6l7-3Z" />
      <path d="m9 12 2 2 4-4" />
    </>
  ),
  bolt: <path d="M13 2 4.5 13.5H11L10 22l8.5-11.5H12L13 2Z" />,
  timer: (
    <>
      <circle cx="12" cy="13.5" r="7.5" />
      <path d="M12 9.5v4l2.5 2.5M9.5 2.5h5M12 2.5V6" />
    </>
  ),
  clipboard: (
    <>
      <rect x="5" y="4.5" width="14" height="17" rx="2.5" />
      <path d="M9 4.5V3h6v1.5M8.5 10h7M8.5 14h7M8.5 18h4" />
    </>
  ),
  note: (
    <>
      <path d="M5 4.5h14v11l-4 4H5v-15Z" />
      <path d="M15 19.5v-4h4M8.5 9h7M8.5 12.5h5" />
    </>
  ),
  music: (
    <>
      <path d="M9 18V6l10-2v12" />
      <circle cx="6.5" cy="18" r="2.5" />
      <circle cx="16.5" cy="16" r="2.5" />
    </>
  ),
  drop: <path d="M12 3s6 6.2 6 10.5A6 6 0 0 1 6 13.5C6 9.2 12 3 12 3Z" />,
  flame: (
    <path d="M12 2.5c.8 4 4.5 5.4 4.5 9.5a4.5 4.5 0 0 1-9 0c0-1.7.8-3.2 2-4.4 0 2 1 3 2 3 0-3.2.3-5.6.5-8.1Z" />
  ),
  lungs: (
    <>
      <path d="M12 3v9M9 8c-2 0-5 2-5 6.5C4 18 5.5 20 8 20s3-2 3-4.5V10c0-1.5-1-2-2-2ZM15 8c2 0 5 2 5 6.5 0 3.5-1.5 5.5-4 5.5s-3-2-3-4.5V10c0-1.5 1-2 2-2Z" />
    </>
  ),
  layers: <path d="m12 3 9 5-9 5-9-5 9-5Zm-9 9 9 5 9-5M3 16.5l9 5 9-5" />,
  qr: (
    <>
      <rect x="4" y="4" width="6" height="6" rx="1" />
      <rect x="14" y="4" width="6" height="6" rx="1" />
      <rect x="4" y="14" width="6" height="6" rx="1" />
      <path d="M14 14h2v2h-2zM18 14h2v2h-2zM14 18h2v2h-2zM18 18h2v2h-2z" />
    </>
  ),
  key: (
    <>
      <circle cx="8" cy="12" r="4.5" />
      <path d="M12.5 12H21M18 12v3M15 12v2" />
    </>
  ),
  clock: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3.5 2" />
    </>
  ),
  chart: <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />,
  menu: <path d="M4 7h16M4 12h16M4 17h16" />,
  chevronDown: <path d="m6 9 6 6 6-6" />,
  trash: (
    <>
      <path d="M4 7h16M9 7V4.5h6V7M6 7l1 13h10l1-13" />
      <path d="M10 11v5M14 11v5" />
    </>
  ),
  external: <path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" />,
  info: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5M12 8h.01" />
    </>
  ),
  star: <path d="m12 3 2.7 5.7 6.3.9-4.5 4.4 1 6.2-5.5-3-5.5 3 1-6.2L3 9.6l6.3-.9L12 3Z" />,
  grid: (
    <>
      <rect x="3" y="3" width="7" height="7" rx="1.5" />
      <rect x="14" y="3" width="7" height="7" rx="1.5" />
      <rect x="3" y="14" width="7" height="7" rx="1.5" />
      <rect x="14" y="14" width="7" height="7" rx="1.5" />
    </>
  ),
  internaldrive: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2.5" />
      <path d="M3 13.5h18M7 16.5h.01M10.5 16.5h.01" />
    </>
  ),
} as const;

export type IconName = keyof typeof P;

export function Icon({
  name,
  className,
  strokeWidth = 1.7,
  ...props
}: { name: IconName; className?: string; strokeWidth?: number } & Omit<
  SVGProps<SVGSVGElement>,
  "name"
>) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
      {...props}
    >
      {P[name]}
    </svg>
  );
}

/** Map an SF Symbol name from the catalog onto the web icon set. */
export function iconForSymbol(symbol: string): IconName {
  const s = symbol.toLowerCase();
  if (s.includes("play") || s.includes("record")) return "play";
  if (s.includes("wave") || s.includes("speaker") || s.includes("music")) return "wave";
  if (s.includes("photo") || s.includes("image") || s.includes("camera")) return "image";
  if (s.includes("pdf") || s.includes("doc") || s.includes("archive")) return "doc";
  if (s.includes("text") || s.includes("character") || s.includes("captions")) return "text";
  if (s.includes("folder") || s.includes("tray") || s.includes("externaldrive")) return "folder";
  if (s.includes("display") || s.includes("sun") || s.includes("mac")) return "display";
  if (s.includes("chevron") || s.includes("curlybraces") || s.includes("asterisk")) return "code";
  if (s.includes("mic")) return "mic";
  if (s.includes("calendar")) return "calendar";
  if (s.includes("wifi") || s.includes("network")) return "wifi";
  if (s.includes("sparkle") || s.includes("wand")) return "sparkles";
  if (s.includes("clipboard")) return "clipboard";
  if (s.includes("note")) return "note";
  if (s.includes("timer") || s.includes("clock") || s.includes("hourglass")) return "timer";
  if (s.includes("drop")) return "drop";
  if (s.includes("flame")) return "flame";
  if (s.includes("lungs")) return "lungs";
  if (s.includes("qrcode")) return "qr";
  if (s.includes("key") || s.includes("lock")) return "key";
  if (s.includes("chart") || s.includes("gauge")) return "chart";
  if (s.includes("check")) return "check";
  if (s.includes("trash")) return "trash";
  if (s.includes("shield")) return "shield";
  if (s.includes("scissors")) return "play";
  if (s.includes("arrow")) return "arrowDownCircle";
  return "bolt";
}

export function Logo({
  className = "",
  tone = "ink",
  withWordmark = true,
}: {
  className?: string;
  tone?: "ink" | "paper";
  withWordmark?: boolean;
}) {
  const fg = tone === "ink" ? "#0A0B0E" : "#F7F4ED";
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <svg viewBox="0 0 40 40" className="h-8 w-8" role="img" aria-label="Nookit">
        <rect x="1" y="1" width="38" height="38" rx="10" fill={fg} />
        <rect x="10" y="8" width="20" height="7" rx="3" fill="#FF5A1F" />
        <rect x="15" y="10.5" width="10" height="2" rx="1" fill="#0A0B0E" />
        <path
          d="M10 22h20M10 27h14M10 32h17"
          stroke={tone === "ink" ? "#F7F4ED" : "#0A0B0E"}
          strokeWidth="2.6"
          strokeLinecap="round"
        />
      </svg>
      {withWordmark ? (
        <span
          className="text-[1.05rem] font-semibold tracking-[-0.03em]"
          style={{ color: fg }}
        >
          Nookit
        </span>
      ) : null}
    </span>
  );
}
