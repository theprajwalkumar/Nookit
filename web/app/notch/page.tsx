import type { Metadata } from "next";
import Link from "next/link";
import { FaqList } from "@/components/faq-list";
import { Icon, iconForSymbol } from "@/components/icons";
import { NotchDemo } from "@/components/notch-demo";
import { PricingCards } from "@/components/pricing-cards";
import { Reveal } from "@/components/reveal";
import { Badge, ButtonLink, SectionHeader } from "@/components/ui";
import { counts, notchModules, readyNotch } from "@/lib/catalog";
import { NOTCH_FAQ } from "@/lib/site";

export const metadata: Metadata = {
  title: "The notch — 24 modules, 10 ready today",
  description:
    "Nookit includes a notch overlay with 10 working modules today and 14 more planned: clipboard history, notes, tasks, timers, calendar, music, hydration, breathing, habits and a private AI assistant, plus dictation, rewrite, mirror, snippets, reminders and more.",
  alternates: { canonical: "/notch" },
  openGraph: {
    title: "The notch — included with Nookit",
    description:
      "24 modules, 10 ready today: clipboard, notes, tasks, timers, calendar, music and private AI. One purchase.",
    url: "/notch",
  },
};

const REASONS = [
  {
    icon: "command" as const,
    title: "Hover to open. Click to pin.",
    body: "It opens on approach, closes when you leave, and stays put if you click. No keyboard shortcut required — though each visible module has a number key while the panel is open.",
  },
  {
    icon: "grid" as const,
    title: "Pick your tools. Hide the rest.",
    body: "Turn any of the 10 working modules on or off in Settings. The other 14 are roadmap entries and will join the same row as they ship.",
  },
  {
    icon: "display" as const,
    title: "Works on any Mac.",
    body: "No notch? Nookit draws its own pill at the top centre. Same modules, same shortcuts, same behaviour.",
  },
  {
    icon: "shield" as const,
    title: "Keep private things off the call.",
    body: "The panel is excluded from screen capture. Your notes and clipboard stay out of a share, and the teleprompter and revenue modules will use the same behaviour when they land.",
  },
  {
    icon: "timer" as const,
    title: "Closed, it sleeps.",
    body: "Collapsed, it shows a short status from a running timer, the next meeting, now playing, open tasks or water, then gets out of the way. There is no animation loop and no GPU work, and none of those checks use the network.",
  },
  {
    icon: "folder" as const,
    title: "Your data stays put.",
    body: "Notes live as Markdown in Application Support, tasks in a JSON file beside them, and clipboard history in the app's own preferences. Nothing is synced, and you can read or delete it yourself.",
  },
];

const GROUPS = ["AI", "Calls", "Work", "Focus", "Day"] as const;

export default function NotchPage() {
  return (
    <>
      <section className="ink-section relative overflow-hidden">
        <div className="pointer-events-none absolute inset-0 dot-grid-dark opacity-50 [mask-image:radial-gradient(ellipse_60%_60%_at_50%_0%,black,transparent)]" />
        <div className="pointer-events-none absolute -top-40 left-1/2 h-[480px] w-[760px] -translate-x-1/2 rounded-full bg-ember/[0.13] blur-[110px]" />
        <div className="wrap relative py-16 md:py-20">
          <div className="mx-auto max-w-3xl text-center">
            <Badge tone="dark">
              <span className="h-1.5 w-1.5 rounded-full bg-ember" />
              Included with Nookit · not a second app
            </Badge>
            <h1 className="mt-5 text-[clamp(2.6rem,6vw,4.6rem)] font-semibold leading-[0.96]">
              Your whole day,
              <br />
              in the{" "}
              <em className="font-serif font-normal italic text-ember-soft">notch</em>.
            </h1>
            <p className="mx-auto mt-5 max-w-xl text-[1rem] leading-relaxed text-paper/55">
              {counts.notch} small tools for the top of the screen,{" "}
              {readyNotch.length} ready today. Clipboard, notes, tasks, timers, your
              next meeting, now playing, water, breathing, habits and a private AI
              assistant — the other 14 arrive as free updates.
            </p>
            <div className="mt-7 flex flex-wrap justify-center gap-3">
              <ButtonLink href="/pricing" size="lg">
                Buy Nookit — $19
                <Icon name="arrowRight" className="h-4 w-4" />
              </ButtonLink>
              <ButtonLink href="#modules" variant="ghost" size="lg" className="!border-white/20 !text-paper hover:!border-white/40">
                See all {counts.notch} modules
              </ButtonLink>
            </div>
            <p className="mt-4 text-[0.72rem] text-paper/35">
              macOS 14+ · Macs with or without a notch · no subscription
            </p>
          </div>

          <div className="mt-12">
            <NotchDemo auto={false} />
          </div>
        </div>
      </section>

      <section className="py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="Why a notch"
              title="Every reason to give your notch a job."
              body="The notch is the one piece of screen you look at without thinking. Nookit makes it useful without making it loud."
            />
          </Reveal>
          <div className="mt-10 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            {REASONS.map((reason, i) => (
              <Reveal key={reason.title} delay={i * 50}>
                <div className="h-full rounded-2xl border border-line bg-white/70 p-5 transition-colors hover:bg-white">
                  <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-ink text-paper">
                    <Icon name={reason.icon} className="h-4 w-4" />
                  </span>
                  <h3 className="mt-3 text-[1rem] font-semibold tracking-[-0.02em]">
                    {reason.title}
                  </h3>
                  <p className="mt-1.5 text-[0.82rem] leading-relaxed text-slate">
                    {reason.body}
                  </p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section id="modules" className="scroll-mt-24 bg-paper-2/40 py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="The modules"
              title="Twenty-four modules, grouped by when you need them."
              body="Green dot means the module is in this build. Grey means it is specified and coming as a free update. Every one is included in the licence."
            />
          </Reveal>

          <div className="mt-10 space-y-10">
            {GROUPS.map((group) => {
              const list = notchModules.filter((m) => m.group === group);
              if (list.length === 0) return null;
              return (
                <div key={group}>
                  <div className="flex items-center gap-3 border-b border-line pb-3">
                    <h3 className="text-[1.05rem] font-semibold tracking-[-0.02em]">
                      {group === "Day" ? "Your day" : group === "Focus" ? "Focus & builders" : group}
                    </h3>
                    <span className="text-[0.66rem] font-semibold text-slate-2">
                      {list.length}
                    </span>
                    <span className="ml-auto text-[0.62rem] uppercase tracking-[0.1em] text-slate-2">
                      {list.filter((m) => m.implemented).length} ready
                    </span>
                  </div>
                  <div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
                    {list.map((m) => (
                      <div
                        key={m.id}
                        id={m.id}
                        className="scroll-mt-28 rounded-2xl border border-line bg-white/70 p-4"
                      >
                        <div className="flex items-start justify-between gap-2">
                          <span className="grid h-8 w-8 place-items-center rounded-[9px] bg-paper-2 text-ink">
                            <Icon name={iconForSymbol(m.symbol)} className="h-4 w-4" />
                          </span>
                          <div className="flex items-center gap-2">
                            {m.shortcut ? (
                              <span className="font-mono text-[0.6rem] text-slate-2">
                                {m.shortcut}
                              </span>
                            ) : null}
                            <span
                              className={`flex items-center gap-1 text-[0.58rem] font-semibold uppercase tracking-[0.08em] ${
                                m.implemented ? "text-mint-deep" : "text-slate-2"
                              }`}
                            >
                              <span
                                className={`h-1.5 w-1.5 rounded-full ${
                                  m.implemented ? "bg-mint-deep" : "bg-line-strong"
                                }`}
                              />
                              {m.implemented ? "Ready" : "Roadmap"}
                            </span>
                          </div>
                        </div>
                        <h4 className="mt-3 text-[0.9rem] font-semibold">{m.name}</h4>
                        <p className="mt-0.5 text-[0.72rem] font-medium text-ember-deep">
                          {m.tagline}
                        </p>
                        <p className="mt-2 text-[0.78rem] leading-relaxed text-slate">
                          {m.description}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      <section className="py-20">
        <div className="wrap grid gap-10 lg:grid-cols-[1fr_1fr] lg:items-center">
          <div>
            <Reveal>
              <p className="eyebrow">Included, not bundled</p>
              <h2 className="mt-3 text-[clamp(1.9rem,3.6vw,2.9rem)] font-semibold leading-[1.04]">
                Most notch apps are a second purchase.
                <br />
                This one is a feature.
              </h2>
              <p className="mt-4 max-w-lg text-[0.9rem] leading-relaxed text-slate">
                A dedicated notch utility typically costs $15–$20 on its own. With
                Nookit, the notch is part of the same $19 licence as the 94 tools —
                one app, one licence, one place for your notes and clipboard.
              </p>
              <div className="mt-5 flex flex-wrap gap-2">
                <Badge tone="mint">No second app</Badge>
                <Badge tone="neutral">No second subscription</Badge>
                <Badge tone="neutral">Data stays local</Badge>
              </div>
            </Reveal>
          </div>

          <Reveal delay={80}>
            <div className="overflow-hidden rounded-2xl border border-line bg-white">
              <div className="grid grid-cols-[1.3fr_0.85fr_0.85fr] gap-3 border-b border-line bg-paper-2/60 px-4 py-3 text-[0.6rem] font-semibold uppercase tracking-[0.1em] text-slate-2">
                <span>What you need</span>
                <span>Separate apps</span>
                <span>Nookit</span>
              </div>
              {[
                ["94 tools (all ready now)", "$200+", "Included"],
                ["Notch overlay", "$15–$20", "Included"],
                ["Clipboard history", "$5–$15", "Included"],
                ["Notch timers", "Free–$10", "Included"],
                ["Calendar countdown", "$5–$10", "Included"],
                ["AI assistant (local models)", "Often a subscription", "Included"],
              ].map((row) => (
                <div
                  key={row[0]}
                  className="grid grid-cols-[1.3fr_0.85fr_0.85fr] items-center gap-3 border-b border-line px-4 py-3 text-[0.78rem] last:border-0"
                >
                  <span className="font-medium">{row[0]}</span>
                  <span className="text-slate-2">{row[1]}</span>
                  <span className="inline-flex items-center gap-1 font-semibold text-mint-deep">
                    <Icon name="check" className="h-3 w-3" strokeWidth={3} />
                    {row[2]}
                  </span>
                </div>
              ))}
              <div className="flex items-center justify-between bg-ink px-4 py-3 text-paper">
                <span className="text-[0.72rem] text-paper/50">All of it, once</span>
                <span className="text-[1rem] font-semibold">$19</span>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      <section className="border-y border-line bg-paper-2/30 py-20">
        <div className="wrap grid gap-10 lg:grid-cols-[0.72fr_1.28fr]">
          <div className="lg:sticky lg:top-28 lg:self-start">
            <p className="eyebrow">Notch questions</p>
            <h2 className="mt-3 text-[clamp(1.8rem,3.2vw,2.6rem)] font-semibold leading-[1.04]">
              The practical details.
            </h2>
            <p className="mt-4 max-w-sm text-[0.88rem] leading-relaxed text-slate">
              Still curious?{" "}
              <a
                href="mailto:support@nookit.app"
                className="font-semibold text-ink underline decoration-line-strong underline-offset-4"
              >
                support@nookit.app
              </a>
              .
            </p>
          </div>
          <Reveal>
            <FaqList items={NOTCH_FAQ} />
          </Reveal>
        </div>
      </section>

      <section className="py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              align="center"
              eyebrow="One purchase"
              title="The tools and the notch, together."
              body="Buy once. Use it every day. The notch is part of the app, not an upsell."
            />
          </Reveal>
          <div className="mt-8">
            <PricingCards id="notch-pricing" />
          </div>
          <p className="mt-6 text-center text-[0.76rem] text-slate">
            Prefer the full story?{" "}
            <Link href="/tools" className="font-semibold underline decoration-line-strong underline-offset-4">
              Browse all {counts.tools} tools
            </Link>
            .
          </p>
        </div>
      </section>
    </>
  );
}
