import type { Metadata } from "next";
import Link from "next/link";
import { Icon } from "@/components/icons";
import { ToolCatalog } from "@/components/tool-catalog";
import { Badge, ButtonLink, SectionHeader } from "@/components/ui";
import { categories, counts, tools } from "@/lib/catalog";

export const metadata: Metadata = {
  title: "All 94 Mac tools",
  description:
    "The full Nookit catalogue: video, audio, images, documents, text and speech, files, Mac utilities and developer tools. All 94 tools are ready in this build.",
  alternates: { canonical: "/tools" },
};

export default function ToolsPage() {
  return (
    <>
      <section className="relative overflow-hidden border-b border-line">
        <div className="pointer-events-none absolute inset-0 dot-grid opacity-40 [mask-image:radial-gradient(ellipse_60%_70%_at_50%_0%,black,transparent)]" />
        <div className="wrap relative py-14 md:py-18">
          <nav className="flex items-center gap-2 text-[0.72rem] text-slate">
            <Link href="/" className="hover:text-ink">
              Nookit
            </Link>
            <Icon name="chevronDown" className="h-3 w-3 -rotate-90" />
            <span className="text-ink">All tools</span>
          </nav>

          <div className="mt-6 flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div>
              <p className="eyebrow">The catalogue</p>
              <h1 className="mt-3 text-[clamp(2.4rem,5.4vw,4rem)] font-semibold leading-[0.98]">
                Every tool.
                <br />
                One purchase.
              </h1>
              <p className="mt-4 max-w-xl text-[0.95rem] leading-relaxed text-slate">
                {counts.tools} tools across {categories.length} categories.{" "}
                All {counts.implementedTools} are ready in this build, each with its
                own screen and real status.
              </p>
            </div>
            <div className="grid grid-cols-3 gap-3 md:min-w-[320px]">
              {[
                { k: counts.tools, v: "in the catalogue" },
                { k: counts.implementedTools, v: "ready now" },
                { k: counts.notch, v: "notch modules" },
              ].map((s) => (
                <div
                  key={s.v}
                  className="rounded-xl border border-line bg-white/70 px-3 py-3 text-center"
                >
                  <p className="text-[1.5rem] font-semibold leading-none tracking-[-0.03em]">
                    {s.k}
                  </p>
                  <p className="mt-1 text-[0.6rem] uppercase tracking-[0.08em] text-slate-2">
                    {s.v}
                  </p>
                </div>
              ))}
            </div>
          </div>

          <div className="mt-7 flex flex-wrap gap-2">
            {categories.map((cat) => (
              <a
                key={cat.id}
                href={`#${cat.id}`}
                className="inline-flex items-center gap-1.5 rounded-full border border-line-strong bg-white/50 px-3 py-1.5 text-[0.72rem] font-medium text-slate transition-colors hover:border-ink hover:text-ink"
              >
                {cat.name}
                <span className="text-[0.62rem] text-slate-2">{counts.byCategory[cat.id]}</span>
              </a>
            ))}
          </div>
        </div>
      </section>

      <section className="wrap py-12">
        <ToolCatalog />
      </section>

      <section className="wrap pb-20">
        <div className="rounded-[26px] border border-line bg-paper-2/60 p-6 md:p-10">
          <SectionHeader
            eyebrow="How status works"
            title="Every tool in the catalogue is ready in this build."
            body="We list the whole catalogue because people want to see the actual surface area, not a highlight reel. All 94 tools have a working screen today. Future additions and the remaining 14 notch modules are included in your licence when they ship."
            action={
              <ButtonLink href="/pricing" size="md">
                Buy from $19
                <Icon name="arrowRight" className="h-3.5 w-3.5" />
              </ButtonLink>
            }
          />
          <div className="mt-6 flex flex-wrap gap-2">
            <Badge tone="mint">Green dot — ready in this build</Badge>
            <Badge tone="outline">14 notch modules on the roadmap</Badge>
            <Badge tone="neutral">{tools.length} tools total</Badge>
          </div>
        </div>
      </section>
    </>
  );
}
