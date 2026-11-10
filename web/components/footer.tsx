import Link from "next/link";
import { categories, counts } from "@/lib/catalog";
import { SITE } from "@/lib/site";
import { Icon, Logo } from "./icons";

const columns = [
  {
    title: "Product",
    links: [
      { label: "All tools", href: "/tools" },
      { label: "The notch", href: "/notch" },
      { label: "Pricing", href: "/pricing" },
      { label: "Download", href: "/download" },
      { label: "Changelog", href: "/changelog" },
    ],
  },
  {
    title: "Categories",
    links: categories.slice(0, 8).map((c) => ({
      label: c.name,
      href: `/tools#${c.id}`,
    })),
  },
  {
    title: "Support",
    links: [
      { label: "Setup guide", href: "/download#setup" },
      { label: "FAQ", href: "/#faq" },
      { label: "Email us", href: `mailto:${SITE.support}` },
      { label: "Privacy", href: "/privacy" },
      { label: "Terms", href: "/terms" },
      { label: "Refunds", href: "/terms#refunds" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="ink-section grain relative overflow-hidden">
      <div className="pointer-events-none absolute -top-40 left-1/2 h-80 w-[900px] -translate-x-1/2 rounded-full bg-ember/10 blur-[120px]" />
      <div className="wrap relative py-14">
        <div className="grid gap-10 border-b border-white/10 pb-10 lg:grid-cols-[1.6fr_1fr_1fr_1fr]">
          <div>
            <Logo tone="paper" />
            <p className="mt-4 max-w-xs text-[0.85rem] leading-relaxed text-paper/50">
              {counts.tools} private tools for the Mac, and a notch that earns its keep.
              One payment, no account, nothing uploaded.
            </p>
            <div className="mt-5 flex flex-wrap gap-2">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-white/[0.06] px-2.5 py-1 text-[0.68rem] text-paper/55">
                <Icon name="shield" className="h-3 w-3 text-mint" />
                On-device by default
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-white/[0.06] px-2.5 py-1 text-[0.68rem] text-paper/55">
                <Icon name="lock" className="h-3 w-3 text-ember-soft" />
                No account needed
              </span>
            </div>
            <div className="mt-6 flex items-center gap-3">
              <a
                href={`mailto:${SITE.support}`}
                className="text-[0.78rem] text-paper/50 underline decoration-white/20 underline-offset-4 hover:text-paper"
              >
                {SITE.support}
              </a>
            </div>
          </div>

          {columns.map((col) => (
            <div key={col.title}>
              <p className="text-[0.66rem] font-semibold uppercase tracking-[0.14em] text-paper/35">
                {col.title}
              </p>
              <ul className="mt-3.5 space-y-2">
                {col.links.map((link) => (
                  <li key={link.label + link.href}>
                    <Link
                      href={link.href}
                      className="text-[0.82rem] text-paper/60 transition-colors hover:text-paper"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="flex flex-col gap-4 pt-6 text-[0.7rem] text-paper/35 md:flex-row md:items-center md:justify-between">
          <p>© 2026 Nookit. All rights reserved.</p>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
            <span className="flex items-center gap-1.5">
              <span className="h-1.5 w-1.5 rounded-full bg-mint" />
              macOS 14 Sonoma or later
            </span>
            <span className="hidden h-3 w-px bg-white/15 md:block" />
            <Link href="/privacy" className="hover:text-paper/70">
              Privacy
            </Link>
            <Link href="/terms" className="hover:text-paper/70">
              Terms
            </Link>
            <Link href="/changelog" className="hover:text-paper/70">
              Changelog
            </Link>
          </div>
        </div>
        <p className="mt-4 max-w-4xl text-[0.64rem] leading-relaxed text-paper/25">
          Apple, Mac, macOS, Apple Intelligence and SF Symbols are trademarks of Apple Inc.
          Nookit is an independent product and is not affiliated with or endorsed by Apple.
          FFmpeg is a trademark of Fabrice Bellard. Prices shown in USD; taxes are calculated
          at checkout.
        </p>
      </div>
    </footer>
  );
}
