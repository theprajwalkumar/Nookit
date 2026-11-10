"use client";

import { useEffect, useState } from "react";
import { counts, product, readyNotch } from "@/lib/catalog";
import {
  checkoutIsConfigured,
  checkoutUrl,
  LAUNCH_ENDS,
  TIERS,
  type Tier,
} from "@/lib/site";
import { Icon } from "./icons";
import { Badge } from "./ui";

const INCLUDED = [
  `All ${counts.tools} tools — ready today`,
  `All ${counts.notch} notch modules — ${readyNotch.length} ready today, the rest as they land`,
  "Free updates for the life of the product",
  "Works offline after activation",
  "Signed and notarized before release",
  "14-day refund, no interrogation",
];

export function PricingCards({ id = "pricing" }: { id?: string }) {
  const [tierId, setTierId] = useState<Tier["id"]>("three");
  const [launchActive, setLaunchActive] = useState(true);
  const tier = TIERS.find((t) => t.id === tierId) ?? TIERS[1];
  const save = Math.round((1 - tier.price / tier.compareAt) * 100);
  const href = checkoutUrl(tier.id);

  useEffect(() => {
    setLaunchActive(Date.now() < LAUNCH_ENDS);
  }, []);

  return (
    <div id={id} className="scroll-mt-24">
      <div className="mx-auto max-w-md">
        <div
          className="mb-4 flex rounded-full border border-line bg-paper-2 p-1"
          role="tablist"
          aria-label="Licence size"
        >
          {TIERS.map((t) => (
            <button
              key={t.id}
              type="button"
              role="tab"
              aria-selected={tierId === t.id}
              onClick={() => setTierId(t.id)}
              className={`relative flex-1 rounded-full px-3 py-2 text-[0.78rem] font-semibold transition-colors ${
                tierId === t.id
                  ? "bg-ink text-paper shadow-sm"
                  : "text-slate hover:text-ink"
              }`}
            >
              {t.label}
              {t.best ? (
                <span
                  className={`absolute -top-2 left-1/2 -translate-x-1/2 rounded-full px-1.5 py-0.5 text-[0.55rem] font-bold uppercase tracking-wide ${
                    tierId === t.id ? "bg-ember text-white" : "bg-ember/10 text-ember-deep"
                  }`}
                >
                  Best
                </span>
              ) : null}
            </button>
          ))}
        </div>

        <div className="overflow-hidden rounded-[26px] border border-line bg-white shadow-lift">
          <div className="relative border-b border-line bg-gradient-to-b from-paper to-white p-6">
            <div className="flex items-start justify-between">
              <div>
                <p className="eyebrow">
                  {launchActive ? `Launch price · ${save}% off` : "One-time licence"}
                </p>
                <div className="mt-2 flex items-end gap-2">
                  <span className="text-[3.1rem] font-semibold leading-none tracking-[-0.05em]">
                    ${tier.price}
                  </span>
                  {launchActive ? (
                    <span className="pb-1 text-[0.95rem] text-slate line-through">
                      ${tier.compareAt.toFixed(2)}
                    </span>
                  ) : null}
                </div>
                <p className="mt-1 text-[0.8rem] text-slate">
                  once · {tier.macs} {tier.macs === 1 ? "Mac" : "Macs"} · {tier.note}
                </p>
              </div>
              <span className="inline-flex h-12 w-12 items-center justify-center rounded-[13px] bg-ink text-paper">
                <Icon name="bolt" className="h-6 w-6 text-ember-soft" />
              </span>
            </div>

            <a
              href={href}
              className="mt-5 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-ember text-[0.92rem] font-semibold text-white shadow-[0_12px_26px_-12px_rgba(255,90,31,0.8)] transition-colors hover:bg-ember-deep"
            >
              Buy Nookit — ${tier.price}
              <Icon name="arrowRight" className="h-4 w-4" />
            </a>
            <p className="mt-2.5 text-center text-[0.68rem] text-slate-2">
              {checkoutIsConfigured()
                ? "Secure checkout · Taxes calculated at checkout · Key by email"
                : "Pre-release · Order by email · Build and key at launch"}
            </p>
          </div>

          <div className="p-6">
            <p className="text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-slate-2">
              Included
            </p>
            <ul className="mt-3 space-y-2.5">
              {INCLUDED.map((item) => (
                <li key={item} className="flex gap-2.5 text-[0.82rem] leading-snug">
                  <Icon
                    name="check"
                    className="mt-0.5 h-3.5 w-3.5 shrink-0 text-mint-deep"
                    strokeWidth={2.4}
                  />
                  <span className="text-slate">{item}</span>
                </li>
              ))}
            </ul>

            <div className="mt-5 flex flex-wrap gap-2 border-t border-line pt-4">
              <Badge tone="mint">macOS 14+</Badge>
              <Badge tone="neutral">Apple silicon & Intel</Badge>
              <Badge tone="neutral">Works without a notch</Badge>
            </div>
          </div>
        </div>

        <div className="mt-4 flex items-center justify-center gap-4 text-[0.7rem] text-slate">
          <span className="flex items-center gap-1.5">
            <Icon name="lock" className="h-3.5 w-3.5" />
            Notarized at release
          </span>
          <span className="h-3 w-px bg-line-strong" />
          <span className="flex items-center gap-1.5">
            <Icon name="shield" className="h-3.5 w-3.5" />
            14-day refund
          </span>
          <span className="h-3 w-px bg-line-strong" />
          <span className="flex items-center gap-1.5">
            <Icon name="check" className="h-3.5 w-3.5" />
            No subscription
          </span>
        </div>

        <p className="mt-3 text-center text-[0.68rem] text-slate-2">
          Need 10+ Macs or an invoice?{" "}
          <a
            href={`mailto:${product.support}?subject=Nookit%20team%20licence`}
            className="font-semibold text-ink underline decoration-line-strong underline-offset-2"
          >
            {product.support}
          </a>
        </p>
      </div>
    </div>
  );
}
