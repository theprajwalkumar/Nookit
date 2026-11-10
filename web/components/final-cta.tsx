import { counts, readyNotch } from "@/lib/catalog";
import { Icon, Logo } from "./icons";

export function FinalCta() {
  return (
    <section className="wrap pb-20">
      <div className="relative overflow-hidden rounded-[30px] bg-ink px-6 py-12 text-paper md:px-14 md:py-16">
        <div className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-ember/20 blur-[90px]" />
        <div className="pointer-events-none absolute -bottom-32 left-1/3 h-72 w-72 rounded-full bg-mint/10 blur-[100px]" />
        <div className="relative grid gap-8 md:grid-cols-[1.4fr_1fr] md:items-center">
          <div>
            <div className="mb-5 flex items-center gap-3">
              <Logo tone="paper" />
              <span className="rounded-full border border-white/15 px-2 py-0.5 text-[0.6rem] font-semibold uppercase tracking-[0.1em] text-paper/50">
                for Mac
              </span>
            </div>
            <h2 className="max-w-xl text-[clamp(2rem,4vw,3.1rem)] font-semibold leading-[1.02]">
              {counts.tools} tools. One notch. One payment.
            </h2>
            <p className="mt-4 max-w-lg text-[0.92rem] leading-relaxed text-paper/55">
              All {counts.tools} tools are ready today. The notch keeps growing as a
              free update, and it is part of the app, not another subscription.
            </p>
            <div className="mt-6 flex flex-wrap items-center gap-3">
              <a
                href="/pricing"
                className="inline-flex h-12 items-center gap-2 rounded-full bg-ember px-6 text-[0.92rem] font-semibold text-white transition-colors hover:bg-ember-deep"
              >
                Buy from $19
                <Icon name="arrowRight" className="h-4 w-4" />
              </a>
              <a
                href="/download"
                className="inline-flex h-12 items-center gap-2 rounded-full border border-white/20 px-6 text-[0.92rem] font-semibold text-paper/80 transition-colors hover:border-white/40 hover:text-paper"
              >
                How to install
              </a>
            </div>
          </div>
          <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-5">
            <p className="text-[0.66rem] font-semibold uppercase tracking-[0.12em] text-paper/35">
              What you get
            </p>
            <ul className="mt-3 space-y-2">
              {[
                `All ${counts.tools} tools ready now`,
                `${counts.notch} notch modules — ${readyNotch.length} ready now`,
                "Free updates, no upgrade tier",
                "3 Macs on the 3-Mac licence",
                "14-day refund",
                "No account, no telemetry",
              ].map((item) => (
                <li key={item} className="flex items-center gap-2 text-[0.78rem] text-paper/70">
                  <Icon name="check" className="h-3.5 w-3.5 text-mint" strokeWidth={2.4} />
                  {item}
                </li>
              ))}
            </ul>
            <p className="mt-4 border-t border-white/10 pt-3 text-[0.66rem] leading-relaxed text-paper/35">
              Requires macOS 14 Sonoma or later. Signed and notarized before
              release. Works on Macs with or without a notch.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
