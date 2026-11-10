"use client";

import { useEffect, useState } from "react";
import { notchModules, type NotchModule } from "@/lib/catalog";
import { Icon, iconForSymbol } from "./icons";
import { Badge } from "./ui";

const ORDER = [
  "calendar",
  "clipboard",
  "timers",
  "notes",
  "tasks",
  "music",
  "hydration",
  "breathe",
  "habits",
  "ai-chat",
];

function ModulePreview({ id }: { id: string }) {
  switch (id) {
    case "calendar":
      return (
        <div className="space-y-2">
          {[
            { time: "12:30", title: "Design review", meta: "in 24 min · Zoom", live: true },
            { time: "14:00", title: "1:1 with Sam", meta: "in 1 hr 54 min · Meet" },
            { time: "16:15", title: "Ship review", meta: "in 4 hr 9 min" },
          ].map((e) => (
            <div
              key={e.time}
              className={`flex items-center gap-3 rounded-xl border p-2.5 ${
                e.live ? "border-ember/30 bg-ember/[0.08]" : "border-white/[0.07] bg-white/[0.03]"
              }`}
            >
              <span className="tabular w-10 shrink-0 font-mono text-[11px] text-white/50">
                {e.time}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[12px] font-semibold text-white/90">
                  {e.title}
                </span>
                <span className="block truncate text-[10px] text-white/35">{e.meta}</span>
              </span>
              {e.live ? (
                <span className="rounded-full bg-ember px-2 py-1 text-[9px] font-semibold text-white">
                  Join
                </span>
              ) : null}
            </div>
          ))}
        </div>
      );
    case "clipboard":
      return (
        <div className="space-y-1.5">
          {[
            { text: "https://nookit.app/tools/json-formatter", meta: "Safari · 2 min ago" },
            { text: "SELECT * FROM orders WHERE status = 'paid';", meta: "Terminal · 8 min ago" },
            { text: "••••••••••••••••••••", meta: "Skipped — password manager", skip: true },
            { text: "Thanks — I'll take a look this afternoon.", meta: "Mail · 21 min ago" },
            { text: "screenshots/notch-expanded@2x.png", meta: "Finder · 34 min ago" },
          ].map((row) => (
            <div
              key={row.text}
              className={`flex items-center gap-3 rounded-lg border px-2.5 py-2 ${
                row.skip
                  ? "border-white/[0.04] bg-white/[0.01] opacity-50"
                  : "border-white/[0.07] bg-white/[0.03]"
              }`}
            >
              <Icon
                name={row.skip ? "lock" : "clipboard"}
                className="h-3 w-3 shrink-0 text-white/30"
              />
              <span className="min-w-0 flex-1 truncate font-mono text-[10px] text-white/70">
                {row.text}
              </span>
              <span className="shrink-0 text-[8.5px] text-white/25">{row.meta}</span>
            </div>
          ))}
        </div>
      );
    case "timers":
      return (
        <div className="flex items-center gap-5 rounded-xl border border-white/[0.07] bg-white/[0.03] p-4">
          <div className="relative grid h-24 w-24 place-items-center">
            <svg viewBox="0 0 100 100" className="absolute inset-0 -rotate-90">
              <circle cx="50" cy="50" r="43" fill="none" stroke="rgba(255,255,255,.08)" strokeWidth="6" />
              <circle
                cx="50"
                cy="50"
                r="43"
                fill="none"
                stroke="#FF5A1F"
                strokeWidth="6"
                strokeLinecap="round"
                strokeDasharray="270"
                strokeDashoffset="92"
              />
            </svg>
            <div className="text-center">
              <p className="tabular font-mono text-[19px] font-semibold text-white">24:12</p>
              <p className="text-[8px] uppercase tracking-wide text-white/35">focus</p>
            </div>
          </div>
          <div className="flex-1">
            <p className="text-[11px] font-semibold text-white/85">Pomodoro · session 2 of 4</p>
            <p className="mt-1 text-[10px] leading-relaxed text-white/35">
              After this: a five minute break. The countdown keeps running in the collapsed notch.
            </p>
            <div className="mt-3 flex gap-1.5">
              {["Pause", "Skip", "Reset"].map((label, i) => (
                <span
                  key={label}
                  className={`rounded-md px-2 py-1 text-[9px] ${
                    i === 0 ? "bg-white text-ink" : "bg-white/[0.07] text-white/60"
                  }`}
                >
                  {label}
                </span>
              ))}
            </div>
          </div>
        </div>
      );
    case "notes":
      return (
        <div className="rounded-xl border border-white/[0.07] bg-white/[0.03] p-3">
          <div className="flex items-center justify-between border-b border-white/[0.06] pb-2">
            <span className="text-[10px] font-semibold text-white/70">Standup — 2 Nov</span>
            <span className="text-[8.5px] text-white/25">saved 4s ago</span>
          </div>
          <p className="mt-2 whitespace-pre-line text-[10.5px] leading-relaxed text-white/60">
            {`Shipped the notch clipboard filter.\nNext: PDF merge progress + cancel.\nBlocker: none.`}
          </p>
        </div>
      );
    case "tasks":
      return (
        <div className="space-y-1.5">
          {[
            { text: "Send the licence email", done: true },
            { text: "Fix result folder naming", done: false },
            { text: "Record the notch demo", done: false },
            { text: "Reply to Sam", done: false },
          ].map((t) => (
            <div
              key={t.text}
              className="flex items-center gap-2.5 rounded-lg border border-white/[0.06] bg-white/[0.025] px-2.5 py-2"
            >
              <span
                className={`grid h-4 w-4 place-items-center rounded-[5px] border ${
                  t.done ? "border-mint bg-mint text-ink" : "border-white/20"
                }`}
              >
                {t.done ? <Icon name="check" className="h-2.5 w-2.5" strokeWidth={3} /> : null}
              </span>
              <span
                className={`text-[11px] ${
                  t.done ? "text-white/30 line-through" : "text-white/75"
                }`}
              >
                {t.text}
              </span>
            </div>
          ))}
          <p className="px-1 pt-1 text-[9px] text-white/25">
            Type a task and press return. Completed items clear at midnight.
          </p>
        </div>
      );
    case "music":
      return (
        <div className="flex items-center gap-4 rounded-xl border border-white/[0.07] bg-white/[0.03] p-3">
          <div className="grid h-20 w-20 shrink-0 place-items-center rounded-lg bg-[radial-gradient(circle_at_30%_25%,#FFB27A,#FF5A1F_45%,#5A1E00)]">
            <Icon name="music" className="h-7 w-7 text-white/80" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-[12px] font-semibold text-white/90">Everything In Its Right Place</p>
            <p className="truncate text-[10px] text-white/35">Radiohead · Kid A</p>
            <div className="mt-2 h-1 overflow-hidden rounded-full bg-white/10">
              <div className="h-full w-[62%] rounded-full bg-white/70" />
            </div>
            <div className="mt-2 flex items-center gap-3 text-white/55">
              <Icon name="wave" className="h-3.5 w-3.5" />
              <Icon name="play" className="h-4 w-4 text-white" />
              <Icon name="arrowRight" className="h-3.5 w-3.5" />
              <span className="ml-auto text-[9px] text-white/25">2:51 / 4:07</span>
            </div>
          </div>
        </div>
      );
    case "hydration":
      return (
        <div className="rounded-xl border border-white/[0.07] bg-white/[0.03] p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-[12px] font-semibold text-white/90">5 of 8 glasses</p>
              <p className="text-[10px] text-white/35">A quiet nudge, not a lecture.</p>
            </div>
            <span className="rounded-lg bg-white px-2.5 py-1.5 text-[10px] font-semibold text-ink">
              + Glass
            </span>
          </div>
          <div className="mt-4 flex gap-1.5">
            {Array.from({ length: 8 }).map((_, i) => (
              <span
                key={i}
                className={`grid h-8 flex-1 place-items-center rounded-md ${
                  i < 5 ? "bg-[#6FB7E3]/25 text-[#9FD8F7]" : "bg-white/[0.04] text-white/15"
                }`}
              >
                <Icon name="drop" className="h-3.5 w-3.5" />
              </span>
            ))}
          </div>
        </div>
      );
    case "breathe":
      return (
        <div className="flex flex-col items-center justify-center rounded-xl border border-white/[0.07] bg-white/[0.03] py-6">
          <div className="relative grid h-24 w-24 place-items-center">
            <span className="absolute inset-0 animate-breathe rounded-full bg-mint/20" />
            <span className="absolute inset-4 rounded-full bg-mint/30" />
            <span className="relative text-[11px] font-semibold text-white">Breathe in</span>
          </div>
          <p className="mt-4 text-[10px] text-white/35">4 in · 7 hold · 8 out — 2 minutes</p>
        </div>
      );
    case "habits":
      return (
        <div className="space-y-2">
          {[
            { name: "Read 20 pages", streak: 12, today: true },
            { name: "Walk outside", streak: 5, today: true },
            { name: "No phone at breakfast", streak: 21, today: false },
          ].map((h) => (
            <div
              key={h.name}
              className="flex items-center gap-3 rounded-lg border border-white/[0.06] bg-white/[0.025] px-3 py-2.5"
            >
              <span
                className={`grid h-7 w-7 place-items-center rounded-full ${
                  h.today ? "bg-ember/15 text-ember" : "bg-white/[0.05] text-white/20"
                }`}
              >
                <Icon name="flame" className="h-3.5 w-3.5" />
              </span>
              <span className="flex-1">
                <span className="block text-[11px] font-medium text-white/80">{h.name}</span>
                <span className="block text-[9px] text-white/30">{h.streak} day streak</span>
              </span>
              <span
                className={`h-5 w-5 rounded-md border ${
                  h.today ? "border-mint bg-mint" : "border-white/15"
                }`}
              />
            </div>
          ))}
        </div>
      );
    case "ai-chat":
      return (
        <div className="space-y-2.5">
          <div className="ml-auto max-w-[80%] rounded-2xl rounded-br-md bg-white/[0.09] px-3 py-2 text-[11px] text-white/80">
            Summarise this paragraph in one sentence.
          </div>
          <div className="max-w-[88%] rounded-2xl rounded-bl-md border border-white/[0.07] bg-white/[0.03] px-3 py-2 text-[11px] leading-relaxed text-white/65">
            The release adds a clipboard filter, a cancellable PDF merge and a faster
            result-folder naming scheme.
            <span className="mt-1 flex items-center gap-1 text-[8.5px] text-mint/80">
              <Icon name="sparkles" className="h-2.5 w-2.5" />
              On-device · nothing sent
            </span>
          </div>
        </div>
      );
    default:
      return null;
  }
}

export function NotchDemo({ auto = true }: { auto?: boolean }) {
  const modules = ORDER.map((id) => notchModules.find((m) => m.id === id)).filter(
    (m): m is NotchModule => Boolean(m),
  );
  const [activeId, setActiveId] = useState(modules[0]?.id ?? "calendar");
  const [touched, setTouched] = useState(false);
  const active = modules.find((m) => m.id === activeId) ?? modules[0];

  useEffect(() => {
    if (!auto || touched) return;
    const id = window.setInterval(() => {
      setActiveId((current) => {
        const index = modules.findIndex((m) => m.id === current);
        return modules[(index + 1) % modules.length]?.id ?? current;
      });
    }, 5200);
    return () => window.clearInterval(id);
  }, [auto, touched, modules]);

  return (
    <div className="mx-auto w-full max-w-[660px]">
      {/* menu bar with the physical notch */}
      <div className="flex h-9 items-center justify-between rounded-t-2xl bg-[#0b0c10] px-4 text-[10px] text-white/55 ring-1 ring-white/[0.07]">
        <div className="flex items-center gap-3">
          <span className="font-semibold text-white/80">Finder</span>
          <span className="hidden sm:inline">File</span>
          <span className="hidden sm:inline">Edit</span>
          <span className="hidden sm:inline">View</span>
        </div>
        <div className="notch-shape absolute left-1/2 h-[26px] w-[150px] -translate-x-1/2" />
        <div className="flex items-center gap-3">
          <Icon name="wifi" className="h-3 w-3" />
          <span className="hidden sm:inline">100%</span>
          <span className="tabular font-mono">14:06</span>
        </div>
      </div>

      {/* expanded notch body */}
      <div
        className="relative overflow-hidden rounded-b-2xl border border-t-0 border-white/[0.07] bg-[#0b0c10]"
        onPointerDown={() => setTouched(true)}
      >
        <div className="pointer-events-none absolute inset-x-0 top-0 h-24 bg-[radial-gradient(ellipse_at_top,rgba(255,90,31,0.10),transparent_70%)]" />
        <div className="relative p-3">
          {/* module tabs */}
          <div className="flex items-center gap-1 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {modules.map((m) => (
              <button
                key={m.id}
                type="button"
                onClick={() => {
                  setActiveId(m.id);
                  setTouched(true);
                }}
                className={`inline-flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-[9.5px] font-medium transition-colors ${
                  m.id === activeId
                    ? "bg-white/[0.11] text-white"
                    : "text-white/40 hover:bg-white/[0.05] hover:text-white/70"
                }`}
                aria-pressed={m.id === activeId}
              >
                <Icon name={iconForSymbol(m.symbol)} className="h-3 w-3" />
                {m.name}
              </button>
            ))}
            <span className="ml-auto hidden shrink-0 items-center gap-1 rounded-md bg-white/[0.04] px-1.5 py-1 font-mono text-[8px] text-white/30 sm:flex">
              hover to open
            </span>
          </div>

          <div className="mt-2 min-h-[212px] rounded-xl bg-white/[0.015] p-3">
            <div className="mb-2.5 flex items-start justify-between gap-3">
              <div>
                <p className="text-[12px] font-semibold text-white/90">{active.name}</p>
                <p className="text-[9.5px] text-white/35">{active.tagline}</p>
              </div>
              {active.implemented ? (
                <span className="inline-flex items-center gap-1 rounded-full bg-mint/10 px-2 py-0.5 text-[8px] font-semibold text-mint">
                  <span className="h-1 w-1 rounded-full bg-mint" />
                  ready
                </span>
              ) : (
                <span className="rounded-full border border-white/10 px-2 py-0.5 text-[8px] text-white/35">
                  roadmap
                </span>
              )}
            </div>
            <ModulePreview id={active.id} />
          </div>
        </div>

        <div className="flex items-center justify-between border-t border-white/[0.06] px-4 py-2 text-[8.5px] text-white/25">
          <span className="flex items-center gap-1.5">
            <Icon name="shield" className="h-2.5 w-2.5 text-mint/60" />
            {active.shortcut ? (
              <>
                Shortcut <span className="font-mono text-white/45">{active.shortcut}</span>
              </>
            ) : (
              "Lives in the notch, not the Dock"
            )}
          </span>
          <span className="hidden sm:inline">Click any module to preview it</span>
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center justify-center gap-2">
        <Badge tone="dark">
          <Icon name="grid" className="h-3 w-3" />
          {notchModules.length} modules
        </Badge>
        <Badge tone="dark">Works without a notch</Badge>
        <Badge tone="dark">Zero CPU when closed</Badge>
      </div>
    </div>
  );
}
