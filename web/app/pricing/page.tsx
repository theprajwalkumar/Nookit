import type { Metadata } from "next";
import { ComparisonTable } from "@/components/comparison";
import { FaqList } from "@/components/faq-list";
import { Icon } from "@/components/icons";
import { PricingCards } from "@/components/pricing-cards";
import { Reveal } from "@/components/reveal";
import { SectionHeader } from "@/components/ui";
import { counts } from "@/lib/catalog";
import { FAQ } from "@/lib/site";

export const metadata: Metadata = {
  title: "Pricing — one payment, no subscription",
  description:
    "Nookit costs $19 for one Mac, $29 for three or $39 for five. One payment for all 94 tools and 24 notch modules, free updates, and a 14-day refund.",
  alternates: { canonical: "/pricing" },
};

export default function PricingPage() {
  return (
    <>
      <section className="relative overflow-hidden border-b border-line">
        <div className="pointer-events-none absolute inset-0 dot-grid opacity-40 [mask-image:radial-gradient(ellipse_60%_60%_at_50%_0%,black,transparent)]" />
        <div className="wrap relative py-14 md:py-18">
          <div className="mx-auto max-w-2xl text-center">
            <p className="eyebrow">Pricing</p>
            <h1 className="mt-3 text-[clamp(2.4rem,5.4vw,3.9rem)] font-semibold leading-[0.98]">
              Pay once.
              <br />
              Use it every day.
            </h1>
            <p className="mx-auto mt-4 max-w-xl text-[0.95rem] leading-relaxed text-slate">
              One payment for {counts.tools} tools and {counts.notch} notch modules.
              Free updates, no subscription, and no tool held back for a higher tier.
            </p>
            <div className="mt-5 flex flex-wrap justify-center gap-2">
              {["14-day refund", "Key by email", "Offline after activation"].map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center gap-1.5 rounded-full bg-white/70 px-3 py-1 text-[0.7rem] font-medium text-slate"
                >
                  <Icon name="check" className="h-3 w-3 text-mint-deep" strokeWidth={2.6} />
                  {t}
                </span>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="py-14">
        <div className="wrap">
          <PricingCards id="choose" />
        </div>
      </section>

      <section className="border-y border-line bg-paper-2/30 py-16">
        <div className="wrap">
          <Reveal>
            <SectionHeader
              eyebrow="The maths"
              title="Less than most single-purpose apps."
              body="Nookit is not trying to replace a professional editor. It replaces the dozen small apps most people keep around for everyday jobs."
            />
          </Reveal>
          <div className="mt-8">
            <ComparisonTable />
          </div>
        </div>
      </section>

      <section className="py-16">
        <div className="wrap">
          <div className="grid gap-3 md:grid-cols-3">
            {[
              {
                icon: "shield" as const,
                title: "14-day refund",
                body: "If it is not right, ask within 14 days and we will process it. No interrogation, no retention offer.",
              },
              {
                icon: "key" as const,
                title: "A key, not an account",
                body: "Your licence arrives by email. Activate on the number of Macs in your licence — one, three or five. No login required to use the app.",
              },
              {
                icon: "info" as const,
                title: "Roadmap included",
                body: "Roadmap tools are part of the purchase and arrive as free updates. We do not promise a date, and we do not charge again when they land.",
              },
            ].map((item) => (
              <div key={item.title} className="rounded-2xl border border-line bg-white/70 p-5">
                <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-ink text-paper">
                  <Icon name={item.icon} className="h-4 w-4" />
                </span>
                <h2 className="mt-3 text-[1rem] font-semibold">{item.title}</h2>
                <p className="mt-1.5 text-[0.82rem] leading-relaxed text-slate">{item.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="pb-20">
        <div className="wrap max-w-3xl">
          <Reveal>
            <SectionHeader
              eyebrow="Before you buy"
              title="A few honest answers."
            />
            <div className="mt-6">
              <FaqList items={[FAQ[3], FAQ[1], FAQ[8], FAQ[9], FAQ[10], FAQ[11]]} />
            </div>
          </Reveal>
        </div>
      </section>
    </>
  );
}
