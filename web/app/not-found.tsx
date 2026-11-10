import Link from "next/link";
import { CommandPaletteTrigger } from "@/components/command-palette";
import { Icon } from "@/components/icons";
import { ButtonLink } from "@/components/ui";
import { categories } from "@/lib/catalog";

export default function NotFound() {
  return (
    <section className="wrap flex min-h-[70vh] max-w-2xl flex-col items-center justify-center py-20 text-center">
      <p className="font-mono text-[0.72rem] font-semibold uppercase tracking-[0.16em] text-ember-deep">
        404
      </p>
      <h1 className="mt-4 text-[clamp(2.2rem,6vw,3.6rem)] font-semibold leading-[1.0]">
        That tool is not here.
      </h1>
      <p className="mt-3 max-w-md text-[0.94rem] leading-relaxed text-slate">
        The page may have moved, or the link may be from an older build. Search the
        catalogue, or start from the dashboard.
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        <CommandPaletteTrigger />
        <ButtonLink href="/tools" size="md">
          Browse all tools
          <Icon name="arrowRight" className="h-4 w-4" />
        </ButtonLink>
        <ButtonLink href="/" variant="ghost" size="md">
          Home
        </ButtonLink>
      </div>
      <div className="mt-10 flex flex-wrap justify-center gap-2">
        {categories.map((cat) => (
          <Link
            key={cat.id}
            href={`/tools#${cat.id}`}
            className="rounded-full border border-line bg-white/60 px-3 py-1.5 text-[0.74rem] font-medium text-slate hover:border-ink hover:text-ink"
          >
            {cat.name}
          </Link>
        ))}
      </div>
    </section>
  );
}
