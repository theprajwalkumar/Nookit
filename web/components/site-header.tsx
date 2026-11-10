"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { counts } from "@/lib/catalog";
import { LAUNCH_ENDS, NAV } from "@/lib/site";
import { useScrollLock } from "@/lib/use-scroll-lock";
import { Icon, Logo } from "./icons";
import { CommandPalette, SearchTrigger } from "./command-palette";
import { ButtonLink, Kbd } from "./ui";

const DEADLINE = LAUNCH_ENDS;

function pad(n: number) {
  return String(n).padStart(2, "0");
}

export function SiteHeader() {
  const [scrolled, setScrolled] = useState(false);
  const [menu, setMenu] = useState(false);
  const [left, setLeft] = useState<number | null>(null);

  useScrollLock(menu);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    const tick = () => setLeft(DEADLINE - Date.now());
    tick();
    const id = window.setInterval(tick, 1000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!menu) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMenu(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [menu]);

  const days = left && left > 0 ? Math.floor(left / 86_400_000) : 0;
  const hours = left && left > 0 ? Math.floor((left % 86_400_000) / 3_600_000) : 0;
  const mins = left && left > 0 ? Math.floor((left % 3_600_000) / 60_000) : 0;
  const secs = left && left > 0 ? Math.floor((left % 60_000) / 1000) : 0;

  return (
    <>
      {left !== null && left > 0 ? (
        <div className="ink-section relative z-50 border-b border-white/10">
          <div className="wrap flex h-9 items-center justify-between gap-4 text-[0.72rem]">
            <p className="flex items-center gap-2 text-paper/70">
              <span className="inline-flex h-1.5 w-1.5 animate-pulse rounded-full bg-ember" />
              <span className="hidden sm:inline">Launch price — 62% off.</span>
              <span className="sm:hidden">62% off.</span>
              <span className="text-paper/40">Ends in</span>
              <span className="tabular font-mono text-paper/85" suppressHydrationWarning>
                {days}d {pad(hours)}h {pad(mins)}m {pad(secs)}s
              </span>
            </p>
            <Link
              href="/pricing"
              className="group inline-flex items-center gap-1 font-semibold text-ember-soft hover:text-paper"
            >
              See pricing
              <Icon name="arrowRight" className="h-3 w-3" />
            </Link>
          </div>
        </div>
      ) : null}

      <header
        className={`sticky top-0 z-40 transition-colors duration-200 ${
          scrolled
            ? "border-b border-line bg-paper/85 backdrop-blur-xl"
            : "border-b border-transparent bg-paper/60 backdrop-blur-sm"
        }`}
      >
        <div className="wrap flex h-16 items-center gap-6">
          <Link href="/" className="shrink-0" aria-label="Nookit home">
            <Logo />
          </Link>

          <nav className="hidden items-center gap-1 lg:flex" aria-label="Primary">
            {NAV.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="rounded-full px-3 py-2 text-[0.84rem] font-medium text-slate transition-colors hover:bg-paper-2 hover:text-ink"
              >
                {item.label}
              </Link>
            ))}
          </nav>

          <div className="ml-auto flex items-center gap-2.5">
            <CommandPalette />
            <SearchTrigger />
            <Link
              href="/download"
              className="hidden text-[0.84rem] font-semibold text-ink hover:text-ember-deep sm:block"
            >
              Download
            </Link>
            <ButtonLink href="/pricing" size="sm" className="hidden sm:inline-flex">
              Buy — $19
            </ButtonLink>
            <button
              type="button"
              onClick={() => setMenu(true)}
              className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-line-strong lg:hidden"
              aria-label="Open menu"
              aria-expanded={menu}
            >
              <Icon name="menu" className="h-4 w-4" />
            </button>
          </div>
        </div>
      </header>

      {menu ? (
        <div className="fixed inset-0 z-[70] bg-paper lg:hidden">
          <div className="wrap flex h-16 items-center justify-between">
            <Logo />
            <button
              type="button"
              onClick={() => setMenu(false)}
              className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-line-strong"
              aria-label="Close menu"
            >
              <Icon name="close" className="h-4 w-4" />
            </button>
          </div>
          <nav className="wrap mt-6 flex flex-col gap-1" aria-label="Mobile">
            {[{ label: `All ${counts.tools} tools`, href: "/tools" }, ...NAV].map((item) => (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setMenu(false)}
                className="flex items-center justify-between border-b border-line py-4 text-[1.35rem] font-medium tracking-tight"
              >
                {item.label}
                <Icon name="arrowUpRight" className="h-4 w-4 text-slate-2" />
              </Link>
            ))}
          </nav>
          <div className="wrap mt-8 flex flex-col gap-3">
            <ButtonLink href="/pricing" size="lg" className="w-full">
              Buy Nookit — $19
            </ButtonLink>
            <ButtonLink href="/download" variant="ghost" size="lg" className="w-full">
              Download
            </ButtonLink>
            <p className="mt-4 text-center text-[0.76rem] text-slate">
              One payment · macOS 14+ · 3 Macs on the 3-Mac licence
            </p>
            <p className="mt-2 text-center text-[0.7rem] text-slate-2">
              <Kbd>⌘</Kbd> <Kbd>K</Kbd> searches everything
            </p>
          </div>
        </div>
      ) : null}
    </>
  );
}
