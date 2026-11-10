"use client";

import { useMemo, useState } from "react";
import {
  categories,
  categoryMeta,
  counts,
  readyNotch,
  tools,
  type CategoryId,
} from "@/lib/catalog";
import { Icon, iconForSymbol, Logo } from "./icons";

type Filter = "all" | CategoryId;

export function AppMockup({ compact = false }: { compact?: boolean }) {
  const [filter, setFilter] = useState<Filter>("all");
  const [hover, setHover] = useState<string | null>(null);

  const visible = useMemo(() => {
    const base =
      filter === "all" ? tools.filter((t) => t.implemented) : tools.filter((t) => t.category === filter);
    return base.slice(0, compact ? 8 : 12);
  }, [filter, compact]);

  return (
    <div className="relative">
      {/* notch overlay */}
      <div className="pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2">
        <div className="notch-shape flex h-[30px] w-[228px] items-center justify-center gap-2 px-3 text-[9px] text-white/80">
          <span className="h-1.5 w-1.5 rounded-full bg-ember" />
          <span className="font-medium">Design review</span>
          <span className="text-white/40">in</span>
          <span className="tabular font-mono text-white/90">12:30</span>
        </div>
      </div>

      <div className="window-shell pt-[30px]">
        <div className="window-bar">
          <span className="traffic bg-[#ff5f57]" />
          <span className="traffic bg-[#febc2e]" />
          <span className="traffic bg-[#28c840]" />
          <div className="mx-auto flex h-6 w-[42%] min-w-[150px] items-center gap-1.5 rounded-md bg-white/[0.06] px-2 text-[9px] text-white/35">
            <Icon name="search" className="h-2.5 w-2.5" />
            Search tools
            <span className="ml-auto rounded border border-white/10 px-1 font-mono text-[8px]">
              ⌘K
            </span>
          </div>
          <div className="w-12" />
        </div>

        <div className="flex min-h-[330px] bg-[#0d0f14] text-white sm:min-h-[390px]">
          {/* sidebar */}
          <aside className="hidden w-[168px] shrink-0 flex-col border-r border-white/[0.07] p-2.5 sm:flex">
            <div className="flex items-center gap-2 rounded-md px-1.5 py-1.5">
              <Logo tone="paper" withWordmark={false} className="!gap-0 [&>svg]:h-5 [&>svg]:w-5" />
              <span className="text-[11px] font-semibold tracking-tight">Nookit</span>
              <span className="ml-auto rounded bg-white/10 px-1 py-0.5 font-mono text-[7px] text-white/50">
                v1.0
              </span>
            </div>

            <p className="mt-3 px-1.5 text-[7px] font-semibold uppercase tracking-[0.16em] text-white/30">
              Library
            </p>
            <button
              type="button"
              onClick={() => setFilter("all")}
              className={`mt-1 flex items-center gap-2 rounded-md px-1.5 py-1.5 text-left text-[9.5px] ${
                filter === "all" ? "bg-white/[0.09] text-white" : "text-white/55 hover:bg-white/[0.05]"
              }`}
            >
              <Icon name="grid" className="h-3 w-3" />
              All tools
              <span className="ml-auto font-mono text-[8px] text-white/30">{counts.tools}</span>
            </button>

            <div className="mt-3 flex flex-col gap-0.5">
              {categories.map((cat) => {
                const meta = categoryMeta[cat.id as CategoryId];
                const isActive = filter === cat.id;
                return (
                  <button
                    key={cat.id}
                    type="button"
                    onClick={() => setFilter(cat.id)}
                    className={`flex items-center gap-2 rounded-md px-1.5 py-1.5 text-left text-[9.5px] ${
                      isActive ? "bg-white/[0.09] text-white" : "text-white/55 hover:bg-white/[0.05]"
                    }`}
                  >
                    <span
                      className="inline-flex h-4 w-4 items-center justify-center rounded-[4px]"
                      style={{ backgroundColor: `${meta.tint}26`, color: meta.tint }}
                    >
                      <Icon name={meta.icon as never} className="h-2.5 w-2.5" />
                    </span>
                    {cat.name}
                    <span className="ml-auto font-mono text-[8px] text-white/30">
                      {counts.byCategory[cat.id]}
                    </span>
                  </button>
                );
              })}
            </div>

            <div className="mt-auto rounded-md border border-white/[0.08] bg-white/[0.03] p-2">
              <p className="flex items-center gap-1.5 text-[8.5px] font-semibold text-white/80">
                <span className="h-1 w-1 rounded-full bg-mint" />
                Notch is on
              </p>
              <p className="mt-1 text-[7.5px] leading-relaxed text-white/35">
                {counts.notch} modules · {readyNotch.length} ready
              </p>
            </div>
          </aside>

          {/* main */}
          <div className="min-w-0 flex-1 p-3 sm:p-4">
            <div className="flex items-end justify-between gap-4">
              <div>
                <p className="text-[7px] font-semibold uppercase tracking-[0.16em] text-white/30">
                  {filter === "all" ? "Library" : categories.find((c) => c.id === filter)?.name}
                </p>
                <h3 className="mt-0.5 text-[15px] font-semibold tracking-[-0.02em] text-white">
                  {filter === "all" ? `All ${counts.tools} tools` : `${visible.length} tools`}
                </h3>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="rounded-full bg-mint/10 px-2 py-0.5 text-[7.5px] font-semibold text-mint">
                  {counts.implementedTools} ready
                </span>
                <span className="rounded-full border border-white/10 px-2 py-0.5 text-[7.5px] text-white/40">
                  {counts.tools - counts.implementedTools} in progress
                </span>
              </div>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-1.5 sm:grid-cols-3">
              {visible.map((tool) => {
                const meta = categoryMeta[tool.category];
                return (
                  <div
                    key={tool.slug}
                    onMouseEnter={() => setHover(tool.slug)}
                    onMouseLeave={() => setHover(null)}
                    className={`group relative cursor-default rounded-lg border p-2 transition-all duration-150 ${
                      hover === tool.slug
                        ? "border-white/20 bg-white/[0.07]"
                        : "border-white/[0.07] bg-white/[0.025]"
                    }`}
                  >
                    <div className="flex items-start justify-between">
                      <span
                        className="inline-flex h-6 w-6 items-center justify-center rounded-[6px]"
                        style={{ backgroundColor: `${meta.tint}22`, color: meta.tint }}
                      >
                        <Icon name={iconForSymbol(tool.symbol)} className="h-3.5 w-3.5" />
                      </span>
                      {tool.implemented ? (
                        <span className="mt-0.5 h-1 w-1 rounded-full bg-mint" />
                      ) : (
                        <span className="rounded-sm bg-white/[0.06] px-1 text-[6px] uppercase tracking-wide text-white/30">
                          soon
                        </span>
                      )}
                    </div>
                    <p className="mt-1.5 truncate text-[8.5px] font-semibold text-white/90">
                      {tool.name}
                    </p>
                    <p className="mt-0.5 line-clamp-2 text-[7px] leading-[1.35] text-white/35">
                      {tool.tagline}
                    </p>
                  </div>
                );
              })}
            </div>

            <div className="mt-3 flex items-center justify-between border-t border-white/[0.06] pt-2 text-[7px] text-white/25">
              <span className="flex items-center gap-1">
                <Icon name="shield" className="h-2.5 w-2.5 text-mint/70" />
                On-device · no account
              </span>
              <span className="hidden items-center gap-2 sm:flex">
                <span>Results → Downloads/Nookit</span>
                <span className="font-mono">⌘K</span>
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* floating result toast */}
      <div className="absolute -bottom-4 left-3 z-20 hidden items-center gap-2 rounded-xl border border-white/10 bg-[#1a1e26] px-3 py-2 shadow-xl sm:flex">
        <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-mint/15 text-mint">
          <Icon name="check" className="h-3 w-3" />
        </span>
        <div>
          <p className="text-[8.5px] font-semibold text-white/90">Converted to MP4 · 186 MB</p>
          <p className="text-[7px] text-white/35">Saved to Nookit/2026-11-02 Convert Video</p>
        </div>
        <span className="ml-2 rounded-md bg-white/[0.06] px-1.5 py-1 text-[7px] text-white/60">
          Reveal
        </span>
      </div>
    </div>
  );
}
