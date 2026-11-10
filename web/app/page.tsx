import Link from "next/link";
import { AppMockup } from "@/components/app-mockup";
import { CommandPaletteTrigger } from "@/components/command-palette";
import { ComparisonTable } from "@/components/comparison";
import { FaqList } from "@/components/faq-list";
import { FeatureBento } from "@/components/feature-bento";
import { FinalCta } from "@/components/final-cta";
import { Icon } from "@/components/icons";
import { ToolMarquee } from "@/components/marquee";
import { NotchDemo } from "@/components/notch-demo";
import { PricingCards } from "@/components/pricing-cards";
import { PrivacyGrid } from "@/components/privacy-grid";
import { Reveal } from "@/components/reveal";
import { ToolCard } from "@/components/tool-catalog";
import { Badge, ButtonLink, SectionHeader } from "@/components/ui";
import {
  counts,
  getTool,
  notchModules,
  readyNotch,
  tools,
} from "@/lib/catalog";
import { FAQ } from "@/lib/site";

export const dynamic = "force-static";

const FEATURED = [
  "json-formatter",
  "transcribe",
  "merge-pdfs",
  "convert-video",
  "remove-metadata",
  "qr-code",
  "regex-tester",
  "beautify-screenshot",
  "keep-awake",
  "batch-rename",
  "battery-health",
  "base64",
]
  .map((slug) => getTool(slug))
  .filter((t): t is NonNullable<typeof t> => Boolean(t));

const NOTCH_GROUPS = Array.from(new Set(notchModules.map((m) => m.group)));

export default function HomePage() {
  const ready = counts.implementedTools;

  return (
    <>
      {/* ── Hero ─────────────────────────────────────────────────────────── */}
      <section className="relative overflow-hidden">
        <div className="pointer-events-none absolute inset-0 dot-grid opacity-[0.55] [mask-image:radial-gradient(ellipse_70%_60%_at_50%_20%,black,transparent)]" />
        <div className="pointer-events-none absolute -top-40 left-1/2 h-[520px] w-[820px] -translate-x-1/2 rounded-full bg-ember/[0.10] blur-[110px]" />

        <div className="wrap relative grid items-center gap-12 pb-16 pt-14 lg:grid-cols-[1.02fr_1fr] lg:gap-10 lg:pb-24 lg:pt-20">
          <div className="max-w-xl">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone="ember">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ember" />
                Nookit 0.1 · {ready} tools ready
              </Badge>
              <Badge tone="outline">macOS 14 Sonoma or later</Badge>
            </div>

            <h1 className="mt-5 text-[clamp(2.6rem,6.2vw,4.6rem)] font-semibold leading-[0.96] tracking-[-0.055em]">
              94 Mac tools.
              <br />
              One{" "}
              <em className="font-serif font-normal italic tracking-[-0.03em] text-ember">
                notch
              </em>{" "}
              away.
            </h1>

            <p className="mt-5 max-w-lg text-[1rem] leading-relaxed text-slate">
              Every file job, text job and Mac chore in one private app — plus a
              notch that shows your day without taking it. Video, audio, images,
              PDFs, speech, developer utilities and the small things macOS leaves
              to you.
            </p>

            <div className="mt-7 flex flex-wrap items-end gap-x-4 gap-y-1">
              <span className="text-[2.2rem] font-semibold leading-none tracking-[-0.04em]">
                $19
              </span>
              <span className="pb-0.5 text-[0.95rem] text-slate -tracking-tight">
                <s className="decoration-line-strong">$49.99</s>{" "}
                <span className="font-semibold text-ember-deep">62% off</span> · once
              </span>
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-3">
              <ButtonLink href="/pricing" size="lg">
                Buy Nookit
                <Icon name="arrowRight" className="h-4 w-4" />
              </ButtonLink>
              <ButtonLink href="#inside" variant="ghost" size="lg">
                <Icon name="play" className="h-3.5 w-3.5" />
                Take the tour
              </ButtonLink>
            </div>

            <div className="mt-5 flex flex-wrap items-center gap-x-4 gap-y-2 text-[0.72rem] text-slate">
              {[
                "One-time purchase",
                "3 Macs on the 3-Mac licence",
                "Notarized before release",
              ].map((item) => (
                <span key={item} className="flex items-center gap-1.5">
                  <Icon name="check" className="h-3 w-3 text-mint-deep" strokeWidth={2.6} />
                  {item}
                </span>
              ))}
            </div>

            <dl className="mt-8 grid max-w-lg grid-cols-4 gap-3 border-t border-line pt-5">
              {[
                { k: String(counts.tools), v: "tools" },
                { k: String(ready), v: "ready now" },
                { k: String(counts.notch), v: "notch modules" },
                { k: "0", v: "uploads" },
              ].map((stat) => (
                <div key={stat.v}>
                  <dt className="text-[1.35rem] font-semibold leading-none tracking-[-0.03em]">
                    {stat.k}
                  </dt>
                  <dd className="mt-1 text-[0.66rem] uppercase tracking-[0.08em] text-slate-2">
                    {stat.v}
                  </dd>
                </div>
              ))}
            </dl>
          </div>

          <div className="relative lg:pl-2">
            <div className="animate-float">
              <AppMockup />
            </div>
            <p className="mt-8 text-center text-[0.66rem] text-slate-2">
              An interactive preview. Click a category on the left — the real app
              behaves the same way.
            </p>
          </div>
        </div>
      </section>

      <ToolMarquee />

      {/* ── What's inside ────────────────────────────────────────────────── */}
      <section id="inside" className="scroll-mt-24 py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="What's inside"
              title={
                <>
                  A toolbox that behaves like
                  <br className="hidden sm:block" /> a Mac app, not a website.
                </>
              }
              body="Native windows. Files that never leave the machine. Each tool opens with only the settings it needs, and every run writes to its own folder so you can find the result later."
              action={
                <ButtonLink href="/tools" variant="ghost" size="sm">
                  All {counts.tools} tools
                  <Icon name="arrowRight" className="h-3.5 w-3.5" />
                </ButtonLink>
              }
            />
          </Reveal>

          <Reveal delay={80} className="mt-10">
            <FeatureBento />
          </Reveal>

          <Reveal delay={120}>
            <div className="mt-10 grid gap-3 rounded-2xl border border-line bg-white/60 p-2 sm:grid-cols-3">
              {[
                {
                  step: "01",
                  title: "Drop it in",
                  body: "A file, a folder, or a link. Or paste text straight into the tool.",
                  icon: "folder" as const,
                },
                {
                  step: "02",
                  title: "Choose the one setting that matters",
                  body: "Quality, format, page range, case. The rest has a good default.",
                  icon: "slider" as const,
                },
                {
                  step: "03",
                  title: "Take the result",
                  body: "A dated folder, a Reveal button, and the original untouched.",
                  icon: "check" as const,
                },
              ].map((s) => (
                <div key={s.step} className="rounded-xl bg-paper p-4">
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-[0.66rem] text-slate-2">{s.step}</span>
                    <Icon
                      name={s.icon === "slider" ? "grid" : s.icon}
                      className="h-4 w-4 text-slate-2"
                    />
                  </div>
                  <h3 className="mt-3 text-[0.9rem] font-semibold">{s.title}</h3>
                  <p className="mt-1 text-[0.78rem] leading-relaxed text-slate">{s.body}</p>
                </div>
              ))}
            </div>
          </Reveal>
        </div>
      </section>

      {/* ── Notch ────────────────────────────────────────────────────────── */}
      <section id="notch" className="ink-section scroll-mt-24 py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              dark
              eyebrow="Included with Nookit · not a second app"
              title={
                <>
                  Your whole day,
                  <br className="hidden sm:block" /> in the notch.
                </>
              }
              body={`${counts.notch} small tools for the top of the screen, ${readyNotch.length} ready today. Clipboard, notes, tasks, timers, your next meeting, now playing, water, breathing, habits and a private AI assistant — one hover away, then gone. The other 14 are roadmap entries included in the purchase.`}
              action={
                <ButtonLink href="/notch" variant="light" size="sm">
                  Explore the notch
                  <Icon name="arrowRight" className="h-3.5 w-3.5" />
                </ButtonLink>
              }
            />
          </Reveal>

          <Reveal delay={80} className="mt-10">
            <NotchDemo />
          </Reveal>

          <Reveal delay={120}>
            <div className="mt-12 grid gap-6 border-t border-white/10 pt-8 sm:grid-cols-2 lg:grid-cols-5">
              {NOTCH_GROUPS.map((group) => (
                <div key={group}>
                  <p className="text-[0.62rem] font-semibold uppercase tracking-[0.14em] text-paper/30">
                    {group}
                  </p>
                  <ul className="mt-2.5 space-y-1.5">
                    {notchModules
                      .filter((m) => m.group === group)
                      .map((m) => (
                        <li key={m.id}>
                          <Link
                            href={`/notch#${m.id}`}
                            className="group flex items-center gap-2 text-[0.78rem] text-paper/60 transition-colors hover:text-paper"
                          >
                            <span
                              className={`h-1 w-1 rounded-full ${
                                m.implemented ? "bg-mint" : "bg-paper/20"
                              }`}
                            />
                            {m.name}
                            {m.shortcut ? (
                              <span className="ml-auto hidden font-mono text-[0.58rem] text-paper/25 lg:inline">
                                {m.shortcut}
                              </span>
                            ) : null}
                          </Link>
                        </li>
                      ))}
                  </ul>
                </div>
              ))}
            </div>
            <p className="mt-5 flex items-center gap-2 text-[0.66rem] text-paper/30">
              <span className="h-1 w-1 rounded-full bg-mint" />
              Ready now
              <span className="ml-3 h-1 w-1 rounded-full bg-paper/20" />
              Free update
            </p>
          </Reveal>

          <Reveal delay={160}>
            <div className="mt-8 grid gap-3 sm:grid-cols-3">
              {[
                {
                  icon: "command" as const,
                  title: "One shortcut away",
                  body: "Clipboard on ⌃⌘V, notes on ⌥⌘J, AI on ⌥⌘A. Or just hover.",
                },
                {
                  icon: "display" as const,
                  title: "Works without a notch",
                  body: "On older Macs it draws its own pill at the top centre. Same modules.",
                },
                {
                  icon: "shield" as const,
                  title: "Not in the screen share",
                  body: "The panel is excluded from capture, so notes and clipboard stay private.",
                },
              ].map((item) => (
                <div
                  key={item.title}
                  className="rounded-xl border border-white/10 bg-white/[0.03] p-4"
                >
                  <Icon name={item.icon} className="h-4 w-4 text-ember-soft" />
                  <h3 className="mt-2.5 text-[0.86rem] font-semibold">{item.title}</h3>
                  <p className="mt-1 text-[0.76rem] leading-relaxed text-paper/45">
                    {item.body}
                  </p>
                </div>
              ))}
            </div>
          </Reveal>
        </div>
      </section>

      {/* ── Tools ────────────────────────────────────────────────────────── */}
      <section id="tools" className="scroll-mt-24 py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="The catalogue"
              title="A dozen to start with. Ninety-four when you need them."
              body={`All ${ready} tools are ready in this build, each with its own screen. Every one is included in the purchase — no upgrade tier, no credit packs.`}
              action={
                <ButtonLink href="/tools" variant="ghost" size="sm">
                  Browse all {counts.tools}
                  <Icon name="arrowRight" className="h-3.5 w-3.5" />
                </ButtonLink>
              }
            />
          </Reveal>

          <Reveal delay={80}>
            <div className="mt-10 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {FEATURED.map((tool) => (
                <ToolCard key={tool.slug} tool={tool} />
              ))}
            </div>
          </Reveal>

          <Reveal delay={120}>
            <div className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-line bg-paper-2/50 px-5 py-4">
              <p className="text-[0.82rem] text-slate">
                Looking for one job in particular? Press{" "}
                <span className="font-semibold text-ink">⌘K</span> anywhere on this
                site, or open the full catalogue.
              </p>
              <div className="flex items-center gap-2">
                <CommandPaletteTrigger />
                <ButtonLink href="/tools" size="sm">
                  All tools
                  <Icon name="arrowRight" className="h-3.5 w-3.5" />
                </ButtonLink>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ── One app instead of ten ───────────────────────────────────────── */}
      <section className="py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="The maths"
              title="One app instead of ten."
              body="The single-purpose apps people collect, and the Nookit tool that does the same everyday job."
            />
          </Reveal>
          <Reveal delay={80} className="mt-8">
            <ComparisonTable />
          </Reveal>
        </div>
      </section>

      {/* ── Privacy ──────────────────────────────────────────────────────── */}
      <section id="privacy" className="scroll-mt-24 bg-paper-2/40 py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="Private by design"
              title="Online converters ask for the file first. Nookit does not."
              body="Compression, transcription, PDF work, image editing and every Mac utility run locally. Permissions are explained before macOS asks, and only when a tool you opened needs one."
            />
          </Reveal>
          <Reveal delay={80} className="mt-10">
            <PrivacyGrid />
          </Reveal>
        </div>
      </section>

      {/* ── Pricing ──────────────────────────────────────────────────────── */}
      <section id="pricing" className="scroll-mt-24 py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              align="center"
              eyebrow="Pricing"
              title="Pay once. Use it every day."
              body="One payment for the licence you need. Free updates. No subscription, no tool held back for a higher tier."
            />
          </Reveal>
          <Reveal delay={80} className="mt-9">
            <PricingCards id="pricing-card" />
          </Reveal>
        </div>
      </section>

      {/* ── FAQ ──────────────────────────────────────────────────────────── */}
      <section id="faq" className="scroll-mt-24 py-20">
        <div className="wrap grid gap-10 lg:grid-cols-[0.72fr_1.28fr]">
          <div className="lg:sticky lg:top-28 lg:self-start">
            <Reveal>
              <p className="eyebrow">Questions</p>
              <h2 className="mt-3 text-[clamp(1.9rem,3.4vw,2.8rem)] font-semibold leading-[1.04]">
                The things people ask before buying.
              </h2>
              <p className="mt-4 max-w-sm text-[0.9rem] leading-relaxed text-slate">
                Something else? Email{" "}
                <a
                  href="mailto:support@nookit.app"
                  className="font-semibold text-ink underline decoration-line-strong underline-offset-4"
                >
                  support@nookit.app
                </a>{" "}
                and a person answers.
              </p>
              <div className="mt-5 flex flex-wrap gap-2">
                <Badge tone="mint">14-day refund</Badge>
                <Badge tone="neutral">No subscription</Badge>
                <Badge tone="neutral">Human support</Badge>
              </div>
            </Reveal>
          </div>
          <Reveal delay={60}>
            <FaqList items={FAQ} />
          </Reveal>
        </div>
      </section>

      {/* ── Join the waitlist ────────────────────────────────────────────── */}
      <section className="py-20">
        <div className="wrap">
          <Reveal>
            <div className="relative overflow-hidden rounded-[28px] border border-line bg-ink px-6 py-14 text-paper md:px-12">
              <div className="pointer-events-none absolute -right-20 -top-20 h-72 w-72 rounded-full bg-ember/30 blur-3xl" />
              <div className="pointer-events-none absolute -bottom-24 -left-16 h-72 w-72 rounded-full bg-mint/20 blur-3xl" />
              <div className="relative grid gap-8 md:grid-cols-[1.1fr_1fr] md:items-center">
                <div>
                  <p className="eyebrow text-ember-soft">Early access</p>
                  <h2 className="mt-3 text-[clamp(1.9rem,3.6vw,2.8rem)] font-semibold leading-[1.04] tracking-[-0.03em]">
                    Join the waitlist.
                  </h2>
                  <p className="mt-3 max-w-md text-[0.9rem] leading-relaxed text-paper/60">
                    Be the first to hear when Nookit ships, plus release notes and
                    the occasional behind-the-scenes. No spam, unsubscribe any
                    time.
                  </p>
                </div>
                <form className="flex flex-col gap-3 sm:flex-row">
                  <input
                    type="email"
                    placeholder="you@domain.com"
                    className="flex-1 rounded-full border border-white/15 bg-white/[0.06] px-5 py-3 text-[0.9rem] text-paper placeholder:text-paper/40 focus:border-ember focus:outline-none"
                  />
                  <button
                    type="submit"
                    className="rounded-full bg-ember px-6 py-3 text-[0.9rem] font-semibold text-ink transition hover:bg-ember-soft"
                  >
                    Join waitlist
                  </button>
                </form>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ── What's new in Nookit ─────────────────────────────────────────── */}
      <section className="py-20">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="New in this build"
              title="Nookit AI, Hype and Apps — all inside Nookit."
              body="Chat with Nookit AI, plan a meal, a night out or a trip with Hype, and connect Google Workspace from Apps. Everything runs on your Mac."
            />
          </Reveal>
          <Reveal delay={80} className="mt-10">
            <div className="grid gap-4 md:grid-cols-3">
              {[
                {
                  title: "Nookit AI",
                  body: "Persistent chat with image and document analysis, powered by NVIDIA models. Providers: Automatic, Apple Intelligence, Nookit AI.",
                  icon: "sparkles",
                },
                {
                  title: "Hype",
                  body: "Food, Events and Travel with live data — Swiggy/Zomato menus, District movies and showtimes, Google Flights/Hotels and eRail trains with fares.",
                  icon: "map",
                },
                {
                  title: "Apps",
                  body: "Real Google Workspace actions after OAuth: Docs, Sheets, Slides, Gmail, Calendar, Meet and Drive.",
                  icon: "grid",
                },
              ].map((f) => (
                <div
                  key={f.title}
                  className="rounded-[22px] border border-line bg-white p-6"
                >
                  <h3 className="text-[1.1rem] font-semibold tracking-[-0.02em]">
                    {f.title}
                  </h3>
                  <p className="mt-2 text-[0.82rem] leading-relaxed text-slate">
                    {f.body}
                  </p>
                </div>
              ))}
            </div>
          </Reveal>

        </div>
      </section>

      <FinalCta />
    </>
  );
}
