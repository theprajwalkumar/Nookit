import Link from "next/link";
import type { ReactNode } from "react";
import { categoryMeta, getCategory, type Tool } from "@/lib/catalog";
import { Icon, iconForSymbol, type IconName } from "./icons";

export function Badge({
  children,
  tone = "neutral",
  className = "",
}: {
  children: ReactNode;
  tone?: "neutral" | "ember" | "mint" | "dark" | "outline";
  className?: string;
}) {
  const tones = {
    neutral: "bg-paper-2 text-slate",
    ember: "bg-ember/10 text-ember-deep",
    mint: "bg-mint/15 text-mint-deep",
    dark: "bg-white/10 text-paper",
    outline: "border border-line-strong text-slate",
  };
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[0.68rem] font-semibold tracking-[0.01em] ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  );
}

export function StatusBadge({ tool, dark = false }: { tool: Tool; dark?: boolean }) {
  if (tool.implemented) {
    return (
      <Badge tone={dark ? "mint" : "mint"}>
        <span className="h-1.5 w-1.5 rounded-full bg-mint-deep" />
        Ready now
      </Badge>
    );
  }
  return (
    <Badge tone={dark ? "dark" : "outline"}>
      <span className="h-1.5 w-1.5 rounded-full bg-current opacity-50" />
      On the roadmap
    </Badge>
  );
}

export function ToolGlyph({
  tool,
  size = "md",
  className = "",
}: {
  tool: Tool;
  size?: "sm" | "md" | "lg";
  className?: string;
}) {
  const meta = categoryMeta[tool.category];
  const icon = iconForSymbol(tool.symbol);
  const box = {
    sm: "h-8 w-8 rounded-[8px]",
    md: "h-10 w-10 rounded-[10px]",
    lg: "h-14 w-14 rounded-[14px]",
  }[size];
  const glyph = { sm: "h-4 w-4", md: "h-5 w-5", lg: "h-7 w-7" }[size];
  return (
    <span
      className={`inline-flex shrink-0 items-center justify-center ${box} ${className}`}
      style={{ backgroundColor: meta.tintSoft, color: meta.tint }}
    >
      <Icon name={icon} className={glyph} strokeWidth={1.8} />
    </span>
  );
}

export function CategoryGlyph({
  category,
  className = "",
}: {
  category: string;
  className?: string;
}) {
  const cat = getCategory(category);
  const meta = categoryMeta[category as keyof typeof categoryMeta];
  if (!cat || !meta) return null;
  return (
    <span
      className={`inline-flex h-7 w-7 items-center justify-center rounded-[7px] ${className}`}
      style={{ backgroundColor: meta.tintSoft, color: meta.tint }}
    >
      <Icon name={meta.icon as IconName} className="h-4 w-4" />
    </span>
  );
}

export function SectionHeader({
  eyebrow,
  title,
  body,
  align = "left",
  dark = false,
  action,
}: {
  eyebrow?: string;
  title: ReactNode;
  body?: ReactNode;
  align?: "left" | "center";
  dark?: boolean;
  action?: ReactNode;
}) {
  return (
    <div
      className={`flex flex-col gap-4 ${
        align === "center" ? "items-center text-center" : "items-start"
      } ${action ? "md:flex-row md:items-end md:justify-between" : ""}`}
    >
      <div className={align === "center" ? "max-w-2xl" : "max-w-3xl"}>
        {eyebrow ? (
          <p className={`eyebrow mb-3 ${dark ? "!text-paper/50" : ""}`}>{eyebrow}</p>
        ) : null}
        <h2
          className={`text-[clamp(1.9rem,4vw,3.15rem)] font-semibold leading-[1.03] ${
            dark ? "text-paper" : "text-ink"
          }`}
        >
          {title}
        </h2>
        {body ? (
          <p
            className={`mt-4 max-w-2xl text-[0.98rem] leading-relaxed ${
              dark ? "text-paper/60" : "text-slate"
            }`}
          >
            {body}
          </p>
        ) : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </div>
  );
}

export function ButtonLink({
  href,
  children,
  variant = "primary",
  size = "md",
  className = "",
  external = false,
}: {
  href: string;
  children: ReactNode;
  variant?: "primary" | "dark" | "ghost" | "light";
  size?: "sm" | "md" | "lg";
  className?: string;
  external?: boolean;
}) {
  const variants = {
    primary:
      "bg-ember text-white shadow-[0_10px_24px_-10px_rgba(255,90,31,0.7)] hover:bg-ember-deep",
    dark: "bg-ink text-paper hover:bg-ink-2",
    ghost:
      "border border-line-strong bg-transparent text-ink hover:border-ink hover:bg-white/50",
    light: "bg-paper text-ink hover:bg-white",
  };
  const sizes = {
    sm: "h-9 px-3.5 text-[0.82rem]",
    md: "h-11 px-5 text-[0.9rem]",
    lg: "h-12 px-6 text-[0.95rem]",
  };
  const cls = `inline-flex items-center justify-center gap-2 rounded-full font-semibold transition-colors duration-150 ${variants[variant]} ${sizes[size]} ${className}`;
  if (external) {
    return (
      <a href={href} className={cls} rel="noreferrer">
        {children}
      </a>
    );
  }
  return (
    <Link href={href} className={cls}>
      {children}
    </Link>
  );
}

export function ArrowLink({
  href,
  children,
  dark = false,
  className = "",
}: {
  href: string;
  children: ReactNode;
  dark?: boolean;
  className?: string;
}) {
  return (
    <Link
      href={href}
      className={`group inline-flex items-center gap-1.5 text-[0.86rem] font-semibold ${
        dark ? "text-paper/80 hover:text-paper" : "text-ink hover:text-ember-deep"
      } ${className}`}
    >
      {children}
      <Icon
        name="arrowRight"
        className="h-3.5 w-3.5 transition-transform duration-200 group-hover:translate-x-0.5"
      />
    </Link>
  );
}

export function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="inline-flex h-5 min-w-5 items-center justify-center rounded-[5px] border border-line-strong bg-white/70 px-1.5 font-mono text-[0.66rem] font-medium text-slate">
      {children}
    </kbd>
  );
}

export function WindowBar({ title = "Nookit" }: { title?: string }) {
  return (
    <div className="window-bar">
      <span className="traffic bg-[#ff5f57]" />
      <span className="traffic bg-[#febc2e]" />
      <span className="traffic bg-[#28c840]" />
      <span className="ml-3 text-[0.72rem] font-medium text-white/45">{title}</span>
    </div>
  );
}
