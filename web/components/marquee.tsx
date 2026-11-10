import { tools } from "@/lib/catalog";

export function ToolMarquee() {
  const names = tools.filter((t) => t.implemented).map((t) => t.name);
  const row = [...names, ...names];
  return (
    <div className="relative overflow-hidden border-y border-line bg-paper-2/50 py-3">
      <div className="pointer-events-none absolute inset-y-0 left-0 z-10 w-20 bg-gradient-to-r from-paper to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 z-10 w-20 bg-gradient-to-l from-paper to-transparent" />
      <div className="marquee-track flex w-max items-center gap-6 whitespace-nowrap">
        {row.map((name, i) => (
          <span
            key={`${name}-${i}`}
            className="flex items-center gap-6 text-[0.72rem] font-medium text-slate"
          >
            {name}
            <span className="h-1 w-1 rounded-full bg-line-strong" />
          </span>
        ))}
      </div>
    </div>
  );
}
