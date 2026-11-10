"use client";

import { useState } from "react";
import { Icon } from "./icons";

export function FaqList({
  items,
  dark = false,
}: {
  items: { q: string; a: string }[];
  dark?: boolean;
}) {
  const [open, setOpen] = useState<number | null>(0);

  return (
    <div className={`divide-y ${dark ? "divide-white/10" : "divide-line"}`}>
      {items.map((item, index) => {
        const isOpen = open === index;
        return (
          <div key={item.q}>
            <button
              type="button"
              onClick={() => setOpen(isOpen ? null : index)}
              aria-expanded={isOpen}
              className={`flex w-full items-center justify-between gap-4 py-5 text-left text-[0.95rem] font-semibold transition-colors ${
                dark ? "text-paper hover:text-white" : "text-ink hover:text-ember-deep"
              }`}
            >
              <span>{item.q}</span>
              <span
                className={`grid h-6 w-6 shrink-0 place-items-center rounded-full border transition-transform duration-200 ${
                  dark ? "border-white/15" : "border-line-strong"
                } ${isOpen ? "rotate-45" : ""}`}
              >
                <Icon name="plus" className="h-3.5 w-3.5" />
              </span>
            </button>
            <div
              className={`grid transition-[grid-template-rows,opacity] duration-300 ease-out ${
                isOpen ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"
              }`}
            >
              <div className="overflow-hidden">
                <p
                  className={`max-w-3xl pb-5 pr-10 text-[0.88rem] leading-relaxed ${
                    dark ? "text-paper/55" : "text-slate"
                  }`}
                >
                  {item.a}
                </p>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
