import type { Metadata } from "next";
import { Icon } from "@/components/icons";
import { Reveal } from "@/components/reveal";
import { Badge, ButtonLink, SectionHeader } from "@/components/ui";
import { CHANGELOG } from "@/lib/site";

export const metadata: Metadata = {
  title: "Changelog",
  description:
    "What shipped in each Nookit build, what is in progress, and what is next on the roadmap.",
  alternates: { canonical: "/changelog" },
};

export default function ChangelogPage() {
  return (
    <>
      <section className="border-b border-line bg-paper-2/30">
        <div className="wrap py-14 md:py-18">
          <div className="flex flex-col gap-5 md:flex-row md:items-end md:justify-between">
            <div>
              <p className="eyebrow">Changelog</p>
              <h1 className="mt-3 text-[clamp(2.3rem,5vw,3.7rem)] font-semibold leading-[1]">
                What actually shipped.
              </h1>
              <p className="mt-4 max-w-xl text-[0.95rem] leading-relaxed text-slate">
                No “minor improvements” filler. Each build lists the tools and
                behaviour that changed, and what is still in progress.
              </p>
            </div>
            <div className="flex gap-2">
              <Badge tone="mint">Current: 0.1.0</Badge>
              <Badge tone="outline">Roadmap public</Badge>
            </div>
          </div>
        </div>
      </section>

      <section className="wrap max-w-4xl py-12">
        <div className="space-y-4">
          {CHANGELOG.map((entry, i) => (
            <Reveal key={entry.version} delay={i * 60}>
              <article className="rounded-2xl border border-line bg-white/70 p-5 md:p-6">
                <div className="flex flex-wrap items-center gap-3">
                  <span className="rounded-full bg-ink px-2.5 py-1 font-mono text-[0.7rem] font-semibold text-paper">
                    v{entry.version}
                  </span>
                  <span className="text-[0.72rem] text-slate-2">{entry.date}</span>
                  {entry.date === "Planned" ? (
                    <Badge tone="outline">In progress</Badge>
                  ) : entry.version === "0.1.0" ? (
                    <Badge tone="outline">Pre-release</Badge>
                  ) : (
                    <Badge tone="mint">Shipped</Badge>
                  )}
                </div>
                <h2 className="mt-3 text-[1.25rem] font-semibold tracking-[-0.02em]">
                  {entry.title}
                </h2>
                <ul className="mt-3 space-y-2">
                  {entry.items.map((item) => (
                    <li key={item} className="flex items-start gap-2.5 text-[0.85rem] leading-relaxed text-slate">
                      <Icon
                        name={entry.date === "Planned" ? "arrowRight" : "check"}
                        className={`mt-0.5 h-3.5 w-3.5 shrink-0 ${
                          entry.date === "Planned" ? "text-slate-2" : "text-mint-deep"
                        }`}
                        strokeWidth={2.4}
                      />
                      {item}
                    </li>
                  ))}
                </ul>
              </article>
            </Reveal>
          ))}
        </div>

        <Reveal delay={120}>
          <div className="mt-10 rounded-2xl border border-line bg-paper-2/60 p-6">
            <SectionHeader
              eyebrow="How to read this"
              title="A roadmap is a promise of work, not a date."
              body="All 94 tool entries are ready in this build; the remaining roadmap is the 14 notch modules, which are included in your licence and ship when they are good enough — not on a marketing schedule."
              action={
                <ButtonLink href="/tools" variant="ghost" size="sm">
                  See tool status
                  <Icon name="arrowRight" className="h-3.5 w-3.5" />
                </ButtonLink>
              }
            />
          </div>
        </Reveal>
      </section>
    </>
  );
}
