import { COMPARISON } from "@/lib/site";
import { Icon } from "./icons";

export function ComparisonTable() {
  return (
    <div className="overflow-hidden rounded-[22px] border border-line bg-white">
      <div className="hidden grid-cols-[1.4fr_1fr_1fr] gap-4 border-b border-line bg-paper-2/60 px-5 py-3 text-[0.64rem] font-semibold uppercase tracking-[0.12em] text-slate-2 md:grid">
        <span>The job</span>
        <span>What it usually costs</span>
        <span>In Nookit</span>
      </div>
      <div className="divide-y divide-line">
        {COMPARISON.map((row) => (
          <div
            key={row.job}
            className="grid gap-2 px-5 py-3.5 md:grid-cols-[1.4fr_1fr_1fr] md:items-center md:gap-4"
          >
            <p className="text-[0.86rem] font-semibold">{row.job}</p>
            <p className="text-[0.78rem] text-slate">{row.elsewhere}</p>
            <div className="flex flex-wrap gap-1.5">
              {row.nookit.map((item) => (
                <span
                  key={item}
                  className="inline-flex items-center gap-1 rounded-full bg-mint/15 px-2 py-1 text-[0.68rem] font-semibold text-mint-deep"
                >
                  <Icon name="check" className="h-2.5 w-2.5" strokeWidth={3} />
                  {item}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="flex items-start gap-2 border-t border-line bg-paper-2/40 px-5 py-3">
        <Icon name="info" className="mt-0.5 h-3.5 w-3.5 shrink-0 text-slate-2" />
        <p className="text-[0.68rem] leading-relaxed text-slate">
          Prices are rough, change over time, and some good options are free. A
          dedicated app can go deeper than a single tool here. Nookit covers the
          everyday version of each job for one price — and the notch is included,
          not a second licence.
        </p>
      </div>
    </div>
  );
}
