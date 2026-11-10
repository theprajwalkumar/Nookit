"use client";

import { useEffect } from "react";

/**
 * Locks body scrolling while `active` is true.
 *
 * Several overlays (command palette, mobile menu) can be mounted at once, so the
 * hook counts locks instead of writing `overflow` directly. Without this, the
 * last overlay to unmount would unlock the page even if another is still open.
 */
let locks = 0;
let previousOverflow = "";
let previousPaddingRight = "";

export function useScrollLock(active: boolean) {
  useEffect(() => {
    if (!active) return;

    if (locks === 0) {
      const scrollbar = window.innerWidth - document.documentElement.clientWidth;
      previousOverflow = document.body.style.overflow;
      previousPaddingRight = document.body.style.paddingRight;
      if (scrollbar > 0) {
        const current = Number.parseFloat(
          window.getComputedStyle(document.body).paddingRight,
        );
        const base = Number.isFinite(current) ? current : 0;
        document.body.style.paddingRight = `${base + scrollbar}px`;
      }
      document.body.style.overflow = "hidden";
    }
    locks += 1;

    return () => {
      locks = Math.max(0, locks - 1);
      if (locks === 0) {
        document.body.style.overflow = previousOverflow;
        document.body.style.paddingRight = previousPaddingRight;
      }
    };
  }, [active]);
}
