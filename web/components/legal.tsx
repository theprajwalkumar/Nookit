import type { ReactNode } from "react";

export function LegalShell({
  eyebrow,
  title,
  updated,
  intro,
  children,
}: {
  eyebrow: string;
  title: string;
  updated: string;
  intro: string;
  children: ReactNode;
}) {
  return (
    <>
      <section className="border-b border-line bg-paper-2/30">
        <div className="wrap py-14 md:py-18">
          <p className="eyebrow">{eyebrow}</p>
          <h1 className="mt-3 max-w-3xl text-[clamp(2.2rem,4.6vw,3.6rem)] font-semibold leading-[1]">
            {title}
          </h1>
          <p className="mt-4 max-w-2xl text-[0.95rem] leading-relaxed text-slate">
            {intro}
          </p>
          <p className="mt-5 text-[0.72rem] text-slate-2">Last updated: {updated}</p>
        </div>
      </section>
      <section className="wrap max-w-3xl py-12">
        <div className="space-y-9">{children}</div>
        <p className="mt-12 border-t border-line pt-5 text-[0.72rem] leading-relaxed text-slate-2">
          This document is written in plain English so it is useful, not just
          enforceable. If anything is unclear, email support@nookit.app and we will
          explain it. It is not legal advice to you, and we recommend a lawyer review
          before publishing a commercial product.
        </p>
      </section>
    </>
  );
}

export function LegalSection({
  title,
  children,
  id,
}: {
  title: string;
  children: ReactNode;
  id?: string;
}) {
  return (
    <section id={id} className="scroll-mt-28">
      <h2 className="text-[1.1rem] font-semibold tracking-[-0.02em]">{title}</h2>
      <div className="mt-2.5 space-y-2.5 text-[0.88rem] leading-relaxed text-slate">
        {children}
      </div>
    </section>
  );
}
