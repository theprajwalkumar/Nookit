"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import {
  categories,
  categoryMeta,
  counts,
  getCategory,
  searchTools,
  tools,
  type CategoryId,
  type Tool,
} from "@/lib/catalog";
import { Icon } from "./icons";
import { Badge, ToolGlyph } from "./ui";

export function ToolCard({ tool, dark = false }: { tool: Tool; dark?: boolean }) {
  const cat = getCategory(tool.category);
  return (
    <Link
      href={`/tools/${tool.slug}`}
      className={`group relative flex flex-col rounded-2xl border p-4 transition-all duration-200 ${
        dark
          ? "border-white/[0.08] bg-white/[0.03] hover:border-white/20 hover:bg-white/[0.06]"
          : "border-line bg-white/70 hover:-translate-y-0.5 hover:border-line-strong hover:bg-white hover:shadow-[0_18px_40px_-24px_rgba(10,11,14,0.3)]"
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <ToolGlyph tool={tool} />
        {tool.implemented ? (
          <span
            className={`inline-flex items-center gap-1 text-[0.62rem] font-semibold uppercase tracking-[0.08em] ${
              dark ? "text-mint" : "text-mint-deep"
            }`}
          >
            <span className="h-1.5 w-1.5 rounded-full bg-current" />
            Ready
          </span>
        ) : (
          <span
            className={`text-[0.62rem] font-semibold uppercase tracking-[0.08em] ${
              dark ? "text-paper/30" : "text-slate-2"
            }`}
          >
            Roadmap
          </span>
        )}
      </div>
      <h3
        className={`mt-3 text-[0.95rem] font-semibold tracking-[-0.015em] ${
          dark ? "text-paper" : "text-ink"
        }`}
      >
        {tool.name}
      </h3>
      <p
        className={`mt-1 flex-1 text-[0.78rem] leading-relaxed ${
          dark ? "text-paper/45" : "text-slate"
        }`}
      >
        {tool.tagline}
      </p>
      <div
        className={`mt-3 flex items-center justify-between border-t pt-2.5 text-[0.66rem] ${
          dark ? "border-white/[0.07] text-paper/30" : "border-line text-slate-2"
        }`}
      >
        <span>{cat?.name}</span>
        <Icon
          name="arrowUpRight"
          className="h-3 w-3 transition-transform duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
        />
      </div>
    </Link>
  );
}

export function ToolCatalog({
  showFilters = true,
  defaultCategory = "all",
  limit,
  dark = false,
  initialReadyOnly = false,
}: {
  showFilters?: boolean;
  defaultCategory?: "all" | CategoryId;
  limit?: number;
  dark?: boolean;
  initialReadyOnly?: boolean;
}) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<"all" | CategoryId>(defaultCategory);
  const [readyOnly, setReadyOnly] = useState(initialReadyOnly);

  const filtered = useMemo(() => {
    let list = query.trim() ? searchTools(query) : tools;
    if (category !== "all") list = list.filter((t) => t.category === category);
    if (readyOnly) list = list.filter((t) => t.implemented);
    return limit ? list.slice(0, limit) : list;
  }, [query, category, readyOnly, limit]);

  const grouped = useMemo(() => {
    return categories
      .map((cat) => ({
        cat,
        list: filtered.filter((t) => t.category === cat.id),
      }))
      .filter((group) => group.list.length > 0);
  }, [filtered]);

  const ready = tools.filter((t) => t.implemented).length;

  return (
    <div>
      {showFilters ? (
        <div className="mb-8">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
            <label className="relative flex-1">
              <Icon
                name="search"
                className={`pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 ${
                  dark ? "text-paper/30" : "text-slate-2"
                }`}
              />
              <input
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setCategory("all");
                }}
                placeholder="Search by name or job — “compress”, “pdf”, “uuid”…"
                className={`h-11 w-full rounded-full border pl-10 pr-24 text-[0.86rem] outline-none transition-colors ${
                  dark
                    ? "border-white/10 bg-white/[0.04] text-paper placeholder:text-paper/25 focus:border-white/25"
                    : "border-line-strong bg-white/70 placeholder:text-slate-2 focus:border-ink/40 focus:bg-white"
                }`}
                aria-label="Search tools"
              />
              <span
                className={`absolute right-3 top-1/2 -translate-y-1/2 font-mono text-[0.66rem] ${
                  dark ? "text-paper/25" : "text-slate-2"
                }`}
              >
                {filtered.length} / {tools.length}
              </span>
            </label>

            <button
              type="button"
              onClick={() => setReadyOnly((v) => !v)}
              aria-pressed={readyOnly}
              className={`inline-flex h-11 shrink-0 items-center gap-2 rounded-full border px-4 text-[0.8rem] font-semibold transition-colors ${
                readyOnly
                  ? dark
                    ? "border-mint/30 bg-mint/10 text-mint"
                    : "border-mint-deep/25 bg-mint/15 text-mint-deep"
                  : dark
                    ? "border-white/10 text-paper/50 hover:text-paper"
                    : "border-line-strong text-slate hover:text-ink"
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${
                  readyOnly ? "bg-current" : "bg-current opacity-40"
                }`}
              />
              Ready now
              <span className="opacity-60">{ready}</span>
            </button>
          </div>

          <div className="mt-4 flex flex-wrap gap-1.5">
            <button
              type="button"
              onClick={() => setCategory("all")}
              className={`rounded-full px-3 py-1.5 text-[0.76rem] font-semibold transition-colors ${
                category === "all"
                  ? dark
                    ? "bg-paper text-ink"
                    : "bg-ink text-paper"
                  : dark
                    ? "bg-white/[0.05] text-paper/50 hover:text-paper"
                    : "bg-white/60 text-slate hover:text-ink"
              }`}
            >
              All <span className="opacity-50">{tools.length}</span>
            </button>
            {categories.map((cat) => {
              const active = category === cat.id;
              return (
                <button
                  key={cat.id}
                  type="button"
                  onClick={() => setCategory(cat.id)}
                  className={`rounded-full px-3 py-1.5 text-[0.76rem] font-semibold transition-colors ${
                    active
                      ? dark
                        ? "bg-paper text-ink"
                        : "bg-ink text-paper"
                      : dark
                        ? "bg-white/[0.05] text-paper/50 hover:text-paper"
                        : "bg-white/60 text-slate hover:text-ink"
                  }`}
                >
                  {cat.name} <span className="opacity-50">{counts.byCategory[cat.id]}</span>
                </button>
              );
            })}
          </div>
        </div>
      ) : null}

      {filtered.length === 0 ? (
        <div
          className={`rounded-2xl border border-dashed p-10 text-center ${
            dark ? "border-white/15" : "border-line-strong"
          }`}
        >
          <p className={`text-sm font-semibold ${dark ? "text-paper" : "text-ink"}`}>
            No tool matches that.
          </p>
          <p className={`mt-1 text-[0.82rem] ${dark ? "text-paper/40" : "text-slate"}`}>
            Try a broader word, or{" "}
            <button
              type="button"
              className="underline underline-offset-2"
              onClick={() => {
                setQuery("");
                setCategory("all");
                setReadyOnly(false);
              }}
            >
              clear the filters
            </button>
            .
          </p>
        </div>
      ) : category !== "all" || query.trim() ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {filtered.map((tool) => (
            <ToolCard key={tool.slug} tool={tool} dark={dark} />
          ))}
        </div>
      ) : (
        <div className="space-y-12">
          {grouped.map(({ cat, list }) => (
            <section key={cat.id} id={cat.id} className="scroll-mt-28">
              <div className="mb-4 flex flex-wrap items-end justify-between gap-3 border-b border-line pb-3">
                <div>
                  <div className="flex items-center gap-2">
                    <span
                      className="inline-flex h-6 w-6 items-center justify-center rounded-md"
                      style={{
                        backgroundColor: categoryMeta[cat.id].tintSoft,
                        color: categoryMeta[cat.id].tint,
                      }}
                    >
                      <Icon name={categoryMeta[cat.id].icon as never} className="h-3.5 w-3.5" />
                    </span>
                    <h3 className="text-[1.15rem] font-semibold tracking-[-0.02em]">
                      {cat.name}
                    </h3>
                    <span className="text-[0.7rem] font-semibold text-slate-2">
                      {list.length}
                    </span>
                  </div>
                  <p className="mt-1 max-w-xl text-[0.78rem] text-slate">{cat.blurb}</p>
                </div>
                <span className="text-[0.66rem] font-medium uppercase tracking-[0.08em] text-slate-2">
                  {list.filter((t) => t.implemented).length} ready
                </span>
              </div>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {list.map((tool) => (
                  <ToolCard key={tool.slug} tool={tool} dark={dark} />
                ))}
              </div>
            </section>
          ))}
        </div>
      )}

      {limit && filtered.length >= limit ? (
        <div className="mt-8 flex justify-center">
          <Link
            href="/tools"
            className="inline-flex h-11 items-center gap-2 rounded-full border border-line-strong bg-white/60 px-5 text-[0.85rem] font-semibold text-ink transition-colors hover:border-ink hover:bg-white"
          >
            Browse all {tools.length} tools
            <Icon name="arrowRight" className="h-3.5 w-3.5" />
          </Link>
        </div>
      ) : null}
    </div>
  );
}
