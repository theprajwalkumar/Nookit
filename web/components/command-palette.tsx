"use client";

import { useRouter } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { categories, getCategory, searchTools, tools } from "@/lib/catalog";
import { useScrollLock } from "@/lib/use-scroll-lock";
import { Icon } from "./icons";
import { Kbd, ToolGlyph } from "./ui";

type PaletteContextValue = { open: () => void };

const PaletteContext = createContext<PaletteContextValue | null>(null);

/**
 * One palette for the whole site. The header, the homepage CTA and the 404
 * page all open this same dialog, so ⌘K never mounts two competing overlays.
 */
export function CommandPaletteProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);

  useScrollLock(open);

  // Focus as soon as the input is attached. A timeout-based focus could be
  // missed if the browser paints late, which left the palette unfocused.
  const attachInput = useCallback((node: HTMLInputElement | null) => {
    inputRef.current = node;
    node?.focus();
  }, []);

  const results = useMemo(() => searchTools(query).slice(0, 30), [query]);

  const close = useCallback(() => {
    setOpen(false);
    setQuery("");
    setActive(0);
    window.requestAnimationFrame(() => previousFocus.current?.focus());
  }, []);

  const show = useCallback(() => {
    previousFocus.current = document.activeElement as HTMLElement | null;
    setOpen(true);
  }, []);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      const mod = event.metaKey || event.ctrlKey;
      if (mod && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen((v) => !v);
        return;
      }
      if (!open) return;
      if (event.key === "Tab") {
        const dialog = dialogRef.current;
        if (!dialog) return;
        const focusable = [
          ...dialog.querySelectorAll<HTMLElement>(
            'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
          ),
        ];
        if (focusable.length === 0) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const current = document.activeElement;
        if (event.shiftKey && (current === first || !dialog.contains(current))) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && (current === last || !dialog.contains(current))) {
          event.preventDefault();
          first.focus();
        }
        return;
      }
      if (event.key === "Escape") {
        event.preventDefault();
        close();
      } else if (event.key === "ArrowDown") {
        event.preventDefault();
        setActive((i) => Math.min(i + 1, results.length - 1));
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        setActive((i) => Math.max(i - 1, 0));
      } else if (event.key === "Enter" && results[active]) {
        event.preventDefault();
        router.push(`/tools/${results[active].slug}`);
        close();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, results, active, close, router]);

  useEffect(() => {
    if (!open) return;
    // Re-focus after the dialog mounts (covers browsers that drop focus when
    // the overlay appears) and make sure the caret is at the end of the query.
    const id = window.requestAnimationFrame(() => {
      const input = inputRef.current;
      if (!input) return;
      input.focus();
      const end = input.value.length;
      input.setSelectionRange(end, end);
    });
    return () => window.cancelAnimationFrame(id);
  }, [open]);

  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>(
      `[data-index="${active}"]`,
    );
    el?.scrollIntoView({ block: "nearest" });
  }, [active]);

  return (
    <PaletteContext.Provider value={{ open: show }}>
      {children}

      {open ? (
        <div
          ref={dialogRef}
          className="fixed inset-0 z-[80] flex items-start justify-center bg-ink/40 px-4 pt-[12vh] backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          aria-label="Search all Nookit tools"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) close();
          }}
        >
          <div className="w-full max-w-xl overflow-hidden rounded-2xl border border-line bg-paper shadow-2xl">
            <div className="flex items-center gap-3 border-b border-line px-4">
              <Icon name="search" className="h-4 w-4 text-slate-2" />
              <input
                ref={attachInput}
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setActive(0);
                }}
                placeholder={`Search ${tools.length} tools — try “pdf”, “json”, “timer”…`}
                className="h-14 flex-1 bg-transparent text-[0.95rem] outline-none placeholder:text-slate-2"
                aria-label="Search tools"
                autoComplete="off"
                spellCheck={false}
              />
              <Kbd>esc</Kbd>
            </div>
            <div ref={listRef} className="max-h-[52vh] overflow-y-auto p-2">
              {results.length === 0 ? (
                <p className="px-3 py-8 text-center text-sm text-slate">
                  Nothing matches “{query}”. Try a category like{" "}
                  <button
                    className="font-semibold text-ink underline decoration-line-strong underline-offset-2"
                    onClick={() => setQuery("video")}
                  >
                    video
                  </button>
                  .
                </p>
              ) : (
                results.map((tool, index) => {
                  const cat = getCategory(tool.category);
                  return (
                    <button
                      key={tool.slug}
                      data-index={index}
                      type="button"
                      onMouseEnter={() => setActive(index)}
                      onClick={() => {
                        router.push(`/tools/${tool.slug}`);
                        close();
                      }}
                      className={`flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left ${
                        index === active ? "bg-ink text-paper" : "text-ink hover:bg-paper-2"
                      }`}
                    >
                      <ToolGlyph tool={tool} size="sm" />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[0.88rem] font-semibold">
                          {tool.name}
                        </span>
                        <span
                          className={`block truncate text-[0.75rem] ${
                            index === active ? "text-paper/55" : "text-slate"
                          }`}
                        >
                          {cat?.name} · {tool.tagline}
                        </span>
                      </span>
                      {tool.implemented ? (
                        <span
                          className={`text-[0.62rem] font-semibold uppercase tracking-wide ${
                            index === active ? "text-mint" : "text-mint-deep"
                          }`}
                        >
                          Ready
                        </span>
                      ) : null}
                    </button>
                  );
                })
              )}
            </div>
            <div className="flex items-center justify-between border-t border-line px-4 py-2.5 text-[0.68rem] text-slate">
              <span>
                {results.length} of {tools.length} tools · {categories.length}{" "}
                categories
              </span>
              <span className="flex items-center gap-2">
                <span className="flex items-center gap-1">
                  <Kbd>↑</Kbd>
                  <Kbd>↓</Kbd> move
                </span>
                <span className="flex items-center gap-1">
                  <Kbd>↵</Kbd> open
                </span>
              </span>
            </div>
          </div>
        </div>
      ) : null}
    </PaletteContext.Provider>
  );
}

function usePalette() {
  const ctx = useContext(PaletteContext);
  if (!ctx) {
    throw new Error("Command palette trigger used outside its provider");
  }
  return ctx;
}

/** Header pill: "Search ⌘K". */
export function CommandPalette() {
  const { open } = usePalette();
  return (
    <button
      type="button"
      onClick={open}
      className="hidden h-9 items-center gap-2 rounded-full border border-line-strong bg-white/60 px-3 text-[0.8rem] text-slate transition-colors hover:border-ink/30 hover:text-ink md:inline-flex"
      aria-label="Search tools"
      aria-haspopup="dialog"
    >
      <Icon name="search" className="h-3.5 w-3.5" />
      Search
      <span className="ml-4 inline-flex items-center gap-0.5">
        <Kbd>⌘</Kbd>
        <Kbd>K</Kbd>
      </span>
    </button>
  );
}

/** Inline CTA used on the homepage and 404 page. Visible at every width. */
export function CommandPaletteTrigger() {
  const { open } = usePalette();
  return (
    <button
      type="button"
      onClick={open}
      className="inline-flex h-9 items-center gap-2 rounded-full border border-line-strong bg-paper px-3.5 text-[0.82rem] font-medium text-ink transition-colors hover:border-ink/40 hover:bg-white"
      aria-haspopup="dialog"
    >
      <Icon name="search" className="h-3.5 w-3.5" />
      Search tools
      <span className="ml-1 inline-flex items-center gap-0.5">
        <Kbd>⌘</Kbd>
        <Kbd>K</Kbd>
      </span>
    </button>
  );
}

export function SearchTrigger() {
  const { open } = usePalette();
  return (
    <button
      type="button"
      onClick={open}
      className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-line-strong text-slate md:hidden"
      aria-label="Search all tools"
      aria-haspopup="dialog"
    >
      <Icon name="search" className="h-4 w-4" />
    </button>
  );
}
