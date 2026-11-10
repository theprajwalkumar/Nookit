import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ComparisonTable } from "@/components/comparison";
import { FaqList } from "@/components/faq-list";
import { Icon } from "@/components/icons";
import { Reveal } from "@/components/reveal";
import { ToolCard } from "@/components/tool-catalog";
import {
  Badge,
  ButtonLink,
  CategoryGlyph,
  StatusBadge,
  ToolGlyph,
} from "@/components/ui";
import {
  counts,
  getCategory,
  getTool,
  relatedTools,
  tools,
  type CategoryId,
} from "@/lib/catalog";
import { toolDetail } from "@/lib/tool-content";
import { FAQ } from "@/lib/site";

type Params = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return tools.map((tool) => ({ slug: tool.slug }));
}

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { slug } = await params;
  const tool = getTool(slug);
  if (!tool) return { title: "Tool not found" };
  const cat = getCategory(tool.category);
  const title = `${tool.name} for Mac`;
  return {
    title,
    description: `${tool.tagline} ${tool.description}`.slice(0, 158),
    alternates: { canonical: `/tools/${tool.slug}` },
    openGraph: {
      title: `${title} — Nookit`,
      description: tool.tagline,
      url: `/tools/${tool.slug}`,
      type: "article",
    },
    other: { "nookit:category": cat?.name ?? tool.category, "nookit:status": tool.implemented ? "ready" : "roadmap" },
  };
}

export default async function ToolPage({ params }: Params) {
  const { slug } = await params;
  const tool = getTool(slug);
  if (!tool) notFound();

  const cat = getCategory(tool.category);
  const detail = toolDetail(tool.category as CategoryId);
  const related = relatedTools(tool, 3);
  const faq = [FAQ[0], FAQ[1], FAQ[6]];

  return (
    <>
      <section className="relative overflow-hidden border-b border-line">
        <div className="pointer-events-none absolute inset-0 dot-grid opacity-40 [mask-image:radial-gradient(ellipse_60%_60%_at_40%_0%,black,transparent)]" />
        <div className="wrap relative py-12 md:py-16">
          <nav className="flex flex-wrap items-center gap-2 text-[0.72rem] text-slate">
            <Link href="/" className="hover:text-ink">
              Nookit
            </Link>
            <Icon name="chevronDown" className="h-3 w-3 -rotate-90" />
            <Link href="/tools" className="hover:text-ink">
              Tools
            </Link>
            <Icon name="chevronDown" className="h-3 w-3 -rotate-90" />
            <Link href={`/tools#${tool.category}`} className="hover:text-ink">
              {cat?.name}
            </Link>
            <Icon name="chevronDown" className="h-3 w-3 -rotate-90" />
            <span className="text-ink">{tool.name}</span>
          </nav>

          <div className="mt-7 grid gap-10 lg:grid-cols-[1.35fr_0.65fr]">
            <div>
              <div className="flex items-center gap-3">
                <ToolGlyph tool={tool} size="lg" />
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <StatusBadge tool={tool} />
                    <span className="inline-flex items-center gap-1 rounded-full bg-paper-2 px-2.5 py-1 text-[0.66rem] font-semibold text-slate">
                      <CategoryGlyph category={tool.category} className="!h-4 !w-4 !rounded-[4px]" />
                      {cat?.name}
                    </span>
                  </div>
                  <h1 className="mt-2 text-[clamp(2.1rem,4.6vw,3.4rem)] font-semibold leading-[1.0]">
                    {tool.name}
                  </h1>
                </div>
              </div>

              <p className="mt-5 max-w-2xl text-[1.15rem] font-medium leading-snug text-ink/85">
                {tool.tagline}
              </p>
              <p className="mt-3 max-w-2xl text-[0.94rem] leading-relaxed text-slate">
                {tool.description}
              </p>

              <div className="mt-6 flex flex-wrap gap-3">
                {tool.implemented ? (
                  <ButtonLink href="/pricing" size="md">
                    Get Nookit — $19
                    <Icon name="arrowRight" className="h-4 w-4" />
                  </ButtonLink>
                ) : (
                  <ButtonLink href="/pricing" size="md">
                    Get it when it ships — $19
                    <Icon name="arrowRight" className="h-4 w-4" />
                  </ButtonLink>
                )}
                <ButtonLink href="/tools" variant="ghost" size="md">
                  All tools
                </ButtonLink>
              </div>

              <div className="mt-5 flex flex-wrap gap-x-5 gap-y-2 text-[0.72rem] text-slate">
                {[
                  "On-device",
                  "No account",
                  "Original files untouched",
                  "Included in one purchase",
                ].map((item) => (
                  <span key={item} className="flex items-center gap-1.5">
                    <Icon name="check" className="h-3 w-3 text-mint-deep" strokeWidth={2.6} />
                    {item}
                  </span>
                ))}
              </div>
            </div>

            <aside className="rounded-2xl border border-line bg-white p-5 shadow-[0_20px_50px_-32px_rgba(10,11,14,0.4)]">
              <div className="flex items-center justify-between">
                <p className="text-[0.66rem] font-semibold uppercase tracking-[0.12em] text-slate-2">
                  At a glance
                </p>
                {tool.implemented ? (
                  <Badge tone="mint">Ready</Badge>
                ) : (
                  <Badge tone="outline">Roadmap</Badge>
                )}
              </div>
              <dl className="mt-4 space-y-3">
                {[
                  { k: "Category", v: cat?.name ?? tool.category },
                  { k: "Runs on", v: "macOS 14+" },
                  { k: "Where it runs", v: "On this Mac" },
                  { k: "Output", v: tool.category === "mac" || tool.category === "developer" ? "In the window, or Downloads" : "Dated folder in Downloads" },
                  { k: "Status", v: tool.implemented ? "Included in this build" : "Free update when ready" },
                ].map((row) => (
                  <div key={row.k} className="flex items-start justify-between gap-3 border-b border-line pb-2.5 last:border-0 last:pb-0">
                    <dt className="text-[0.72rem] text-slate-2">{row.k}</dt>
                    <dd className="text-right text-[0.76rem] font-medium">{row.v}</dd>
                  </div>
                ))}
              </dl>
              <div className="mt-4 rounded-xl bg-paper p-3">
                <p className="flex items-start gap-2 text-[0.7rem] leading-relaxed text-slate">
                  <Icon name="shield" className="mt-0.5 h-3.5 w-3.5 shrink-0 text-mint-deep" />
                  The file you open is never uploaded, moved or overwritten.
                </p>
              </div>
            </aside>
          </div>
        </div>
      </section>

      <section className="wrap py-14">
        <div className="grid gap-10 lg:grid-cols-[0.8fr_1.2fr]">
          <div>
            <p className="eyebrow">How it works</p>
            <h2 className="mt-3 text-[clamp(1.7rem,3vw,2.4rem)] font-semibold leading-tight">
              Three steps, no wizard.
            </h2>
            <p className="mt-3 max-w-sm text-[0.88rem] leading-relaxed text-slate">
              {tool.name} behaves like the rest of Nookit: one window, only the
              settings this job needs, and a result you can find afterwards.
            </p>
            {!tool.implemented ? (
              <div className="mt-6 rounded-2xl border border-line bg-paper-2/60 p-4">
                <p className="flex items-center gap-2 text-[0.78rem] font-semibold">
                  <Icon name="info" className="h-4 w-4 text-ember" />
                  On the roadmap
                </p>
                <p className="mt-2 text-[0.78rem] leading-relaxed text-slate">
                  This tool is specified and included in your licence, but it is not
                  in the current build. Buying today funds the work; it arrives as a
                  free update. You can also{" "}
                  <a
                    href="mailto:support@nookit.app?subject=Prioritise%20a%20tool"
                    className="font-semibold text-ink underline decoration-line-strong underline-offset-2"
                  >
                    ask us to prioritise it
                  </a>
                  .
                </p>
              </div>
            ) : null}
          </div>
          <ol className="space-y-3">
            {detail.steps.map((step, i) => (
              <li
                key={step.title}
                className="flex gap-4 rounded-2xl border border-line bg-white/70 p-4"
              >
                <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-ink font-mono text-[0.68rem] text-paper">
                  0{i + 1}
                </span>
                <div>
                  <h3 className="text-[0.94rem] font-semibold">{step.title}</h3>
                  <p className="mt-1 text-[0.82rem] leading-relaxed text-slate">
                    {step.body}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        </div>

        <div className="mt-12 grid gap-3 md:grid-cols-3">
          {detail.notes.map((note) => (
            <div key={note} className="rounded-xl border border-line bg-paper-2/40 p-4">
              <Icon name="check" className="h-4 w-4 text-mint-deep" strokeWidth={2.4} />
              <p className="mt-2 text-[0.78rem] leading-relaxed text-slate">{note}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="wrap pb-16">
        <div className="rounded-[26px] bg-ink p-6 text-paper md:p-10">
          <div className="grid gap-8 md:grid-cols-[1.1fr_0.9fr] md:items-center">
            <div>
              <p className="eyebrow !text-paper/40">Included, not an add-on</p>
              <h2 className="mt-2 text-[clamp(1.7rem,3vw,2.5rem)] font-semibold leading-tight">
                {tool.name} is one of {tools.length}. So is the notch.
              </h2>
              <p className="mt-3 max-w-lg text-[0.88rem] leading-relaxed text-paper/55">
                One licence covers the whole catalogue and all {counts.notch} notch
                modules. No credits, no per-export limit, no second subscription.
              </p>
              <div className="mt-5 flex flex-wrap gap-3">
                <ButtonLink href="/pricing" size="md">
                  Buy Nookit — $19
                  <Icon name="arrowRight" className="h-4 w-4" />
                </ButtonLink>
                <ButtonLink href="/download" variant="light" size="md">
                  How to install
                </ButtonLink>
              </div>
            </div>
            <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
              <p className="flex items-center gap-2 text-[0.72rem] font-semibold text-paper/70">
                <StatusBadge tool={tool} dark />
              </p>
              <p className="mt-3 text-[0.78rem] leading-relaxed text-paper/45">
                {tool.implemented
                  ? `${tool.name} is in the current build. Open it from the dashboard, or search with ⌘K in the app.`
                  : `${tool.name} appears in the dashboard with its full specification while it is being built. When it ships, it unlocks in place — nothing else to buy.`}
              </p>
            </div>
          </div>
        </div>
      </section>

      {related.length > 0 ? (
        <section className="wrap pb-16">
          <div className="flex items-end justify-between gap-4 border-b border-line pb-3">
            <div>
              <p className="eyebrow">More in {cat?.name}</p>
              <h2 className="mt-2 text-[1.4rem] font-semibold tracking-[-0.02em]">
                While you are here
              </h2>
            </div>
            <Link
              href={`/tools#${tool.category}`}
              className="text-[0.78rem] font-semibold text-slate hover:text-ink"
            >
              See all
            </Link>
          </div>
          <div className="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
            {related.map((t) => (
              <ToolCard key={t.slug} tool={t} />
            ))}
          </div>
        </section>
      ) : null}

      <section className="border-t border-line bg-paper-2/30">
        <div className="wrap grid gap-8 py-14 lg:grid-cols-[0.7fr_1.3fr]">
          <div>
            <p className="eyebrow">Before you buy</p>
            <h2 className="mt-2 text-[1.7rem] font-semibold leading-tight">
              The honest answers.
            </h2>
          </div>
          <Reveal>
            <FaqList items={faq} />
          </Reveal>
        </div>
      </section>

      <section className="wrap py-14">
        <ComparisonTable />
      </section>
    </>
  );
}
